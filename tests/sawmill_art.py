#!/usr/bin/env python3
"""Native mesh/layout/working aperture checks for the authored sawmill."""
import argparse
from pathlib import Path
import re

from rail_span_art import load, along_ray

LAYOUT={(1,0):14,(1,1):12,(1,2):11,(2,0):14,(2,1):13,(0,0):15,(0,1):15,(0,2):12}
ROOT=Path(__file__).resolve().parents[1]
EPS=6e-6

def test(upstream):
    if upstream:
        source=Path(upstream).read_text()
        match=re.search(r'_tile_table_sawmill_0\s*{(.*?)};',source,re.S)
        native={(int(x),int(z)):int(gfx) for x,z,gfx in re.findall(r'MK\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',match[1])}
        assert native==LAYOUT
    files={tuple(map(int,p.stem.split("_")[-2:])) for p in
           (ROOT/"mods/bayline/models").glob("bl_sawmill_0_*.obj")}
    assert files==set(LAYOUT),files
    records={}
    for (x,z),gfx in LAYOUT.items():
        a=load(f"bl_sawmill_0_{x}_{z}")
        records[x,z]=a
        assert min(y for g,ps in a for u,v,y in ps)>-.5-EPS
        assert max(max(abs(u),abs(v)) for g,ps in a for u,v,y in ps)<=1+EPS
        assert len(a)>500,(x,z,len(a))
        if gfx==14:
            assert sum(g=="Roundwood_deck_exposed_concentric_end-grain_measures" for g,p in a)>700
        if gfx==13:
            assert any(g.startswith("Transverse_overhead_log_sorting_bridge") for g,p in a)
            assert not any(u>.542 and y+.5>.071 for g,p in a for u,v,y in p)
    for d,name in ((0,"North_feed_bridge"),(1,"South_transfer_bridge")):
        a=records[1,d]
        b=records[1,d+1]
        def seam(model,at,tag):
            return {(round(x,5),round(y,5)) for g,p in model if g.startswith(tag)
                   for x,z,y in p if abs(z-at)<EPS}
        for v in ("_continuous_side_angle_rails","_brushed_running_flange"):
            a0,b0=seam(a,1,name+v),seam(b,-1,name+v)
            assert a0 and a0==b0,(d,v,a0,b0)
    saw=records[1,1]
    assert sum(g=="Individual_upper_sawtooth_edges" for g,p in saw)>=30
    assert any(g.startswith("Actual_installed_circular_mill_saw") for g,p in saw)
    # Representative sightlines from front door to the machine: architecture
    # must not pretend a front aperture with a painted dark polygon.
    doors=[p for g,p in saw if ("gabled_mill_end" in g or "working_bay_width" in g
           or "door_lintel" in g) and sum(q[1] for q in p)/3>0]
    targets=0
    for u in (-.35,-.24,-.11,0,.11,.24,.35):
        for h in (.275,.360,.448,.580,.644):
            assert not list(along_ray(doors,1,u,h-.5)),(u,h)
            targets+=1
    assert any(g=="Individual_sawn_timber_board" for g,p in records[0,2])
    print(f"SAWMILL_ART_PASS eight stock tiles, four exact coupled seam profiles, actual saw teeth and {targets} clear hall-sightline points")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-layout")
    test(p.parse_args().upstream_layout)
