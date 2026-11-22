#!/usr/bin/env python3
"""Validate the original passenger terminus on all 4 stock bay orientations.

Actual stock road frame and LuanTTD projection modules supply positions and
headings. Load and check all production rigid passenger vehicles at their
runtime sizes, not just a guessed bounding box.
"""
from collections import Counter
from math import cos,pi,sin
from pathlib import Path
import sys

from road_freight_stop_art import trace,rotate
import road_freight_stop_art as stock_trace
from small_airport_art import obj,cut,hull,intersects

ROOT=Path(__file__).absolute().parents[1]
MODEL=ROOT/"mods/bayline/models"
RIM="Continuous_flush_two-bay_concrete_hardstand"
REQUIRED=("Marked_stopping_bay_1_at_exact_projected_parking_throat",
          "Marked_stopping_bay_2_at_exact_projected_parking_throat",
          "Raised_numbered_BAY_1_sign","Raised_numbered_BAY_2_sign",
          "Hardwood_bench_seats","Timetable_printed_block_rules",
          "Tinted_glazing_in_waiting_shelter_partition","Terminal_raised_BUS_STATION_route_identity",
          "Pitched_two-part_standing_seam_shelter_roof")
SOURCE=r'''
local root="mods/bayline/"
local M=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
local P=dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua"))
local fd=assert(io.open(OUTPUT_PATH, "w"))
local td={[0]=0,1,8,9}
for bay=0,3 do
  local bearing=(bay+2)%4
  for side=0,1 do
    for slot=0,1 do
      local state=32+td[bearing]+2*slot
      local stop=M.bay_stop_frame(state,side)
      local kind,x,z=M.sample(state,side,0)
      assert(kind=="position")
      local v={x=x,y=z,state=state,frame=0,direction=2*bearing+1}
      local a={x,z,v.direction,0,1-bearing%2}
      local recorded=false
      local function write(key,x,z,yaw)
        fd:write(string.format("%s %d %.8f %.8f %.8f\n",key,side,x-.5,z-.5,math.pi-yaw))
      end
      for i=1,200 do
        local r,x,z,d,f=M.step(v,side)
        if r~="move" and r~="rotate" then break end
        local b={x,z,d,0,a[5]}
        for j=0,8 do
          local x,z,yaw=P.pose(a,b,j/8)
          write("bay"..bay.."slot"..slot,x,z,yaw)
          if j==8 and f==stop and not recorded then
            write("park"..bay.."slot"..slot,x,z,yaw)
            recorded=true
          end
        end
        v.x,v.y,v.direction,v.frame=x,z,d,f
        a=b
      end
      assert(recorded)
    end
  end
end
fd:close()
'''

def source(p):
    s=p.read_text()
    a=s.index("static void RoadVehCheckOvertake")
    assert "/* Don't overtake in stations */" in s[a:a+1000]
    assert "IsTileType(v->tile, MP_STATION)" in s[a:a+1000]

def build_refs():
    models={}
    for k in range(4):
        paths=MODEL/f"bl_road_bus_bay_pair_{k}.obj"
        vs,layout=obj(paths,(0,0))
        clean=lambda p:(p[0]-.5,p[1],p[2]-.5)
        assert all(-1.000001<x<1.000001 and -.02<y<.73 and -1.000001<z<1.000001
                  for x,y,z in map(clean,vs))
        assert set(REQUIRED)<=layout.keys()
        assert len([l for l in paths.read_text().splitlines() if l.startswith("vt ")])==32
        g={n:[list(map(clean,f)) for f in fs] for n,fs in layout.items()}
        for slot,center in ((1,.3125),(2,-.1875)):
            n=f"Marked_stopping_bay_{slot}_at_exact_projected_parking_throat"
            extent=[rotate(x,z,k) for f in g[n] for x,_,z in f]
            assert min(x for x,_ in extent)<center<max(x for x,_ in extent)
            park_z=.155 if k<2 else .0775
            assert abs((min(y for _,y in extent)+max(y for _,y in extent))/2 - (park_z-.515))<.021
        deck=[[(x,z) for x,_,z in f] for f in g[RIM] if all(abs(y-.003)<1e-6 for _,y,_ in f)]
        obs=[]
        for n,polys in g.items():
            for f in polys:
                poly=cut(cut(f,1,.014,1),1,.33,-1)
                if not poly:continue
                contour=hull((x,z) for x,_,z in poly)
                u,w=zip(*contour)
                obs.append((n,min(u),max(u),min(w),max(w),contour))
        models[k]=(deck,obs)
    return models

def stock_poses():
    old=stock_trace.SAMPLE
    stock_trace.SAMPLE=SOURCE
    parking={};traverses=[];counts=Counter()
    try:
        for key,side,x,z,yaw in trace():
            parking_tag=key.startswith("park")
            k=int(key[4 if parking_tag else 3]);slot=int(key[-1])
            rec=(k,side,slot,x,z,yaw)
            if parking_tag:
                parking[k,side,slot]=(x,z,yaw)
                q,r=rotate(x,z,k)
                # The 16-pixel source tile is metrically identical under
                # rotation in X, but source lane compression can differ on
                # the other half-axis by a single stock subpixel.
                assert abs(q-(.3125 if slot==0 else -.1875))<1e-6
                assert abs(r-(.155 if k<2 else .0775))<1e-6
            else:traverses.append(rec);counts[k,side,slot]+=1
    finally:stock_trace.SAMPLE=old
    assert len(parking)==16 and all(n>=245 for n in counts.values())
    return parking,traverses

def transform(a,x,z,yaw):
    c,s=cos(yaw),sin(yaw)
    return [(x+u*c-w*s,z+u*s+w*c) for u,w in a]

def clearance(models,parking,poses):
    names=(("bl_town_flyer",.42),("bl_leopard_bus",.40),("bl_coach",.42))
    models_vehicle={}
    transient=Counter()
    for name,scale in names:
        v,_=obj(MODEL/(name+".obj"))
        env=hull((u*scale,w*scale) for u,_,w in v)
        contact=min(y for _,y,_ in v)
        tires={(u*scale,w*scale) for u,y,w in v if abs(y-contact)<.003}
        assert len(env)>8 and tires,(name,len(env),len(tires))
        assert .22<max(y*scale for _,y,_ in v)<.32
        models_vehicle[name]=(env,tires)
    for k,side,slot,x,z,angle in poses:
        deck,obs=models[k]
        for name,(env,tires) in models_vehicle.items():
            now=transform(env,x,z,angle)
            a,b=zip(*now)
            a0,a1,b0,b1=min(a),max(a),min(b),max(b)
            for n,x0,x1,z0,z1,p in obs:
                if a1<x0 or a0>x1 or b1<z0 or b0>z1:continue
                assert not intersects(now,p),(k,side,slot,name,n,x,z)
            for p in transform(tires,x,z,angle):
                px,pz=rotate(*p,k)
                # Normal outside connected stub approach remains asphalt.
                if px<=.005 and abs(pz)<=.317:continue
                if px<-.999:continue
                assert any(intersects([p],paved) for paved in deck),(k,side,slot,name,px,pz)
            # Overlap with a stationary sibling is separately observable
            # from fixed geometry/paving. Do not claim that art can change
            # stock entrance or passing logic.
            if intersects(now,transform(env,*parking[k,side,1-slot])):
                transient[name]+=1
    for k in range(4):
        for side in (0,1):
            for n,(a,_) in models_vehicle.items():
                for u,(b,_) in models_vehicle.items():
                    p=transform(a,*parking[k,side,0])
                    q=transform(b,*parking[k,side,1])
                    assert not intersects(p,q),(k,side,n,u,"the two parked bays must coexist")
    return len(poses)*len(names),transient

if __name__=="__main__":
    if len(sys.argv)>1:source(Path(sys.argv[1]))
    p,poses=stock_poses()
    n,observed=clearance(build_refs(),p,poses)
    tex=(ROOT/"mods/bayline/textures/bl_road_bus_bay_pair.png").read_bytes()
    assert tex[:8]==b"\x89PNG\r\n\x1a\n" and int.from_bytes(tex[16:20],"big")==256
    print(f"PASS: stock-only four entrance orientations; 16 exact parked positions and all full vehicle pairs clear; {n:,} swept bus poses paved and clear of fixed equipment.")
    print("Conservative moving-body intersections with stationary sibling when all stock poses are replayed unconditionally:",dict(observed))
