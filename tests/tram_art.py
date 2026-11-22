"""Validate LuanTTD's tram drawings against native runtime dimensions."""
from pathlib import Path
from math import isclose
import struct

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"mods/bayline/models"
EDGES=((1,-.5,0),(0,1.5,1),(1,1.5,2),(0,-.5,3)) # x/z plane, boundary, bit
LANE=.155
GAUGE=.106
HEAD=.012
CONTACT=.50
SCALE=.40


def read(stem):
    model={"v":[],"vt":[],"vn":[],"f":[]}
    for line in (MODEL/f"bl_{stem}.obj").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        key,*w=line.split()
        if key=="v":
            x,y,z=map(float,w)
            model["v"].append((-x,y,z))
        elif key=="vt":
            u,v=map(float,w)
            assert 0<u<1 and v==.5 and isclose(u*32-.5,round(u*32-.5),abs_tol=.0001)
            model[key].append((u,v))
        elif key=="vn":
            model[key].append(tuple(map(float,w)))
        elif key=="f":
            assert len(w)==3
            model[key].append([tuple(map(int,t.split("/"))) for t in w])
        else:
            assert key not in ("usemtl","mtllib"), "only the published palette should load"
    assert model["v"] and model["f"]
    for face in model["f"]:
        for v,vt,vn in face:
            assert 0<v<=len(model["v"]) and 0<vt<=len(model["vt"]) and 0<vn<=len(model["vn"])
    return model


def footprint():
    car=read("streetcar")
    units=SCALE/10
    xyz=[tuple(c*units for c in vertex) for vertex in car["v"]]
    lo,hi=[tuple(fn(v) for v in zip(*xyz)) for fn in (min,max)]
    assert len(xyz)>3000 and len(car["f"])<11_000
    assert isclose(lo[1],0,abs_tol=.000002)
    assert isclose(hi[1]+HEAD,CONTACT,abs_tol=.000002)
    # Center of each track coincides with the marked traffic lane.
    for delta in (-LANE,LANE):
        assert delta+lo[0]>-.3125 and delta+hi[0]<.3125
        assert abs(delta)>max(abs(hi[0]),abs(lo[0]))
    assert .75<hi[2]-lo[2]<.79
    assert all(-1<=p<=1 for v in car["vn"] for p in v)
    print("Streetcar native width, height and length:",*[round(b-a,4) for a,b in zip(lo,hi)])


def exact_edge(mesh,direction,deviation):
    axis,edge,_=direction
    select=[v for v in mesh if isclose(v[axis*2],edge,abs_tol=.000001)]
    return sorted(set(round(v[2-axis*2]-.5,6) for v in select
                      if isclose(v[1],deviation,abs_tol=.000001)))


def check_overlay():
    # Top-height edge points are exactly symmetric around the lane and track
    # centers. Thus a tile with return exit always matches its neighbour.
    want_rails=sorted(round(s*LANE+i*GAUGE/2+j*.0065,6)
                      for s in (-1,1) for i in (-1,1) for j in (-1,1))
    want_wires=sorted(round(s*LANE+j*.006,6) for s in (-1,1) for j in (-1,1))
    edges=0
    for mask in range(1,16):
        rails=read(f"tram_rails_{mask}")
        wire=read(f"tram_wire_{mask}")
        for mesh in (rails["v"],wire["v"]):
            assert all(-.500001<=x<=1.500001 and -.500001<=z<=1.500001 for x,_,z in mesh)
        assert max(v[1] for v in rails["v"])<=-.473+1e-8 # turnout box is above the rails
        assert min(v[1] for v in wire["v"])==CONTACT-.5
        for d in EDGES:
            present=bool(mask&(1<<d[2]))
            r=exact_edge(rails["v"],d,HEAD-.5)
            w=exact_edge(wire["v"],d,CONTACT-.5)
            assert r==(want_rails if present else []), (mask,d,r)
            assert w==(want_wires if present else []), (mask,d,w)
            edges+=present
        for face in rails["f"]:
            if all(isclose(rails["v"][v-1][1],HEAD-.5,abs_tol=1e-8) for v,_,_ in face):
                assert all(rails["vn"][n-1][1]>.99 for _,_,n in face), "outward rail-head normals"
    for direction in ("ns","ew"):
        pole=read("tram_mast_"+direction)["v"]
        assert max(y for _,y,_ in pole)>.15
        horizontal=0 if direction=="ns" else 2
        assert any(p[horizontal]-.50>.49 and p[1]<-.45 for p in pole)
        assert all(-.5<=x<=1.5 and -.5<=z<=1.5 for x,_,z in pole)
    print("PASS: track and wire seams coincide on",edges,"mask/edge pairs; both mast axes sit clear of asphalt")


if __name__=="__main__":
    palette=(ROOT/"mods/bayline/textures/bl_tram_palette.png").read_bytes()
    assert palette.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack(">II",palette[16:24])==(256,8)
    assert (ROOT/"art/streetcar.blend").is_file()
    assert (ROOT/"art/tramway_kit.blend").is_file()
    footprint()
    check_overlay()
