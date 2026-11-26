#!/usr/bin/env python3
"""Check the actual Country Airfield OBJ files against ported fixed-wing motion.

Run from any directory: python3 tests/small_airport_art.py
Optional Lua interpreter as LUA=...; otherwise use liblua5.4 if installed.
The aircraft envelope is a conservative convex plan hull plus its full height;
all obstacles that rise above the flat paint were checked, not just walls.
"""
from collections import defaultdict
from ctypes import CDLL, c_char_p, c_int, c_void_p
from ctypes.util import find_library
from math import cos, hypot, pi, sin
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import subprocess
import re

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"mods/luanttd_core/models"
TOP=.5
RUNWAY="Seamless_rolled_runway_wearing_course"
GROUND=.014

def obj(p,tile=None):
    points=[]
    groups=defaultdict(list)
    name=""
    for line in p.read_text().splitlines():
        word,*a=line.split()
        if word=="o":name=a[0]
        elif word=="v":
            x,y,z=map(float,a)
            points.append((-x+2*tile[0],y+TOP,z+2*tile[1]) if tile else (-x/10,y/10,z/10))
        elif word=="f":
            xyz=[points[int(i.split("/")[0])-1] for i in a]
            groups[name].append(xyz)
    assert groups
    return points,groups

def cross(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1])

def hull(points):
    p=sorted(set(points))
    def lower(path):
        stack=[]
        for v in path:
            while len(stack)>1 and cross(stack[-2],stack[-1],v)<=1e-9:stack.pop()
            stack.append(v)
        return stack
    return lower(p)[:-1]+lower(reversed(p))[:-1] if len(p)>2 else p

def plane_mv(e,x,z,angle):
    # Engine direction 7 is (-Z), followed clockwise in world X/Z order.
    u,v=cos(angle),sin(angle)
    return [(x+u*a-v*b,z+v*a+u*b) for a,b in e]

def cut(p,axis,s,sign):
    out=[]
    for a,b in zip(p,p[1:]+p[:1]):
        h,j=(a[axis]-s)*sign,(b[axis]-s)*sign
        if h>=0:out.append(a)
        if h*j<0:
            t=h/(h-j)
            out.append(tuple(u+(v-u)*t for u,v in zip(a,b)))
    return out

def intersects(a,b):
    if any(max(x[k] for x in a)<min(y[k] for y in b)-1e-7 or
           min(x[k] for x in a)>max(y[k] for y in b)+1e-7 for k in (0,1)):
        return False
    for poly in (a,b):
        for c,d in zip(poly,poly[1:]+poly[:1]):
            u,v=c[1]-d[1],d[0]-c[0]
            if hypot(u,v)<1e-8:continue
            s=[u*x+v*z for x,z in a]
            t=[u*x+v*z for x,z in b]
            if min(s)>max(t)+1e-6 or max(s)<min(t)-1e-6:return False
    return True

def footprint():
    all_parts=defaultdict(list)
    for z in range(3):
        for x in range(4):
            vertices,parts=obj(MODEL/f"bl_small_airport_{x}_{z}.obj",(x,z))
            assert all(2*x-.500001<=a<=2*x+1.500001 and 2*z-.500001<=b<=2*z+1.500001 for a,_,b in vertices)
            assert all(-1e-6<=y<=1.8 for _,y,_ in vertices)
            if z==2:
                # Full-width rolling surface is watertight at every internal
                # tile seam. The actual flat wearing course is a single shade.
                for end in (2*x-.5,2*x+1.5):
                    edge=[(y,c) for f in parts[RUNWAY] for a,y,c in f if abs(a-end)<1e-6]
                    assert abs(min(p[1] for p in edge)-3.85)<1e-6 and abs(max(p[1] for p in edge)-5.16)<1e-6
                    assert all(abs(y-.005)<1e-6 for y,_ in edge)
            for n,f in parts.items():all_parts[n].extend(f)
    assert 4500<sum(map(len,all_parts.values()))<26000
    assert all(len(all_parts[k])>10 for k in (
        "Flat_painted_runway_identifiers","Historic_corrugated_steel_hangar_roof",
        "Hangar_longitudinal_opaque_steel_walls","Open_bi-parting_door_leaves_against_flanks",
        "Windsock_brass_swivel_collar","Analog_clock_hour_indexes"))
    png=(ROOT/"mods/luanttd_core/textures/bl_small_airport_atlas.png").read_bytes()
    assert png[:8]==b"\x89PNG\r\n\x1a\n" and int.from_bytes(png[16:20],"big")>=256
    return all_parts

TRACE=r'''
local A=dofile("mods/luanttd_core/openttd/airport_small.lua")
local M=dofile("mods/luanttd_core/openttd/airport_motion.lua")(A)
local out=assert(io.open(DEST,'w'))
local function airport(id,x,z) return {id=id,x=x,z=z,ground=0,flags=0,owner="A"} end
for slot=1,2 do
  local a,b=airport(1,0,0),airport(2,480,324)
  local host={airports={[1]=a,[2]=b},plane_speed=4}
  if slot==2 then b.flags=A.block.TERM1 end
  local v=A.new(a,{owner="A",acceleration=18,max_speed=473,order={kind="station",id=2}})
  local function route(current,goal,leg)
    for i=1,30000 do
      local now,events,err=M.tick(current,v,host);assert(not err,err)
      current=now
      for _,p in ipairs({a,b}) do
        local x,z=v.x-p.x,v.z-p.z
        if x>=-16 and x<80 and z>=-16 and z<64 then
          out:write(string.format("%d %d %d %d %d %d %d %d\n",leg,x,z,v.y-1,v.direction,v.pos,p.id,v.hidden and 1 or 0))
        end
      end
      for _,e in ipairs(events) do if e==goal then return current end end
    end
    error("stalled "..goal)
  end
  b=route(a,"terminal",slot)
  local sx,sz=slot==1 and 32 or 10,23
  assert(v.x==b.x+sx and v.z==b.z+sz and v.direction==7)
  v.loading=nil
  v.order={kind="depot",id=b.id}
  route(b,"hangar",slot+2)
  assert(v.x==b.x+53 and v.z==b.z+3 and v.hidden and v.direction==3)
end
out:close()
'''

def trace():
    with TemporaryDirectory(prefix="country-art-") as d:
        path=Path(d)/"aircraft.poses"
        script=TRACE.replace("DEST",'"'+str(path)+'"')
        if os.environ.get("LUA"):
            subprocess.run([os.environ["LUA"],"-e",script],cwd=ROOT,check=True)
        else:
            primary=find_library("lua5.4") or find_library("lua5.3")
            assert primary,"Set LUA=/path/to/lua or install the Lua 5.4 runtime library."
            os.chdir(ROOT)
            lib=CDLL(primary)
            signatures={
                "luaL_newstate":(c_void_p,), "luaL_openlibs":(None,c_void_p),
                "luaL_loadstring":(c_int,c_void_p,c_char_p),
                "lua_pcallk":(c_int,c_void_p,c_int,c_int,c_int,c_void_p,c_void_p),
                "lua_tolstring":(c_char_p,c_void_p,c_int,c_void_p),
                "lua_close":(None,c_void_p),
            }
            for name,(res,*args) in signatures.items():
                f=getattr(lib,name);f.restype=res;f.argtypes=args
            L=lib.luaL_newstate()
            lib.luaL_openlibs(L)
            try:
                err=lib.luaL_loadstring(L,script.encode()) or lib.lua_pcallk(L,0,0,0,None,None)
                assert not err,lib.lua_tolstring(L,-1,None)
            finally:lib.lua_close(L)
        return [tuple(map(int,r.split())) for r in path.read_text().splitlines()]

def swept(groups, scale=1.0):
    points,_=obj(MODEL/"bl_bayshore_trimotor.obj")
    wing=hull((x,z) for x,_,z in points)
    height=max(p[1] for p in points)
    radius=max(hypot(*p) for p in wing)
    assert .975<radius<.99 and .67<height<.68
    wing=[(x*scale,z*scale) for x,z in wing]
    height*=scale
    radius*=scale
    assert min(y*scale for _,y,_ in points)==0 # original wheel contact datum
    candidates=[(name,p) for name,faces in groups.items() for p in faces
                if max(v[1] for v in p)>GROUND]
    polys=[]
    for name,p in candidates:
        c=cut(cut(p,1,GROUND,1),1,height+.015,-1)
        if not c:continue
        a,b=min(v[0] for v in c),max(v[0] for v in c)
        d,e=min(v[2] for v in c),max(v[2] for v in c)
        polys.append((name,a,b,d,e,hull((x,z) for x,_,z in c)))
    poses=set()
    old=None
    for leg,x,z,y,dir,point,id,hidden in trace():
        if y==0:
            p=(x/8-.5,z/8-.5,dir)
            poses.add((*p,0.0,0.0))
            # Include the exact visual parking pose, even though stock hides it.
            if old is not None and old[:2]==(leg,id):
                px,pz,pa=old[2:]
                arc=(dir-pa+4)%8-4
                if abs(px-x)+abs(pz-z)<=4:
                    for t in (.25,.5,.75):
                        poses.add((p[0]+(px-x)/8*(1-t),p[1]+(pz-z)/8*(1-t),pa,arc,t))
            old=(leg,id,x,z,dir)
        else:old=None
    assert len(poses)>550
    for x,z,d,arc,t in poses:
        b=plane_mv(wing,x,z,-(d+arc*t-7)*pi/4)
        for n,x0,x1,z0,z1,p in polys:
            if x0>x+radius or x1<x-radius or z0>z+radius or z1<z-radius:
                continue
            assert not intersects(b,p),f"{n}: taxi envelope crosses geometry at {(x,z,d,arc,t)}"
    return len(poses)

if __name__=="__main__":
    art=footprint()
    scale_def=(ROOT/"mods/luanttd_core/airport_airframe_art.lua").read_text()
    scale=float(re.search(r"scale=(\.?[0-9.]+)",scale_def)[1])
    count=swept(art, scale)
    print(f"PASS: 12 anchor-local meshes; three joined runway seams; real open hangar and collision-free clearances in {count} stock plane poses at shared scale {scale} (both stands and both hangar paths).")
