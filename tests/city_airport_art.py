#!/usr/bin/env python3
"""Stock 6×6 tile layout, architectural walkways and exact City FTA clearance."""
from argparse import ArgumentParser
from collections import defaultdict
from hashlib import sha1
from math import floor,pi
from pathlib import Path
import os,re,sys

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import small_airport_art as util
from small_airport_art import obj,cut,hull,intersects,plane_mv
MODELS=ROOT/"mods/luanttd_core/models"
FLOOR=.019
RUNWAY="Continuous_City_runway_wearing_course"
STANDS=((2.75,4.625),(6.5,2.25),(4.25,.5))
DEFAULTS_SHA="65dcba0808b1dabce5bc89c4351d32a16f0315e4"
MOVEMENT_SHA="6988c499c81a88cd5f2dc7348f74263e5ceacdac"

def git_blob(path,expected):
    raw=path.read_bytes()
    assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()==expected
    return raw.decode()

def pins(defaults,movement):
    if defaults:
        p=git_blob(defaults,DEFAULTS_SHA).split("_tile_table_city_0 = {")[1].split("};")[0]
        grid={(int(x),int(z)):k for x,z,k in re.findall(r"\{\{(\d+),\s*(\d+)\},\s*APT_([A-Z_0-9]+)\}",p)}
        assert len(grid)==36
        for (x,z),kind in grid.items():
            with (MODELS/f"bl_city_airport_{x}_{z}.obj").open() as f:
                assert f"{x},{z} APT_{kind};" in f.readline()
    if movement:
        p=git_blob(movement,MOVEMENT_SHA).split("_airport_moving_data_city[] = {")[1].split("};")[0]
        pts=[(int(x)/8-.5,int(z)/8-.5) for x,z in re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*\{",p)]
        assert len(pts)==30
        assert tuple(pts[2:5])==STANDS and pts[0]==(10.125,-.125)
        assert pts[9][1]==10.125 and pts[14][1]==10.375

def models():
    groups=defaultdict(list)
    assert len(list(MODELS.glob("bl_city_airport_?_?.obj")))==36
    for x in range(6):
        for z in range(6):
            p=MODELS/f"bl_city_airport_{x}_{z}.obj"
            vv,gg=obj(p,(x,z))
            assert all(2*x-.500001<=a<=2*x+1.500001 and 2*z-.500001<=b<=2*z+1.500001 for a,_,b in vv)
            assert all(-1e-6<=y<=2.279 for _,y,_ in vv)
            if z==5:
                for edge in (2*x-.5,2*x+1.5):
                    on_edge=[(y,c) for f in gg[RUNWAY] for a,y,c in f if abs(a-edge)<1e-7]
                    assert (min(c for _,c in on_edge),max(c for _,c in on_edge))==(9.535,11.375)
                    assert all(abs(y-.01)<1e-6 for y,_ in on_edge)
            for k,fs in gg.items():groups[k].extend(fs)
    count=sum(map(len,groups.values()))
    assert 9000<count<28500,count
    for i,center in enumerate(STANDS,1):
        pc=[(x,z) for f in groups[f"Exact_stand_{i}_golden_stop_bar"] for x,_,z in f]
        assert len(pc)>=6 and all(abs((max(v)+min(v))/2-c)<1e-6 for v,c in zip(zip(*pc),center))
    for k in ("Physically_painted_runway_ordinals","Round_terminal_tint-wrapped_stacked_glass_floors",
              "Each_horizontal_formed_radar_dish_metal_grid","Stowed_split_sliding_steel_door_against_flank",
              "Tapered_tall_stock_airport_tower_column","Alternating_blue_factory_roof_skylight_panes"):
        assert len(groups[k])>=10,k
    assert all(y>.75 for f in groups["High_City_hangar_open_portal_steel_lintel"] for _,y,_ in f)
    terrace=groups["Dedicated_City_passenger_terrace_slab"]
    assert abs(max(v[1] for f in terrace for v in f)-.026)<1e-6
    xy=hull((x,z) for f in terrace for x,y,z in f if abs(y-.026)<1e-6)
    zone=[(1.78,.04),(2.55,.04),(2.55,.78),(1.78,.78)]
    assert all(intersects([p],xy) for p in zone)
    for name,fs in groups.items():
        if name=="Dedicated_City_passenger_terrace_slab":continue
        for f in fs:
            if max(y for _,y,_ in f)>.02601:
                assert not intersects(zone,hull((x,z) for x,y,z in f)),name
    png=(ROOT/"mods/luanttd_core/textures/bl_city_airport_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and int.from_bytes(png[16:20],"big")>=450
    assert int.from_bytes(png[20:24],"big")==8
    print(f"{count:,} triangles; 36 native tiles and every runway seam, exact stands and passenger terrace.")
    return groups

TRACE=r'''
local A=dofile("mods/luanttd_core/openttd/airport_city.lua")
local M=dofile("mods/luanttd_core/openttd/airport_motion.lua")(A)
local out=assert(io.open(DEST,"w"))
local B=A.block
local a={id=1,x=300,z=350,ground=16,rotation=0,width=6,height=6,owner="Oak"}
local b={id=2,x=1031,z=687,ground=32,rotation=0,width=6,height=6,owner=a.owner}
local fields={a,b}
for t=1,3 do
 a.flags,b.flags=0,t==1 and 0 or t==2 and B.TERM1 or B.TERM1+B.TERM2
 local reserved=b.flags
 local p=A.new(a,{owner=a.owner,order={kind="station",id=b.id},acceleration=40,max_speed=947})
 local active=a
 local function record(k,f)
   local x,z,y=p.x-f.x,p.z-f.z,p.y-f.ground-1
   if x>=-8 and x<103 and z>=-8 and z<103 and y==0 then
     out:write(("%d %d %d %d %d %d %d\n"):format(k,f.id,x,z,p.direction,p.pos,p.hidden and 1 or 0))
   end
 end
 local function run(k,goal)
   local seen={}
   local ctx={airports=fields,position=function(_,id)record(k,fields[id])end}
   for i=1,40000 do
     local ev,err
     active,ev,err=M.tick(active,p,ctx)
     assert(not err,err)
     for _,e in ipairs(ev) do
       seen[e]=true
       if e==goal then record(k,active);return seen end
     end
   end
   error("unreached "..goal.." for slot "..t)
 end
 assert(run(t,"terminal").touchdown)
 assert(active==b and p.pos==t+1 and p.loading and p.state==A.terminal_states[t])
 p.loading=nil;p.order={kind="depot",id=b.id}
 run(t+3,"hangar")
 assert(p.hidden and p.pos==0 and b.flags>=reserved)
end
out:close()
'''

def poses():
    prev=os.getcwd()
    util.ROOT=BASE;util.TRACE=TRACE
    try:rows=util.trace()
    finally:os.chdir(prev)
    assert {t for t,*_ in rows}==set(range(1,7))
    seen=set();prev=None
    for t,id,x,z,d,pos,_ in rows:
        xx,zz=x/8-.5,z/8-.5
        seen.add((xx,zz,d,0.,0.,pos))
        if prev and (t,id)==prev[:2]:
            px,pz,pd=prev[2:]
            arc=(d-pd+4)%8-4
            if abs(px-x)+abs(pz-z)<=5:
                for u in (.25,.50,.75):
                    seen.add((xx+(px-x)/8*(1-u),zz+(pz-z)/8*(1-u),pd,arc,u,pos))
        prev=t,id,x,z,d
    assert len(seen)>600,len(seen)
    return seen

def sweep(groups,model,scale,positions):
    vv,plane=obj(model)
    assert min(y for _,y,_ in vv)==0
    components=[[(x*scale,y*scale,z*scale) for x,y,z in f] for fs in plane.values() for f in fs]
    height=max(y*scale for _,y,_ in vv)
    slabs=[]
    def grid(a,b,c,d):
        return ((i,j) for i in range(floor(a),floor(b)+1) for j in range(floor(c),floor(d)+1))
    for i in range(int(height/.05)+1):
        low,up=i*.05-.006,(i+1)*.05+.009001
        aircraft=[]
        for f in components:
            if max(p[1] for p in f)<low or min(p[1] for p in f)>up:continue
            aircraft.extend(cut(cut(f,1,low,1),1,up,-1))
        if not aircraft:continue
        outline=hull((x,z) for x,_,z in aircraft)
        cells=defaultdict(list)
        for n,fs in groups.items():
            for f in fs:
                if max(y for _,y,_ in f)<=max(low,FLOOR) or min(y for _,y,_ in f)>up:continue
                part=cut(cut(f,1,max(low,FLOOR),1),1,up,-1)
                if not part:continue
                a,b=min(v[0] for v in part),max(v[0] for v in part)
                c,d=min(v[2] for v in part),max(v[2] for v in part)
                obstacle=n,a,b,c,d,hull((x,z) for x,_,z in part)
                for cell in grid(a,b,c,d):cells[cell].append(obstacle)
        slabs.append((outline,cells))
    fails=[]
    for x,z,d,a,u,pos in sorted(positions):
        for outline,cells in slabs:
            q=plane_mv(outline,x,z,-(d+a*u-7)*pi/4)
            x0,x1=min(v[0] for v in q),max(v[0] for v in q)
            z0,z1=min(v[1] for v in q),max(v[1] for v in q)
            for n,A,B,C,D,p in (v for c in grid(x0,x1,z0,z1) for v in cells.get(c,())):
                if A>x1 or B<x0 or C>z1 or D<z0:continue
                if intersects(q,p):
                    fails.append((pos,n,x,z,d,a,u))
                    break
            else:continue
            break
    if fails:
        print(f"{model.name}: {len(fails)} intersects: {fails[:30]}")
    assert not fails
    print(f"{model.name}: {len(positions):,} City FTA ground poses clear the authored structures.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--defaults",type=Path)
    p.add_argument("--movement",type=Path)
    p.add_argument("--airframe",action="append",nargs=2,default=[],metavar=("OBJ","SCALE"))
    a=p.parse_args()
    pins(a.defaults,a.movement)
    g=models()
    if a.airframe:
        pp=poses()
        for model,scale in a.airframe:sweep(g,Path(model),float(scale),pp)
    print("CITY_AIRPORT_ART_PASS")
