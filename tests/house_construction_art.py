#!/usr/bin/env python3
"""Ground datum, retained footing geometry, and visible construction stages."""
from pathlib import Path
from math import isclose
import struct

from rail_span_art import along_ray,load

ROOT=Path(__file__).resolve().parents[1]
EPS=6.e-6

def site_hits(m,groups,axis,u,v):
    return list(along_ray([p for g,p in m if g in groups],axis,u,v))

def main():
    models=[load("bl_house_build_stage_"+str(i)) for i in range(3)]
    data=(ROOT/"mods/luanttd_core/textures/bl_house_build_atlas.png").read_bytes()
    w,h=struct.unpack_from(">II",data,16)
    assert data[:8]==b"\x89PNG\r\n\x1a\n" and w%8==0 and h==8
    pts=[[p for g,ps in m for p in ps] for m in models]
    peak=[]
    for i,a in enumerate(pts):
        assert max(max(abs(x),abs(z)) for x,z,h in a)<.900
        assert min(h for x,z,h in a)>=-.5001
        peak.append(max(h+.5 for x,z,h in a))
    assert .18<peak[0]<.26 and .64<peak[1]<.69 and .98<peak[2]<1.06,peak
    for name in ("Mortared_deep_cottage_foundation_wall","Individually_dressed_exposed_foundation_stones",
                 "Dark_lower_strip_beneath_limestone_footing","Rough_interior_underfloor_concrete_service_ribs"):
        pts=[{p for g,ps in m for p in ps if g==name} for m in models]
        assert len(pts[0])>20 and pts[0]==pts[1]==pts[2]
    # Strings/field stakes disappear once the actual framed footprint rises.
    assert any(g=="Visible_site_building_line_strings" for g,ps in models[0])
    assert all(not any(g=="Visible_site_building_line_strings" for g,ps in m) for m in models[1:])
    # Opposite site area deliberately has open joists in stage 1 only.
    deck=("Individual_floor_sheathing_planks","Visible_subfloor_joists_at_regular_pitch")
    for x in (-.082,.081,.243):
        for z in (-.310,-.258,-.169):
            assert not site_hits(models[1],deck,2,x,z),(x,z)
            complete=site_hits(models[2],deck,2,x,z)
            assert complete and isclose(max(complete)+.5,.166,abs_tol=EPS),(x,z,complete)
    # Representative doorway rays fit the true framed opening with no card
    # or scene-wide panel across the street entrance.
    door=[p for g,p in models[1] if sum(v[1] for v in p)/3<-.395 and
          (g.startswith("Existing_end-wall_") or "future_door" in g or "doorway_lintel" in g)]
    for x in (.188,.251,.314):
        for h in (.276,.361,.423,.475):
            assert not list(along_ray(door,1,x,h-.5)),(x,h)
    shingles=("Course_of_physically_fitted_terracotta_roof_tiles",)
    rafters=("Actual_paired_gable_roof_rafters",)
    r=models[2]
    for z in (-.452,-.293,-.130,.015,.205):
        assert all(site_hits(r,shingles,2,x,z) for x in (-.420,-.280,-.105))
        assert all(not site_hits(r,shingles,2,x,z) for x in (.108,.255,.454))
    assert len([p for g,p in r if g in rafters])==240
    assert any(g=="Individual_ladder_rungs" for g,p in r)
    print(f"HOUSE_BUILD_ART_PASS all 3 stock stages on 2x2 tile, identical limestone ring, "
          f"true floor/door/roof apertures, peaks {', '.join(str(round(v,3)) for v in peak)}")

if __name__=="__main__":
    main()
