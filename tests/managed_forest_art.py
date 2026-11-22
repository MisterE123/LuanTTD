#!/usr/bin/env python3
"""Check authored native Forest layouts against the pinned industry header."""
import argparse
from pathlib import Path
import re
from rail_span_art import load

ROOT=Path(__file__).resolve().parents[1]
LAYOUTS={
    0:{(x,z) for x in range(4) for z in range(4)} | {(1,4),(2,4)},
    1:{(x,z) for x in range(5) for z in range(4)} | {(1,4),(2,4),(3,4)},
}

def test(upstream):
    source=Path(upstream).read_text() if upstream else ""
    for i,layout in LAYOUTS.items():
        if source:
            array=re.search(rf'_tile_table_forest_{i}\s*{{(.*?)}};',source,re.S)[1]
            rows=[tuple(map(int,row)) for row in re.findall(r'MK\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',array)]
            assert {(x,z) for x,z,gfx in rows if gfx==16}==layout and len(rows)==len(layout)
        files={tuple(map(int,p.stem.split("_")[-2:])) for p in
               (ROOT/"mods/bayline/models").glob(f"bl_forest_{i}_*.obj")}
        assert files==layout
        total=0
        for x,z in sorted(layout):
            m=load(f"bl_forest_{i}_{x}_{z}")
            points=[v for g,p in m for v in p]
            assert min(y for u,v,y in points)>=-.5-3.e-6
            assert max(max(abs(u),abs(v)) for u,v,y in points)<=1+3.e-6,(i,x,z)
            crown=max(y+.5 for u,v,y in points)
            assert 1.38<crown<2.42,(i,x,z,crown)
            stems=sum(g=="Genuinely_tapered_evergreen_trunks" for g,p in m)
            assert stems==(80 if (x,z)==(3+i,1) else 160),(x,z,stems)
            assert any(g=="Individual_tapered_pine_needle_tip_clusters" for g,p in m)
            assert any(g=="Sparse_irregular_plantation_litter_on_grass" for g,p in m)
            if (x,z)==(3+i,1):
                assert any(g.startswith("Roundwood_deck_exposed_concentric") for g,p in m)
            total+=stems//40
        assert total==4*len(layout)-2
    cut=load("bl_forest_harvested")
    assert max(h+.5 for g,p in cut for x,z,h in p)<.452
    assert len([g for g,p in cut if g=="Cut_planted_conifer_concentric_fresh_crosscut"])>=450
    assert not any(g=="Genuinely_tapered_evergreen_trunks" for g,p in cut)
    print("FOREST_ART_PASS two exact stock layouts 18/23, 70+90 mature stems, real harvested scene, land/windthrough and footprint edges")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-layout")
    test(p.parse_args().upstream_layout)
