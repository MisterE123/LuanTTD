#!/usr/bin/env python3
"""Check shoulder/rail alignment, structural seams and alternate clear spans."""
from collections import defaultdict
from pathlib import Path
from itertools import product

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "mods/luanttd_core/models"
TEXTURES = MODELS.parent / "textures"
DIR = [(-1,0), (0,1), (1,0), (0,-1)]
COMMON = ["Twin_closed_welded_box_sections", "Continuous_flange_overhang",
          "Continuous_deck_diaphragm", "Continuous_guarded_walkway_barrier"]
BEARINGS = {"Fast_girder_crosshead", "Elastomeric_bearing_bank", "Pier_throat"}


def read(stem, part):
    vertices, groups = [], defaultdict(list)
    for line in (MODELS / f"{stem}_{part}.obj").read_text().splitlines():
        tag, _, data = line.partition(" ")
        if tag == "o":
            group = data
        elif tag == "v":
            x,y,z = map(float, data.split())
            vertices.append((-x-.5, z-.5, y))
        elif tag == "f":
            ids = [int(v.split("/")[0])-1 for v in data.split()]
            points = tuple(vertices[i] for i in ids)
            assert len(set(points))==3, (stem, part)
            groups[group].append(points)
    return groups


def profile(shape,d,edge,names):
    dx,dz=DIR[d]
    return {g:{(round(dz*x-dx*z,6),y) for f in shape[g] for x,z,y in f
               if round(dx*x+dz*z,6)==edge} for g in names}


def flip(data):
    return {g:{(-u,p) for u,p in pts} for g,pts in data.items()}


def main():
    checks=0
    asset=ROOT / "art/fast_girder.blend"
    assert asset.is_file() and asset.stat().st_size>30_000
    for mode,axis in product(("road", "rail"),(0,1)):
        names=COMMON+(["Running_asphalt","Shoulder_slab","Inlaid_centre_markings"]
                      if mode=="road" else ["Polished_railhead","Rail_foot","Rail_web"])
        stem=f"bl_{mode}_bridge_fast_girder"
        assert (TEXTURES/f"{stem}.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
        mid=read(stem,f"span_{axis}")
        clear=read(stem,f"span_{axis}_road_clear")
        assert set(mid)-set(clear)==BEARINGS and set(clear)<set(mid)
        assert all(clear[g]==mid[g] for g in clear)
        d=2 if axis==0 else 1
        want=profile(mid,d,1,names)
        assert want==profile(mid,d,-1,names)
        assert all(pts or g=="Inlaid_centre_markings" for g,pts in want.items())
        for kind in ("head_flat","head_ramp"):
            fore=read(stem,f"{kind}_{d}")
            aft=read(stem,f"{kind}_{(d+2)%4}")
            assert want==profile(fore,d,1,names)==flip(profile(aft,(d+2)%4,1,names))
            checks+=3*len(names)
        support=read(stem,f"pier_{axis}")["Deep_pier_core"]
        cap=mid["Pier_throat"]
        upper={(x,z) for f in support for x,z,y in f if y==.5}
        joint={(x,z) for f in cap for x,z,y in f if y==-.5}
        assert len(upper)==8 and upper==joint
        for depth in ("1","2","water"):
            assert (MODELS/f"{stem}_foot_{axis}_{depth}.obj").exists()
    print(f"PASS {checks} structural/driving-surface seams, matching clear-span structure and matching pier stacks on both axes")


if __name__ == "__main__":
    main()
