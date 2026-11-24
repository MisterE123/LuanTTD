#!/usr/bin/env python3
"""Seams, bearing orientation, swept clearance and both shared finishes."""
from itertools import product
from fast_girder_art import ROOT, MODELS, TEXTURES, read, profile, flip, DIR
from concrete_suspension_art import check_closed_v

BEARINGS = {"Cantilever_cast_seat", "Cantilever_elastomer"}
SEAM = ["Running_deck_diaphragm", "Rolled_bottom_chord", "Deck_edge_stringer", "Boxed_upper_chord"]

def main():
    checks = 0
    assert (ROOT / "art/steel_cantilever.blend").stat().st_size > 30_000
    for mode, axis in product(("road", "rail"), (0,1)):
        stem = f"bl_{mode}_bridge_cantilever"
        names = SEAM + (["Running_asphalt", "Shoulder_slab"] if mode=="road" else
                        ["Polished_railhead", "Rail_foot", "Rail_web"])
        d = 2 if axis==0 else 1
        dx, dz = DIR[d]
        sans = read(stem, f"span_{axis}_clear")
        span = read(stem, f"span_{axis}_minus")
        upper = read(stem, f"span_{axis}_minus_road_clear")
        assert set(span)-set(upper)==BEARINGS and set(sans)==set(upper)
        assert all(upper[k]==sans[k]==span[k] for k in upper)
        pier = read(stem, f"pier_{axis}_minus")["Cantilever_cutwater_core"]
        joint = {(x,z) for face in span["Cantilever_cast_seat"] for x,z,y in face if y==-.5}
        assert len(joint)==12 and all(-1<=dx*x+dz*z<-.70 for x,z in joint)
        assert joint=={(x,z) for face in pier for x,z,y in face if y==.5}
        check_closed_v(span,d,"Cantilever_cast_seat",-1,-.706,2)
        check_closed_v(span,d,"Cantilever_elastomer",-1,-.687,2)
        check_closed_v({"core":pier},d,"core",-1,-.706,2)
        want=profile(span,d,1,names)
        assert all(want.values()) and want==profile(span,d,-1,names)
        assert want==profile(sans,d,1,names)==profile(sans,d,-1,names)
        for kind in ("head_flat","head_ramp"):
            head=read(stem,f"{kind}_{d}")
            tail=read(stem,f"{kind}_{(d+2)%4}")
            assert want==profile(head,d,1,names)==flip(profile(tail,(d+2)%4,1,names))
            checks+=4*len(names)
        for depth in ("1","2","water"):
            assert (MODELS/f"{stem}_foot_{axis}_minus_{depth}.obj").stat().st_size>100
        palettes=[(TEXTURES/f"{stem}{t}.png").read_bytes() for t in ("","_brown","_red")]
        assert len(set(palettes))==3 and all(p[16:24]==palettes[0][16:24] for p in palettes)
    print(f"PASS {checks} cantilever part joins; shared finishes, directional piers, swept clearance")

if __name__=="__main__":
    main()
