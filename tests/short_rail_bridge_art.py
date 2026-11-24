#!/usr/bin/env python3
"""Verify both standard rail decks against source-gauge art and ground seams."""
from itertools import product
from fast_girder_art import ROOT, MODELS, TEXTURES, read, profile, flip
from road_bridge_concrete_art import CONTINUOUS as ROAD_CAST_JOINTS
from road_bridge_girder_art import CONTINUOUS as ROAD_GIRDER_JOINTS

CAST = {"Integral_bent_support_head", "Tapered_cast_shoulder", "Continue_to_pier_course"}
GIRDER = {"Crosshead_bearings", "Chamfered_pier_cap", "Battered_cap_haunch", "Pier_crown"}
RAIL=["Polished_railhead", "Rail_foot", "Rail_web", "Rail_trough_foundation",
      "Rail_trough_drainage_lip", "Renewable_inner_check_steel"]


def main():
    checks=0
    for kind,axis in product(("concrete","girder"),(0,1)):
        stem=f"bl_rail_bridge_{kind}"
        assert (ROOT/f"art/rail_bridge_{kind}.blend").stat().st_size>30_000
        assert (TEXTURES/f"{stem}.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
        span=read(stem,f"span_{axis}")
        under=read(stem,f"span_{axis}_road_clear")
        assert set(span)-set(under)==(CAST if kind=="concrete" else GIRDER)
        assert all(under[k]==span[k] for k in under)
        assert "Running_asphalt" not in span
        names=list(ROAD_CAST_JOINTS if kind=="concrete" else ROAD_GIRDER_JOINTS)+RAIL
        d=2 if axis==0 else 1
        want=profile(span,d,1,names)
        assert all(want.values()) and want==profile(span,d,-1,names)
        # Gauge and height must match the original native timber line.
        timber=read("bl_rail_bridge_wood",f"span_{axis}")
        assert profile(span,d,1,RAIL[:3])==profile(timber,d,1,RAIL[:3])
        for name in ("head_flat","head_ramp"):
            lead=read(stem,f"{name}_{d}")
            tail=read(stem,f"{name}_{(d+2)%4}")
            assert want==profile(lead,d,1,names)==flip(profile(tail,(d+2)%4,1,names))
            checks+=3*len(names)
        pier=read(stem,f"pier_{axis}")
        cap,post=("Continue_to_pier_course","Pier_stack_load-bearing_core") if kind=="concrete" else (
            "Pier_crown","Octagonal_concrete_pier")
        assert {(x,z) for face in span[cap] for x,z,y in face if y==-.5}=={
            (x,z) for face in pier[post] for x,z,y in face if y==.5}
        for depth in ("1","2","water"):
            assert (MODELS/f"{stem}_foot_{axis}_{depth}.obj").stat().st_size>100
    print(f"PASS {checks} short conventional rail joints, matching gauge, pier stacks, and clear spans")


if __name__=="__main__":
    main()
