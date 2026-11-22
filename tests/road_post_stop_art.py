"""Validate the six runtime OBJ variants, elevations, and lane envelopes."""
from collections import defaultdict
from pathlib import Path
from math import sqrt
import struct

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"mods/luanttd_core/models"
TEX=ROOT/"mods/luanttd_core/textures/bl_road_post_stop.png"
KEYS=("straight_0","straight_1","bay_0","bay_1","bay_2","bay_3")
PARTS={"Paved_loading_platform","Raised_porcelain_POST_lettering",
       "Tied_canvas_mail_sacks","Parcels_awaiting_collection",
       "Slate_pitched_loading_canopy","Brick_loading-bay_piers",
       "Porcelain_post-office_fascia","Enamel_post_box_housing"}

def close(a,b):
    return abs(a-b)<1e-5

def read(key):
    model=MODEL/f"bl_road_post_stop_{key}.obj"
    vertices,uv,normals=[],[],[]
    parts=defaultdict(list)
    part=""
    for row in model.read_text().splitlines():
        if row.startswith("#"): continue
        typ,*args=row.split()
        if typ=="o":
            part=args[0]
        elif typ=="v":
            # Luanti X-reversal then undo half-node offset and reorder axes.
            x,h,z=map(float,args);vertices.append((-x-.5,z-.5,h))
        elif typ=="vt":
            uv.append(tuple(map(float,args)))
        elif typ=="vn":
            normals.append(tuple(map(float,args)))
        elif typ=="f":
            ids=[tuple(int(v)-1 for v in item.split("/")) for item in args]
            assert len(ids)==3 and all(0<=v<len(vertices) and 0<=t<len(uv)
                and 0<=n<len(normals) for v,t,n in ids)
            assert len({t for _,t,_ in ids})==1 and len({n for _,_,n in ids})==1
            a,b,c=[vertices[v] for v,_,_ in ids]
            ab=[q-p for p,q in zip(a,b)];ac=[q-p for p,q in zip(a,c)]
            cross=[ab[(i+1)%3]*ac[(i+2)%3]-ab[(i+2)%3]*ac[(i+1)%3] for i in range(3)]
            length=sqrt(sum(k*k for k in cross))
            assert length>1e-7,(key,part,ids)
            nx,ny,nz=normals[ids[0][2]]
            assert all(close(k/length,n) for k,n in zip(cross,(-nx,nz,ny)))
            parts[part].append(tuple(vertices[v] for v,_,_ in ids))
    assert PARTS<=parts.keys(),(key,PARTS-parts.keys())
    assert len(uv)==32 and all(close(u,(i+.5)/32) and v==.5 for i,(u,v) in enumerate(uv))
    assert len(vertices)>800 and len(parts)>25
    return parts,vertices

def rotate(v, turns):
    x,z,h=v
    return ((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[turns%4]

assert TEX.read_bytes()[:8]==b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II",TEX.read_bytes()[16:24])==(256,8)
blender=(ROOT/"art/road_post_stop.blend").read_bytes()
assert b"BLENDER" in blender[:32] or blender[:4]==b"\x28\xb5\x2f\xfd" # uncompressed or Blender's zstd
models={key:read(key) for key in KEYS}
for key,turn in zip(KEYS,(0,1,0,-1,-2,-3)):
    parts,vs=models[key]
    canonical=[rotate(v,-turn) for v in vs]
    assert min(z for _,z,_ in canonical)>=.43
    assert max(z for _,z,_ in canonical)<1
    assert min(x for x,_,_ in canonical)>-1 and max(x for x,_,_ in canonical)<1
    assert -.510<min(h for _,_,h in canonical)<-.500 # footing sunk slightly into the ground
    assert .22<max(h for _,_,h in canonical)<.25
    base=models["bay_0" if key.startswith("bay") else "straight_0"][0]
    for name,polys in parts.items():
        assert len(polys)==len(base[name])
        assert all(all(close(c,d) for c,d in zip(rotate(p,-turn),q))
                       for poly,ref in zip(polys,base[name]) for p,q in zip(poly,ref)),(key,name)
a=models["straight_0"][1];b=models["bay_0"][1]
assert max(x for x,_,_ in b)-min(x for x,_,_ in b)<.75*(max(x for x,_,_ in a)-min(x for x,_,_ in a))
print("PASS: all six post stop meshes have real architecture, oriented road clearance, outward normals, valid palette and editable Blender source")
