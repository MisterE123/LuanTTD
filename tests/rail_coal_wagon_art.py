#!/usr/bin/env python3
"""Verify stock coal appearance, complete native geometry and mount contact."""
import argparse
from math import atan, hypot, isclose, pi
from pathlib import Path
import re

from rail_span_art import along_ray,load
from rail_coal_stage_art import basis
from rail_wagon_art import mesh

ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/"mods/bayline/models"
NAME="rail_coal_wagon"
AXLES=(-.269,.269)
EPS=3.e-6

def near(a,b,eps=EPS):
    assert isclose(a,b,abs_tol=eps),(a,b)

def per_mesh(state):
    g=mesh(NAME+"_"+state)
    extents=[p for v in g.values() for p in v]
    assert max(abs(x) for x,z,h in extents)<.263
    assert max(abs(z) for n,v in g.items() if n!="Coupler_knuckles" for x,z,h in v)<.484
    assert max(h for x,z,h in extents)<=.542+EPS
    windows=[]
    for side,s in ((-1,"L"),(1,"R")):
        v=g["Rolling_tread_"+s]
        near(min(h for x,z,h in v),0)
        a,b=min(x for x,z,h in v),max(x for x,z,h in v)
        near((a+b)/2,side*.212)
        assert {round(z,6) for x,z,h in v if abs(h)<EPS}==set(AXLES)
        for z in AXLES:
            windows.append((side,z,a,b))
    v=g["Inner_wheel_flange"]
    near(min(h for x,z,h in v),-.010)
    assert .169<min(abs(x) for x,z,h in v)<max(abs(x) for x,z,h in v)<.182
    v=g["Coupler_knuckles"]
    near(max(z for x,z,h in v),.499);near(min(z for x,z,h in v),-.499)
    near((max(h for x,z,h in v)+min(h for x,z,h in v))/2,.157)
    assert "Visible_wagon_side_release_latch" in g and "Individual_laminated_suspension_leaves" in g
    return g,windows

def glyph_bounds(g):
    return [p for name,v in g.items() for p in v if name.startswith("Stencil_")]

def check(upstream):
    if upstream:
        text=Path(upstream).read_text()
        assert re.search(r'MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_COAL\s*,\s*T\|A\s*\),\s*//\s*29 Coal Truck',text)
        assert re.search(r'RVI\(\s*34,\s*W,\s*176,\s*0,\s*0,\s*18,\s*0,\s*RC_W,\s*30,\s*R,\s*A\),\s*//\s*29 Coal Truck',text)
    e,we=per_mesh("empty")
    f,wf=per_mesh("loaded")
    # Material/object/group order and every fixed model vertex coincide:
    # swapping mesh at the same entity placement cannot shift any contact.
    empty=(DIR/("bl_"+NAME+"_empty.obj")).read_bytes()
    loaded=(DIR/("bl_"+NAME+"_loaded.obj")).read_bytes()
    assert loaded.startswith(empty) and len(loaded)>len(empty)
    assert we==wf and len(glyph_bounds(e))>200
    assert all(not (abs(x)<.147 and abs(z)<.338 and h>.251)
               for name,v in e.items() for x,z,h in v),"cargo volume isn't open in the empty model"
    v=f["Coal_payload_irregular_ridged_base"]+f["Visible_angular_lumps_of_coal_in_the_wagon"]
    assert all(abs(x)<=.192+EPS and abs(z)<=.377+EPS and h>.376 for x,z,h in v)
    assert max(h for x,z,h in v)>.496 and len(v)>1100
    assert all(not any(k.startswith(t) for k in e) for t in ("Coal_payload_", "Visible_angular_lumps_"))
    kirby=mesh("rail_kirby_paul_tank")
    k=max(z for x,z,h in kirby["Coupler_knuckles"])
    near(1-k-.499,.002)
    near((max(h for x,z,h in kirby["Coupler_knuckles"])+min(h for x,z,h in kirby["Coupler_knuckles"]))/2,.157)
    curved=0
    for bend in (-1,1):
        for n in range(1,20):
            for side,z,a,b in wf:
                r=1+bend*side*.212
                if min(n,20-n)*pi/40<atan(abs(z)/(r-.025)): continue
                ra,rb=sorted(hypot(1+bend*x,z) for x in (a,b))
                assert min(r+.030,rb)-max(r-.030,ra)>.006,(n,bend,side,z)
                curved+=1
    rays=0
    for stage in ("load","unload"):
        for axis in (0,1):
            for mirror in (False,True):
                suffix=f"{stage}_{axis}"+("_mirror" if mirror else "")
                rows=[(g,tuple(basis(axis,mirror,p) for p in vs)) for g,vs in
                               load("bl_rail_coal_stage_"+suffix)]
                crown=[ps for g,ps in rows if g=="Polished_railhead"]
                obstacles=[ps for g,ps in rows if any(y>.126 for x,z,y in ps)]
                # Whole wagon lies inside this conservative swept rectangle.
                # Probe the actual stage down the full length including apron.
                for n in range(13):
                    x=-.265+.53*n/12
                    for m in range(12):
                        h=.132+(.660-.132)*m/11
                        assert not list(along_ray(obstacles,1,x,h)),(suffix,x,h)
                        rays+=1
                for side,z,a,b in wf:
                    points=list(along_ray(crown,2,side*.212,z))
                    assert points, (suffix,side,z)
                    near(max(points),.114)
    print(f"STOCK_COAL_WAGON_ART_PASS two identical shells, 4 gauge contacts each, {curved} curved overlaps, {rays} actual stage clearance rays, .002 stock drawgear clearance")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-engines")
    check(p.parse_args().upstream_engines)
