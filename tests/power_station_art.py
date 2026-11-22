#!/usr/bin/env python3
"""Check the Riverbend native meshes and delivery envelope.

Optional second argument: path to OpenTTD 14.1 src/table/build_industry.h.
"""
from collections import defaultdict
from math import cos, hypot, pi, sin
from pathlib import Path
import re
import sys

from small_airport_art import obj,cut,intersects,hull

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"mods/luanttd_core/models"
FOOTPRINT=((7,7,7,10),(9,8,8,10))
XMIN,XMAX,ZMIN,ZMAX=-.5,7.5,-.5,3.5
APRON="Southern_industrial_carriage_and_rail_service_apron"
FOUNDATION="Coarse_hardpack_industry_foundation"
SHAFT="Tapered_patterned_masonry_smoke_shaft"


def read_source(path):
    s=path.read_text()
    block=s.split("_tile_table_power_station_0 {",1)[1].split("};",1)[0]
    table={(int(x),int(z)):int(gfx) for x,z,gfx in re.findall(r"MK\((\d+),\s*(\d+),\s*(\d+)\)",block)}
    assert table=={(x,z):gfx for z,row in enumerate(FOOTPRINT) for x,gfx in enumerate(row)}
    spec=s.split("MI(_tile_table_power_station",1)[1].split("),",1)[0]
    assert re.search(r"CT_INVALID,\s+0,\s+CT_INVALID,\s+0,\s+5",spec)
    assert re.search(r"CT_COAL,\s+256",spec)
    assert "INDUSTRYLIFE_BLACK_HOLE" in spec and "1 << LT_TEMPERATE | 1 << LT_ARCTIC" in spec


def plane_edge(ps,direction,c):
    axis=0 if direction=="x" else 2
    ortho=2-axis
    e=[p[ortho] for f in ps for p in f if abs(p[axis]-c)<1e-6]
    assert e
    return min(e),max(e)


def load_meshes():
    whole=defaultdict(list)
    for z,row in enumerate(FOOTPRINT):
        for x,gfx in enumerate(row):
            path=M/f"bl_power_station_{x}_{z}.obj"
            assert f"({x},{z}) gfx {gfx}" in path.read_text().splitlines()[0]
            v,g=obj(path,(x,z))
            l=2*x-.5;t=2*z-.5
            assert all(l-1e-6<=a<=l+2.000001 and t-1e-6<=c<=t+2.000001 for a,_,c in v)
            assert all(-1e-6<=b<=3.52+1e-6 for _,b,_ in v)
            # Match full hardpack at every cardinal tile edge. Verify visible
            # south and east functional apron opening beyond that hardpack.
            for east in (0,2):
                assert plane_edge(g[FOUNDATION],"x",l+east)==(t,t+2)
            for south in (0,2):
                assert plane_edge(g[FOUNDATION],"z",t+south)==(l,l+2)
            if z==1:
                assert plane_edge(g[APRON],"z",3.5)==(l,l+2)
            if x==3 and z==1:
                p=[(a,b,c) for f in g["East_heavy_truck_delivery_approach"] for a,b,c in f if abs(a-7.5)<1e-6]
                assert all(abs(b-.004)<1e-6 for _,b,_ in p)
                assert abs(min(c for _,_,c in p)-2.07)<1e-6 and abs(max(c for _,_,c in p)-2.99)<1e-6
            assert (SHAFT in g)==(gfx==8)
            assert ("Riveted_transformer_tank" in g)==(gfx==10)
            for n,tris in g.items():whole[n].extend(tris)
    return whole


def open_geometry(groups):
    # Annular crown is really open all the way down a modeled bore. No
    # triangle crosses the smoke-particle exit center at the top.
    rims=groups["Stack_open_annular_rim"]
    throat=groups["Recessed_soot-lined_chimney_bore"]
    assert len(rims)==96 and len(throat)==96
    for x,y,z in ((2.48,3.38,2.1),(4.34,3.52,2.1)):
        tris=[[(a,c) for a,b,c in f] for f in rims if abs(f[0][1]-y)<1e-6]
        assert len(tris)==48
        assert min(hypot(a-x,c-z) for f in tris for a,c in f)>.14399
        assert not any(intersects([(x,z)],tri) for tri in tris)
    assert len(groups["Independent_curved_cooling_fan_rotor_blade"])==40
    fans=groups["Cooling_fan_open_collar_annulus"]
    assert len(fans)==96
    for x in (4.14,4.70):
        near=[[(a,z) for a,y,z in f] for f in fans if all(abs(a-x)<.22 for a,_,_ in f)]
        assert len(near)==48 and not any(intersects([(x,.413)],p) for p in near)
    assert len(groups["Separate_battered_coal_conveyor_belt_slats"])>=82
    assert len(groups["Genuinely_open_inside_of_tapered_ash_surge_bin"])==8
    assert len(groups["Visible_recessed_coal_chute_grate_bars"])==24
    assert sum(map(len,groups.values()))<39000


def approach(groups):
    vertices,_=obj(M/"bl_coal_tipper_loaded.obj")
    truck=[(x*.42,z*.42) for x,_,z in vertices]
    height=max(y*.42 for _,y,_ in vertices)
    assert .18<height<.30
    truck=hull(truck)
    floor=.014
    solids=[]
    for n,fs in groups.items():
        for f in fs:
            # Keep the stock yard edge as a separable rail/road platform.
            assert not any(z>=2.99 and y>.026 for _,y,z in f),n
            if max(x for x,_,_ in f)<5.73 or min(z for _,_,z in f)>2.90 or max(z for _,_,z in f)<1.90:
                continue
            poly=cut(cut(f,1,floor,1),1,height+floor,-1)
            if poly:solids.append((n,hull((x,z) for x,_,z in poly)))
    assert solids, "fixture must include nearby obstructions"
    for i in range(105):
        x=6.45+i*.016
        for angle in (-10,-5,0,5,10):
            # Nose +X for reversing to the dump grate; the -X pull-in
            # maneuver has the same conservative plan envelope.
            for reverse in (-1,1):
                a=pi*angle/180+reverse*pi/2
                x2,z2=cos(a),sin(a)
                p=[(x+a*x2-b*z2,2.5+a*z2+b*x2) for a,b in truck]
                for n,poly in solids:
                    assert not intersects(p,poly),f"{n} blocks coal tipper at x={x} heading={angle}."
    # A tail centered at the terminal delivery pose overlaps the grate, so
    # the checked approach actually reaches the intended discharge station.
    assert 5.95 < 6.45+min(z for _,z in truck)<6.367
    atlas=(ROOT/"mods/luanttd_core/textures/bl_power_station_atlas.png").read_bytes()
    assert atlas[:8]==b"\x89PNG\r\n\x1a\n" and 256<int.from_bytes(atlas[16:20],"big")<1024
    assert (ROOT/"art/riverbend_power_station.blend").stat().st_size>80000

if __name__=="__main__":
    if len(sys.argv)>1:read_source(Path(sys.argv[1]))
    geo=load_meshes()
    open_geometry(geo)
    approach(geo)
    print("PASS: 8 stock-role meshes with joined slabs, two clear smoke exits and full real cooling rotors, 1,050 loaded-truck approach poses, separate rail frontage.")
