#!/usr/bin/env python3
"""Check the actual Kestrel against all six original coal stop geometries.

Uses live OpenTTD 14.1 road motion and LuanTTD's runtime projection; no
guessed circles or gameplay changes. Run with an optional LUA=/path/to/lua
or on a system with Lua 5.4/5.3 installed as a shared library.
"""
from ctypes import CDLL,c_char_p,c_int,c_void_p
from ctypes.util import find_library
from math import cos,sin
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from small_airport_art import obj,cut,hull,intersects

ROOT=Path(__file__).absolute().parents[1]
M=ROOT/"mods/bayline/models"
KEYS=("straight_0","straight_1","bay_0","bay_1","bay_2","bay_3")
TURN=(0,1,0,-1,-2,-3)
REQUIRED=("Small_weighmaster_booth_timber_shell","Engraved_WEIGH_key",
          "Individual_gauge_graduation_indexes","Cast_iron_balance_deck_weighbridge",
          "Hopper_open_inner_sloping_wear_plate","Visible_open_steel_hopper_rim",
          "Individual_loose_coal_visible_below_hopper_lip","Enamel_raised_COAL_clearance_notice")
SAMPLE=r'''
local root="mods/bayline/"
local K=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
local V=dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua"))
local fd=assert(io.open(OUTPUT_PATH,'w'))
local td={[0]=0,1,8,9}
local function show(key,state,dir,side)
  local r,x,z=K.sample(state,side,0)
  assert(r=="position")
  local v={x=x,y=z,state=state,frame=0,direction=2*dir+1}
  local a={x,z,v.direction,0,1-dir%2}
  local count=0
  for i=1,350 do
    local r,x,z,d,f=K.step(v,side)
    if r~="move" and r~="rotate" then break end
    local b={x,z,d,0,a[5]}
    for j=0,12 do
      local x,z,yaw=V.pose(a,b,j/12)
      fd:write(string.format("%s %d %.8f %.8f %.8f\n",key,side,x-.5,z-.5,math.pi-yaw))
    end
    v.x,v.y,v.direction,v.frame=x,z,d,f
    a=b
    count=count+1
  end
  assert(count>=14)
end
for d=0,3 do
  for side=0,1 do
    show("straight_"..(d%2),64+td[d],d,side)
    show("bay_"..d,32+td[(d+2)%4],(d+2)%4,side)
  end
end
fd:close()
'''

def trace():
    with TemporaryDirectory(prefix="freight-poses-") as d:
        out=Path(d)/"freight.poses"
        script=SAMPLE.replace("OUTPUT_PATH",'"'+str(out)+'"')
        if os.getenv("LUA"):
            subprocess.run([os.environ["LUA"],"-e",script],cwd=ROOT,check=True)
        else:
            so=find_library("lua5.4") or find_library("lua5.3")
            assert so,"Set LUA=/path/to/lua or have a shared Lua 5.4/5.3 library."
            os.chdir(ROOT)
            lib=CDLL(so)
            for name,res,args in (
                ("luaL_newstate",c_void_p,()),("luaL_openlibs",None,(c_void_p,)),
                ("luaL_loadstring",c_int,(c_void_p,c_char_p)),
                ("lua_pcallk",c_int,(c_void_p,c_int,c_int,c_int,c_void_p,c_void_p)),
                ("lua_tolstring",c_char_p,(c_void_p,c_int,c_void_p)),("lua_close",None,(c_void_p,))):
                f=getattr(lib,name);f.restype=res;f.argtypes=args
            L=lib.luaL_newstate();lib.luaL_openlibs(L)
            try:assert not (lib.luaL_loadstring(L,script.encode()) or lib.lua_pcallk(L,0,0,0,None,None)),lib.lua_tolstring(L,-1,None)
            finally:lib.lua_close(L)
        for row in out.read_text().splitlines():
            key,side,x,z,yaw=row.split()
            yield key,int(side),float(x),float(z),float(yaw)

def rotate(x,z,t):
    return ((x,z),(-z,x),(-x,-z),(z,-x))[t%4]

def variants():
    refs={}
    canonical={}
    for key,turn in zip(KEYS,TURN):
        p=M/f"bl_road_freight_stop_{key}.obj"
        v,g=obj(p,(0,0))
        assert all(-.500001<=x<=1.500001 and -.500001<=z<=1.500001 for x,_,z in v)
        assert all(-.020001<=y<=.70 for _,y,_ in v)
        assert not set(REQUIRED)-g.keys(),set(REQUIRED)-g.keys()
        assert len(g["Hopper_open_inner_sloping_wear_plate"])==8
        assert len(g["Visible_open_steel_hopper_rim"])==8
        assert len(g["Individual_gauge_graduation_indexes"])>75
        assert len([l for l in p.read_text().splitlines() if l.startswith("vt ")])==32
        name=key.split("_")[0]
        def as_base(p):
            x,y,z=p
            a,b=rotate(x-.5,z-.5,-turn)
            return a,y,b
        result={n:[tuple(map(as_base,f)) for f in fs] for n,fs in g.items()}
        if name in canonical:
            base=canonical[name]
            assert result.keys()==base.keys()
            for n,fs in result.items():
                assert len(fs)==len(base[n]),(key,n,"triangle count")
                for face,ref in zip(fs,base[n]):
                    assert all(abs(a-b)<2e-6 for p,q in zip(face,ref) for a,b in zip(p,q)),(key,n,face,ref)
        else:canonical[name]=result
        flat=[[(x-.5,z-.5) for x,y,z in f] for f in g.get("Flush_concrete_stock_turnaround_slab",[])
              if all(abs(y-.003)<1e-6 for _,y,_ in f)]
        obstacles=[]
        canopy=[]
        for n,faces in g.items():
            for f in faces:
                poly=cut(cut(f,1,.012,1),1,.30,-1)
                if poly:
                    contour=hull((x-.5,z-.5) for x,_,z in poly)
                    u,w=zip(*contour)
                    obstacles.append((n,min(u),max(u),min(w),max(w),contour))
                if n=="Folded_red_tin_pitched_office_roof":
                    canopy.append(f)
        assert flat if key.startswith("bay_") else not flat
        assert all(y>.41 for f in canopy for _,y,_ in f)
        refs[key]=(obstacles,flat,turn)
    atlas=(ROOT/"mods/bayline/textures/bl_road_freight_stop.png").read_bytes()
    assert atlas[:8]==b"\x89PNG\r\n\x1a\n" and int.from_bytes(atlas[16:20],"big")==256
    assert (ROOT/"art/road_freight_stop.blend").stat().st_size>80000
    return refs

def test_sweeps(refs):
    vertices,_=obj(M/"bl_coal_tipper_loaded.obj")
    assert .265<max(y*.42 for _,y,_ in vertices)<.28
    envelope=hull((x*.42,z*.42) for x,_,z in vertices)
    tires={(x*.42,z*.42) for x,y,z in vertices if abs(y)<1e-6}
    assert tires and len(tires)<80
    seen=set()
    passed=0
    for key,side,x,z,a in trace():
        env=[(x+u*cos(a)-w*sin(a),z+u*sin(a)+w*cos(a)) for u,w in envelope]
        obstacles,apron,turn=refs[key]
        u,w=zip(*env)
        x0,x1,z0,z1=min(u),max(u),min(w),max(w)
        for n,a0,a1,b0,b1,poly in obstacles:
            if a1<x0 or a0>x1 or b1<z0 or b0>z1:continue
            assert not intersects(env,poly),(key,side,n,(x,z,a))
        for u,w in tires:
            point=x+u*cos(a)-w*sin(a),z+u*sin(a)+w*cos(a)
            px,pz=rotate(*point,-turn)
            if apron:
                # Never leave a loaded truck rolling through grass within the
                # stop. The ordinary adjacent road supports it west of the
                # opening, and exists as far as the stub center.
                if px<=.005 and abs(pz)<=.316:continue
                if px<-.999 or abs(pz)>.999:continue
                assert any(intersects([point],p) for p in apron),(key,side,"tire beyond paved apron",px,pz)
            else:
                assert abs(pz)<=.317,(key,side,"tire beyond paved lane",px,pz)
        seen.add((key,side))
        passed+=1
    assert passed>5500 and len(seen)==12,(passed,seen)
    return passed

if __name__=="__main__":
    n=test_sweeps(variants())
    print(f"PASS: 6 bounded coal freight stop meshes and open hopper; {n} loaded-Kestrel stock poses across both drive axes, both traffic sides and four bays; tires supported and equipment clear.")
