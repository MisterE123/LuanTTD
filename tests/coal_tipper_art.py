"""Check open and full coal-tipper exports against native road conventions."""
from collections import Counter
from pathlib import Path
from math import hypot, isclose, pi, sin
import struct

ROOT = Path(__file__).resolve().parents[1]
SCALE = .42
LANE = .155
EDGE = .3125
COAL = set(range(26,30))


def parse(stem):
    vertices, uv, normals = [], [], []
    grouped = Counter()
    source = ROOT/"mods/bayline/models"/f"bl_{stem}.obj"
    for line in source.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        prefix, *args = line.split()
        if prefix == "v":
            x,y,z=map(float,args)
            # Runtime size uses ten OBJ units per native node, with reflected X.
            vertices.append(tuple(round(p*SCALE/10,7) for p in (-x,y,z)))
        elif prefix == "vt":
            u,v=map(float,args)
            sample=32*u-.5
            slot=round(sample)
            assert 0<=slot<31 and isclose(slot,sample,abs_tol=.0001) and v==.5
            uv.append(slot)
        elif prefix == "vn":
            normals.append(tuple(map(float,args)))
        elif prefix == "f":
            assert len(args)==3
            indexes=[tuple(map(int,k.split("/"))) for k in args]
            assert all(0<i<=len(vertices) and 0<j<=len(uv) and 0<k<=len(normals) for i,j,k in indexes)
            points=tuple(sorted((vertices[i-1],uv[j-1]) for i,j,_ in indexes))
            assert len({slot for p,slot in points})==1
            grouped[points]+=1
        else:
            assert prefix not in ("usemtl","mtllib"), "palette is the only material"
    assert 7_000<sum(grouped.values())<10_000 and len(vertices)>3500
    return vertices,grouped


def bounds(verts):
    return tuple(map(min,zip(*verts))),tuple(map(max,zip(*verts)))


def in_lane(lo,hi):
    assert isclose(lo[1],0) and .24<hi[1]<.29
    assert .63<hi[2]-lo[2]<.71
    for side in (-1,1):
        a,b=lo[0]+side*LANE,hi[0]+side*LANE
        assert max(abs(a),abs(b))<EDGE-.025
        assert min(abs(a),abs(b))>.025


def turn_check(lo,hi):
    # Same .36-node quadratic and outer-lane corner easing as road_lanes.lua.
    # Test a bounding rectangle, conservative for the actual curved fenders.
    half_w=max(-lo[0],hi[0])
    half_l=max(-lo[2],hi[2])
    for direction in (-1,1):
        for j in range(201):
            t=j/200
            x,z=direction*.36*t*t,-.36*(1-t)**2
            dx,dz=direction*t,1-t
            l=hypot(dx,dz)
            dx,dz=dx/l,dz/l
            offset=LANE-(.10*sin(pi*t)**1.4 if direction<0 else 0)
            x+=offset*dz
            z-=offset*dx
            for p in range(17):
                for q in range(9):
                    length=(p/8-1)*half_l
                    width=(q/4-1)*half_w
                    a=x+length*dx+width*dz
                    b=z+length*dz-width*dx
                    assert (abs(a)<=EDGE and b<=EDGE) or (abs(b)<=EDGE and direction*a>=-EDGE)


def main():
    assert (ROOT/"art/coal_tipper.blend").stat().st_size>100_000
    palette=(ROOT/"mods/bayline/textures/bl_coal_tipper_palette.png").read_bytes()
    assert palette.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack(">II",palette[16:24])==(256,8)
    empty,empty_faces=parse("coal_tipper")
    full,full_faces=parse("coal_tipper_loaded")
    assert bounds(empty)==bounds(full)
    without_coal=Counter({p:n for p,n in full_faces.items() if p[0][1] not in COAL})
    assert empty_faces==without_coal, "loaded variant must keep coachwork unchanged"
    coal_faces=full_faces-without_coal
    assert sum(coal_faces.values())>600
    assert all(abs(v[0])<.10 and -.05<v[2]<.30 and .11<v[1]<.24
               for points in coal_faces for v,_ in points), "coal leaves open bed bounds"
    for swatch,side in ((6,-1),(7,1)):
        assert all(side*v[2]>.27 for points in empty_faces for v,k in points if k==swatch)
        assert any(k==swatch for points in empty_faces for _,k in points)
    lo,hi=bounds(full)
    in_lane(lo,hi)
    turn_check(lo,hi)
    print("Coal tipper x/y/z native dimensions:",tuple(round(b-a,4) for a,b in zip(lo,hi)))
    print("PASS identical empty/full coachwork origin and bounds; cargo geometry; -Z nose; lane and turn fit")


if __name__=="__main__":
    main()
