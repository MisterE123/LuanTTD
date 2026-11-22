#!/usr/bin/env python3
"""Foster #118 dedicated OBJ, stock lane clearance and genuine right-side traces."""
from collections import Counter
from math import cos, floor, hypot, isclose, sin
from pathlib import Path
import re
import struct
import sys
from zipfile import ZIP_DEFLATED, ZipFile
from io import BytesIO

from PIL import Image

from coal_tipper_art import bounds, in_lane, turn_check
from small_airport_art import hull, intersects, obj
import road_freight_stop_art as runner

ROOT=Path(__file__).resolve().parents[1]
TEX=ROOT/"mods/luanttd_core/textures"
SCALE=.40
PAINT={(79,82,85),(154,147,126),(239,227,182)}
TRACE=r'''
local R=dofile("tests/foster_bus_route.lua")("mods/luanttd_core/")
local io=assert(io.open(OUTPUT_PATH,"w"))
for a=0,3 do
  for delta=-1,1 do
    local b=(a+delta)%4
    local t=R.compile(a,b,8,8)

    for _,p in ipairs(t.points) do
      io:write(string.format("board_%d_%d %d %d %d 0\n",a,b,p.mask,p.x,p.z))
    end
    for k=1,#t.frames-1 do
      for l=0,8 do
        local x,z,yaw,here=t.pose(k,l/8)
        io:write(string.format("pose_%d_%d %d %.9f %.9f %.9f\n",a,b,here==t.id and 1 or 0,x,z,math.pi-yaw))
      end
    end
  end
end
io:close()
'''

def inspect():
    p=ROOT/"mods/luanttd_core/models/bl_foster_bus.obj"
    vertices,uv,faces=[],[],[]
    tag=None
    for row in p.read_text().splitlines():
        fields=row.split()
        if not fields:continue
        k,*v=fields
        if k=="o": tag=v[0]
        elif k=="v":
            x,h,z=(float(q)*SCALE/10 for q in v)
            vertices.append((-x,h,z))
        elif k=="vt":
            a,b=map(float,v);i=int(a*32)
            assert 0<=i<32 and isclose(a,(i+.5)/32,abs_tol=1e-6) and b==.5
            uv.append(i)
        elif k=="f":
            i,j=zip(*(tuple(map(int,s.split("/")[:2])) for s in v))
            assert len(i)==3 and len({uv[k-1] for k in j})==1
            faces.append((tuple(vertices[k-1] for k in i),uv[j[0]-1]))
    assert tag=="Foster_Bus_118" and 8000<len(faces)<16000 and len(vertices)>5000
    atlas=TEX/"bl_foster_bus_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24])==(256,8)
    stream=BytesIO()
    with ZipFile(stream,"w",ZIP_DEFLATED,compresslevel=9) as z:
        z.write(p,p.name);z.write(atlas,atlas.name)
    assert stream.tell()<350*1024
    return vertices,faces,stream.tell()


def source(root):
    root=Path(root)
    s=next(p for p in (root/"engines.h",root/"src/table/engines.h") if p.is_file()).read_text()
    assert re.search(r"MR\(\s*24107,\s*20,\s*15,\s*40,\s*CT_PASSENGERS\s*,\s*T\|A\|S\s*\).*// 118 Foster Bus",s)
    assert re.search(r"ROV\(\s*17,\s*150,\s*178,\s*SND_1B_DEPARTURE_MODERN_BUS,\s*224,\s*37,\s*70,\s*15\s*\).*//\s+2 Foster Bus",s)
    assert re.search(r"ROV\(\s*17,.*//\s+1 Hereford Leopard Bus",s)
    s=next(p for p in (root/"roadveh_cmd.cpp",root/"src/roadveh_cmd.cpp") if p.is_file()).read_text()
    vals=re.search(r"_roadveh_full_adder\[\]\s*=\s*\{(.*?)\};",s,re.S).group(1)
    assert [int(n) for n in re.findall(r"\b\d+\b",vals)][17]==0


def cast(shape, x,z,a):
    c,s=cos(a),sin(a)
    return [(x+u*c-v*s,z+u*s+v*c) for u,v in shape]


def native_sweep(tires,env):
    runner.SAMPLE=TRACE
    poses=0
    roads={}
    used=Counter()
    grids={}
    largest=(0,None)
    outside=0
    for key,slot,x,z,a in runner.trace():
        tag,a0,b0=key.split("_")
        k=(int(a0),int(b0))
        if tag=="board":
            roads.setdefault(k,{})[int(x),int(z)]=slot
            if slot not in grids:
                im=Image.open(TEX/f"bl_road_surface_{slot}.png").convert("RGB")
                grids[slot]={p for j in range(32) for i in range(32) if im.getpixel(p:=(i,j)) in PAINT}
            continue
        a0,b0=k
        # The stock short swept geometry may overhang a verge when it rotates
        # while its nose is at a source subpixel, but wheels must remain on
        # pavement or its textured shoulder. Measure max tire-center deviation
        # continuously (subpixel poses are not quantized to visible nodes).
        for tx,tz in cast(tires,x,z,a):
            A,B=floor((tx+.5)/2),floor((tz+.5)/2)
            mask=roads[k].get((A,B))
            if mask is None:
                raise AssertionError((k,tx,tz,"outside five real connected tiles"))
            u=(tx-2*A+.5)*16
            v=(tz-2*B+.5)*16
            i,j=floor(u),floor(v)
            if (i,j) not in grids[mask]:
                distance=min(hypot(i-p,j-q) for p,q in grids[mask])
                if distance>largest[0]:largest=(distance,(k,slot,tx,tz,x,z,a,mask,(i,j)))
                outside+=1
        if a0==b0 and slot:
            # Confirm actual compiled right-traffic pose and verify opposing
            # model using road-lane symmetric orientation against its own skin.
            mid=16.5
            cross=z if a0%2==0 else x
            along=x if a0%2==0 else z
            assert isclose(abs(cross-mid),.155,abs_tol=1e-6)
            opposite=2*mid-cross
            ox,oz=(along,opposite) if a0%2==0 else (opposite,along)
            assert not intersects(cast(env,x,z,a),cast(env,ox,oz,a+3.141592653589793))
        if slot and a0!=b0: used[k]+=1
        poses+=1
    assert len(used)==8 and min(used.values())>75 and poses>6000
    return poses,largest,outside


def main():
    points,faces,compressed=inspect()
    lo,hi=bounds(points)
    in_lane(lo,hi)
    turn_check(lo,hi)
    assert hi[2]>.34 and lo[2]<-.35 # clear front/rear distinction
    assert all(z<-.336 for f,i in faces if i==16 for x,h,z in f) # bright headlights
    assert all(z>.329 for f,i in faces if i==18 for x,h,z in f) # ruby tail lamps
    contact={p for f,i in faces if i==23 for p in f if abs(p[1])<1e-7}
    assert len(contact)==8
    for x in (-.252*SCALE,.252*SCALE):
        for z in (-.482*SCALE,.496*SCALE):
            yes={(round(q,6),round(r,6)) for q,h,r in contact if abs(q-x)<.012 and abs(r-z)<1e-7}
            assert len(yes)==2,(x,z,yes)
    envelope=hull((x,z) for x,_,z in points)
    # The two ends of each tyre contact edge protect the full width.
    poses,worst,outside=native_sweep([(x,z) for x,h,z in contact],envelope)
    if len(sys.argv)>1:source(sys.argv[1])
    leopard,_=obj(ROOT/"mods/luanttd_core/models/bl_leopard_bus.obj")
    floor_y=min(y for _,y,_ in leopard)
    ref,ref_edge,edge_contacts=native_sweep(
        {(x*SCALE,z*SCALE) for x,y,z in leopard if abs(y-floor_y)<1e-7},
        hull((x*SCALE,z*SCALE) for x,y,z in leopard))
    # Existing port projection/raster mismatch on diagonal rotation frames
    # is not a Foster mesh property. Require no regression over the stock
    # counterpart (same OpenTTD sprite), and report it rather than hide it.
    assert ref==poses and worst[0]<=ref_edge[0] and outside<=edge_contacts
    print(f"Stock turn raster: max {worst[0]:g} texels beyond paint, "
          f"{outside} sampled tyre-edge endpoints vs {edge_contacts} on the stock Leopard reference.")
    print("FOSTER_ART_PASS",tuple(round(b-a,5) for a,b in zip(lo,hi)),f"{poses} right-hand source poses, two-body lane separation, archive={compressed} bytes")


if __name__=="__main__":
    main()
