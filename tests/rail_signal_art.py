#!/usr/bin/env python3
"""Check original signal models and exact OpenTTD 14.1 placement coordinates."""
import argparse
from math import cos, isclose, sin
from pathlib import Path
import re
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/bayline/models"
COLORS=22
TD=(0,1,2,3,4,5,8,9,10,11,12,13)
SLOT={0:8,1:10,2:4,3:6,4:0,5:2,8:9,9:11,10:5,11:7,12:1,13:3}
STRAIGHT={0:(-1,0),1:(0,1),8:(1,0),9:(0,-1)}


def read(variant,aspect):
    model=MODELS/f"bl_rail_signal_{variant}_{aspect}.obj"
    points=[]
    groups={}
    uv=[]
    group=None
    for line in model.read_text().splitlines():
        mode,_,rest=line.partition(" ")
        if mode=="vt":
            u,v=map(float,rest.split())
            uv.append(round(COLORS*u-.5))
            assert v==.5
        if mode=="v":
            ox,h,z=(float(value)/10 for value in rest.split())
            x=-ox
            assert -.5<x<.20 and h>=0 and -.16<z<.15
            points.append((x,z,h))
        if mode=="o":
            group=groups.setdefault(rest,[])
        if mode=="f":
            refs=[tuple(int(s)-1 for s in item.split("/")) for item in rest.split()]
            assert len(refs)==3 and len({r[1] for r in refs})==1
            group.append((tuple(points[p] for p,_,_ in refs),uv[refs[0][1]]))
    assert min(p[2] for p in points)==0 and min(p[1] for p in points)<-.09
    low=[p for p in points if p[2]<.98]
    # Tightest stock straight anchor is the left-side NW signal. At .375
    # from center, all low mast equipment clears the .2675 train half body.
    assert max(max(abs(p[0]),abs(p[1])) for p in low)<.102
    assert len(uv)==COLORS and sum(map(len,groups.values()))>350
    return groups


def caps(group,area):
    return {c for f,c in group[area] if max(p[1] for p in f)<-.071}


def check_assets():
    path=ROOT/"mods/bayline/textures/bl_rail_signal_atlas.png"
    assert struct.unpack(">II",path.read_bytes()[16:24])==(COLORS*8,8)
    red,green=read("light","red"),read("light","green")
    assert {13,15}<=caps(red,"Red_aperture") and not ({14,16}&caps(red,"Green_aperture"))
    assert {14,16}<=caps(green,"Green_aperture") and not ({13,15}&caps(green,"Red_aperture"))
    stop,clear=read("semaphore","red"),read("semaphore","green")
    def tip(group):
        p=[p for f,_ in group["Moving_upper-quadrant_blade"] for p in f]
        return max(y for x,z,y in p)
    assert tip(stop)<1.48 and tip(clear)>1.72
    assert 15 in caps(stop,"Active_spectacle_lens_inner_ring")
    assert 16 in caps(clear,"Active_spectacle_lens_inner_ring")


def check_positions(lua,source):
    probe='''
local A=dofile("mods/bayline/rail_signal_art.lua")
assert(A.pose(9,11,6.5,4,true)==nil)
assert(A.mesh("light",false)=="bl_rail_signal_light_red.obj")
assert(A.mesh("semaphore",true)=="bl_rail_signal_semaphore_green.obj")
for _,right in ipairs({false,true}) do
  for _,td in ipairs({0,1,2,3,4,5,8,9,10,11,12,13}) do
    local u,v=A.anchor(td,right)
    print(td,u,v)
    local p,r=A.pose(9,11,6.5,td,right)
    if p then print(p.x,p.y,p.z,r.y) end
  end
end
'''
    out=iter(subprocess.check_output([lua,"-"],cwd=ROOT,input=probe,text=True).splitlines())
    if source:
        text=source.read_text()
        block=text.split("static const Point SignalPositions[2][12]")[1].split("uint x =")[0]
        values=[tuple(map(int,p)) for p in re.findall(r"\{\s*(\d+)\s*,\s*(\d+)\s*\}",block)]
        assert len(values)==24
        # Cross-check the index mapping against DrawSignals and the stock
        # "along" bit convention instead of guessing from sprite names.
        stock_rail=source.with_name("rail.cpp")
        if stock_rail.is_file():
            relevant=text.split("static void DrawSignals(")[1].split("static void DrawTile_Track")[0]
            loc={(track,1<<int(bit)):int(pos) for bit,pos,track in re.findall(
                r"MAYBE_DRAW_SIGNAL\((\d+),\s*SIGNAL_TO_\w+,\s*(\d+),\s*TRACK_(\w+)\)",relevant)}
            along=stock_rail.read_text().split("_signal_along_trackdir[TRACKDIR_END]")[1].split("};")[0]
            bits=[int(v,0) for v in re.findall(r"\b(?:0x[0-9a-f]+|0)\b",along)]
            tracks=("X","Y","UPPER","LOWER","LEFT","RIGHT")
            assert len(bits)==14
            assert SLOT=={td:loc[tracks[td%8],bits[td]] for td in TD}
    else:
        values=[(8,5),(14,1),(1,14),(9,11),(1,0),(3,10),(11,4),(14,14),
                (11,3),(4,13),(3,4),(11,13),
                (14,1),(12,10),(4,6),(1,14),(10,4),(0,1),(14,14),(5,12),
                (11,13),(4,3),(13,4),(3,11)]
    for offset in (0,12):
        for td in TD:
            u,v=values[offset+SLOT[td]]
            assert tuple(map(int,next(out).split()))==(td,u,v)
            if td not in STRAIGHT:
                continue
            x,y,z,angle=map(float,next(out).split())
            assert (x,y,z)==(2*9-.5+u/8,6.5,2*11-.5+v/8)
            dx,dz=STRAIGHT[td]
            assert isclose(sin(angle),-dx,abs_tol=1e-12) and isclose(-cos(angle),-dz,abs_tol=1e-12)
    assert next(out,None) is None
    print("PASS: 24 stock trackdir anchors, eight verified straight-world poses, both light aspects and mechanical arm states")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua",default="lua5.1")
    parser.add_argument("--rail-cmd",type=Path)
    args=parser.parse_args()
    check_assets()
    check_positions(args.lua,args.rail_cmd)
