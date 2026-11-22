#!/usr/bin/env python3
"""Check Cedar Coal poses and joints against the pinned OpenTTD tile layout."""
import argparse
import re
import struct
import subprocess
from math import isclose
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/bayline/models"
REQ={(1,1,0),(1,2,2),(0,0,5),(1,0,6),(2,0,3),(2,2,3)}
AXLE=(2.5,2.42,2.395)
EPS=2e-6


def grouped(path,tx=None,tz=None):
    groups={}
    for row in path.read_text().splitlines():
        if row.startswith("o "):
            name=row[2:]
            allv=groups.setdefault(name,[])
        if row.startswith("v "):
            x,y,z=map(float,row[2:].split())
            allv.append((-x/10,z/10,y/10) if tx is None else (-x+2*tx,z+2*tz,y+.5))
    assert len(groups)>0
    return groups


def all_points(g,tag=None):
    return [v for name,pts in g.items() if tag is None or name.startswith(tag) for v in pts]


def seam(a,b,tag,dim,x):
    def points(g):
        return {tuple(round(v,6) for v in p) for p in all_points(g,tag) if abs(p[dim]-x)<EPS}
    u,v=points(a),points(b)
    assert u and u==v,tag


def check(lua,header):
    data=subprocess.check_output([lua,"-"],cwd=ROOT,input='''
local t=dofile("mods/bayline/openttd/coal_industry.lua")().mine_layouts[0]
for _,r in ipairs(t) do print(r[1],r[2],r[3]) end
''',text=True)
    assert {tuple(map(int,line.split())) for line in data.splitlines()}==REQ
    if header:
        block=header.read_text().split("static const IndustryTileLayout _tile_table_coal_mine_0")[1].split("};")[0]
        upstream={tuple(map(int,t)) for t in re.findall(r"MK\((\d+),\s*(\d+),\s*(\d+)\)",block)}
        assert upstream==REQ
    paths={tuple(map(int,m.groups())):p for p in MODELS.glob("bl_coal_mine_0_*.obj")
           if (m:=re.fullmatch(r"bl_coal_mine_0_(\d+)_(\d+)\.obj",p.name))}
    assert set(paths)=={(x,z) for x,z,gfx in REQ}
    parts={k:grouped(path,*k) for k,path in paths.items()}
    for (tx,tz),g in parts.items():
        assert all(abs(x-(2*tx+.5))<=1+EPS and abs(z-(2*tz+.5))<=1+EPS for x,z,h in all_points(g))
        assert "Individual_stock_coal_mine_yard_ground" in g
        assert len(all_points(g))>800
    seam(parts[(1,0)],parts[(1,1)],"Shaft_to_screen",1,1.5)
    seam(parts[(1,0)],parts[(2,0)],"Screen_to_spoil_yard",0,3.5)
    seam(parts[(1,0)],parts[(0,0)],"Truck_charging_chute",0,1.5)
    seam(parts[(1,1)],parts[(1,2)],"Taut_diagonal_winding_cable",1,3.5)
    head=parts[(1,1)]
    base=grouped(MODELS/"bl_coal_mine_0_1_1_nosheaves.obj",1,1)
    sheaves=grouped(MODELS/"bl_coal_mine_0_sheaves.obj")
    assert set(head)==set(base)|set(sheaves) and not (set(base)&set(sheaves))
    for name in sheaves:
        expected={tuple(v+a for v,a in zip(p,AXLE)) for p in sheaves[name]}
        actual=set(head[name])
        # Blender uses single-precision Vector coordinates. Re-centering
        # a wheel at its axle and applying the world model transform can
        # vary in the final exported decimal without changing the pose.
        assert len(expected)==len(actual) and all(
            any(max(abs(x-y) for x,y in zip(a,b))<3e-6 for b in actual)
            for a in expected),(name,len(expected),len(actual))
    assert isclose(max(h for x,z,h in all_points(sheaves)),.282,abs_tol=.001)
    # Existing 3D vehicle scale does not run into office or loader front.
    assert not any(x<.86 and .401<z<.892 and .025<h<.338 for x,z,h in all_points(parts[(0,0)]))
    assert not any(x>5.08 and 3.733<z<5.2 and .025<h<.52 for x,z,h in all_points(parts[(2,2)]))
    assert "Actual_tapered_coal_bunker_internal_sides" in parts[(1,0)]
    assert "Actual_open_bunker_rim_thickness" in parts[(1,0)]
    assert "Coal_stockpile_main_tapered_body_broken_coal_lumps" in parts[(2,0)]
    assert "Rope_winch_steel_cable_drum" in parts[(1,2)]
    w,h=struct.unpack(">II",(ROOT/"mods/bayline/textures/bl_coal_mine_atlas.png").read_bytes()[16:24])
    assert h==8 and w%8==0
    print("PASS: exact six stock occupied tile meshes; four continuous stock-layout belt or cable seams; original hollow bins, winding gear and open road/rail loading frontages")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua",default="lua5.1")
    parser.add_argument("--upstream-layout",type=Path)
    a=parser.parse_args()
    check(a.lua,a.upstream_layout)
