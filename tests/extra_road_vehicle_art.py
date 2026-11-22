"""Verify native mesh axes, lane/depot clearances and one stock road bend.

Uses only exports, not .blend script dimensions. Run with standard Python.
"""
from pathlib import Path
from math import hypot, isclose, pi, sin
import struct

ROOT=Path(__file__).resolve().parents[1]
SPEC={"mail_van":.43,"leopard_bus":.40}
ASPHALT=.625
LANE_OFFSET=.155


def load(stem):
    out = {"vertices":[], "uv":[], "faces":[]}
    for line in (ROOT/f"mods/luanttd_core/models/bl_{stem}.obj").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        k,*words=line.split()
        if k=="v":
            x,y,z=map(lambda w:float(w)/10,words)
            # Server uses 10 OBJ units per node, Luanti OBJ reverses X.
            out["vertices"].append((-x,y,z))
        elif k=="vt":
            u,v=map(float,words)
            assert v==.5 and 0<=round(32*u-.5)<24
            assert isclose(32*u-.5,round(32*u-.5),abs_tol=.0001)
            out["uv"].append(round(32*u-.5))
        elif k=="f":
            assert len(words)==3, "native triangulation"
            out["faces"].append([list(map(int,w.split("/"))) for w in words])
        else:
            assert k not in ("usemtl","mtllib"), "single published palette only"
    return out


def check():
    palette = (ROOT/"mods/luanttd_core/textures/bl_road_fleet_palette.png").read_bytes()
    assert palette.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack(">II",palette[16:24])==(256,8)
    for stem,scale in SPEC.items():
        assert (ROOT/f"art/{stem}.blend").stat().st_size>100_000
        obj=load(stem)
        verts=[tuple(c*scale for c in v) for v in obj["vertices"]]
        uv=obj["uv"]
        assert len(verts)>2_000 and 3_500<len(obj["faces"])<13_000
        lo,hi=[tuple(fn(v) for v in zip(*verts)) for fn in (min,max)]
        assert isclose(lo[1],0,abs_tol=.00001) and .24<hi[1]<.30, (stem,lo,hi)
        assert LANE_OFFSET+lo[0]>.020 and ASPHALT/2-LANE_OFFSET-hi[0]>.020, (stem,lo,hi)
        assert ASPHALT/2-LANE_OFFSET+lo[0]>.020 and LANE_OFFSET-hi[0]>.020, (stem,lo,hi)
        assert hi[2]-lo[2]<.72
        light_faces={6:[],7:[]}
        for f in obj["faces"]:
            for v,t,n in f:
                assert 1<=v<=len(verts) and 1<=t<=len(uv) and n>0
                if uv[t-1] in light_faces:
                    light_faces[uv[t-1]].append(verts[v-1][2])
        assert max(light_faces[6])<-.28 and min(light_faces[7])>.28, "headlights must be world model -Z"
        # Compare with a symmetric first-order native swept bounding box,
        # using the same compact .36-node centerline and left taper.
        width=max(abs(lo[0]),abs(hi[0]))
        length=max(abs(lo[2]),abs(hi[2]))
        edge=ASPHALT*.5
        for side in (-1,1):
            for frame in range(201):
                t=frame/200
                x,z=side*.36*t**2,-.36*(1-t)**2
                ox,oz=side*t,1-t
                mag=hypot(ox,oz)
                dx,dz=ox/mag,oz/mag
                offset=LANE_OFFSET-(.1*sin(pi*t)**1.4 if side==-1 else 0)
                x,z=x+dz*offset,z-dx*offset
                for a in range(21):
                    for b in range(7):
                        u=length*(2*a/20-1)
                        v=width*(2*b/6-1)
                        xx=x+dx*u+dz*v
                        zz=z+dz*u-dx*v
                        assert (abs(xx)<=edge and zz<=edge) or (abs(zz)<=edge and side*xx>=-edge), (stem,side,t)
        print(stem, "lane footprint", str(tuple(round(b-a,4) for a,b in zip(lo,hi))), "triangles", len(obj["faces"]))
    print("PASS: two grounded -Z nose vehicles fit one lane and both compact native bends")


if __name__=="__main__":
    check()
