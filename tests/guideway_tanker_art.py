#!/usr/bin/env python3
"""Closed tanks and stocked suspension clearances on both advanced gauges."""
# SPDX-License-Identifier: GPL-2.0-only
from collections import Counter, defaultdict
from math import isfinite
from pathlib import Path

root=Path(__file__).resolve().parents[1]
for family in ("mono","maglev"):
    basename=f"rail_{family}_oil_tanker"
    path=root/"mods/luanttd_core/models"/f"bl_{basename}_body.obj"
    vertices,groups=[],defaultdict(list)
    for row in path.read_text().splitlines():
        op,_,words=row.partition(" ")
        if op=="v":
            p=tuple(float(q)/10 for q in words.split())
            assert all(map(isfinite,p))
            vertices.append(p)
        elif op=="o": name=words
        elif op=="f":
            f=[int(q.split("/")[0])-1 for q in words.split()]
            assert len(f)==3 and len(set(f))==3
            groups[name].append(f)
    assert len(vertices)>1300
    tank=groups["Closed_hydrocarbon_vessel_and_dished_endheads"]
    edges=Counter()
    oriented=Counter()
    signed_volume=0
    for a,b,c in tank:
        for i,j in ((a,b),(b,c),(c,a)):
            edges[tuple(sorted((i,j)))]+=1
            oriented[(i,j)]+=1
        (x,y,z),(u,v,w),(A,B,C)=map(vertices.__getitem__,(a,b,c))
        signed_volume+=(x*(v*C-w*B)+y*(w*A-u*C)+z*(u*B-v*A))/6
    assert len(tank)>600 and set(edges.values())=={2}
    assert all(oriented[j,i]==n for (i,j),n in oriented.items())
    assert .039<signed_volume<.068, signed_volume
    assert max(abs(x) for x,_,_ in vertices)<=.19
    assert max(y for _,y,_ in vertices)<.46
    assert max(abs(z) for _,_,z in vertices)<.47
    assert len(groups["Closed_filling_cover"])>90 and groups["Sealed_unloading_pipe"]
    assert len(groups["Open_ladder_rungs_at_vessel_end"])>120
    assert groups["Coupling_socket_at_guideway_height"]
    assert (root/"art"/f"{basename}.blend").stat().st_size>120000
    assert (root/"mods/luanttd_core/textures"/f"bl_{basename}.png").is_file()
    print(f"GUIDEWAY_TANKER_ART_PASS {family}, native sealed vessel {signed_volume:.5f}, true ladder, hatches and outfitted drain")
