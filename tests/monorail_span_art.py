#!/usr/bin/env python3
"""Tile seams and true bore clearance of the exported stock monorail."""
# SPDX-License-Identifier: GPL-2.0-only
from math import isfinite
import sys
from rail_span_art import ROOT, along_ray, basis, load, physical, profile, vehicle

mode=sys.argv[1] if len(sys.argv)>1 else "mono"
assert mode in {"mono","maglev"}
P=f"bl_guideway_{mode}_span_"
FAMILY={
    "mono": (("Monorail_surface:_cast_segment_running_band","Beveled_top_shoulders_and_sides"),
             ("bl_rail_x2001","bl_rail_mono_passenger","bl_rail_mono_mail"),.246,"monorail"),
    "maglev": (("Paired_polished_magnetic_guide_rails","Raised_guidance_walls","Recessed_steel_motor_shelf",
                "Central_induction_strip"),
               ("bl_rail_lev1","bl_rail_maglev_passenger","bl_rail_maglev_mail"),.213,"maglev"),
}
seams,bodies,rim,title=FAMILY[mode]
seams=(*seams,"Cross-tied_foundation_slab")
profiles=0
rays=0
for d in range(4):
    axis=d%2
    flat=load(f"bl_guideway_{mode}_flat_{1<<axis}")
    middle=load(f"{P}span_{axis}")
    clear=load(f"{P}span_{axis}_road_clear")
    for bearing in ("Trestle_twin_king_posts","Main_bearing_seat","Cross_cap_immediately_below_four_stringers"):
        assert physical(middle,bearing) and not physical(clear,bearing)
    portal=load(f"{P}tunnel_{d}")
    for section,shift in (("head_flat",-1),("head_ramp",0)):
        head=load(f"{P}{section}_{d}")
        for plain in seams:
            group="Guideway_/_"+plain
            inner=profile(head,d,1,group,0)
            assert inner and inner==profile(middle,d,1,group,0)==profile(middle,d,-1,group,0), (d,section,group,inner)
            assert inner==profile(clear,d,-1,group,0)
            outer=profile(head,d,-1,group,shift)
            assert outer and outer==profile(flat,d,1,plain,0), (d,section,group,outer)
            assert outer==profile(portal,d,-1,group,0)==profile(portal,d,1,group,0)
            profiles+=7
    # Trace the real solid-state render surfaces at the roof across mid-
    # and corner positions. No black stop plane can hide a blocking mesh.
    bore=[tuple(basis(d,p) for p in face) for group,face in portal
         if group=="Coursed_brick_intrados"]
    assert bore
    for model in bodies:
        points=list(vehicle(model))
        assert points and all(isfinite(x) for p in points for x in p)
        for x,_,y in points[::7]:
            for at in (.660,.755,.900,.990):
                ys=list(along_ray(bore,2,x,at))
                assert ys and min(ys) > y-(.5-rim)+.11, (d,model,x,at,ys)
                rays+=1
assert (ROOT/f"art/{title}_spans.blend").stat().st_size>20000
print(f"PASS {profiles} {title} bridge/ramp/bore guideway seam checks and {rays} true roof-clearance rays")
