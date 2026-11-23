#!/usr/bin/env python3
"""Editable Millennium power/saloon cab and physically distinct two-end stock."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from math import isfinite
root=Path(__file__).resolve().parents[1]
model=root/"mods/luanttd_core/models"
def load(body):
    verts,groups=[],set()
    for line in (model/f"bl_rail_millennium_z1{body}.obj").read_text().splitlines():
        if line.startswith("v "): verts.append(tuple(float(x)/10 for x in line[2:].split()))
        if line.startswith("o "): groups.add(line[2:])
    assert all(isfinite(v) for row in verts for v in row)
    return verts,groups
p,g=load("_body")
q,h=load("")
assert 800<len(p)<1200 and len(q)>len(p)+1200
assert 0.18<max(abs(x) for x,_,_ in p)<.24
assert .489<max(y for _,y,_ in p)<.515
assert .45<max(abs(z) for _,_,z in p)<.48
assert {"Driver_wraparound_window_seal","Individual_saloon_pressure_window_frames",
        "Accessible_side-entry_pressure_doors","Stock_guideway_rear_draw_eye"}<=g
assert g<=h and "Load_tires_seated_on_beam_crown" not in g and "Load_tires_seated_on_beam_crown" in h
assert (root/"art/rail_millennium_z1.blend").stat().st_size>120000
print("MILLENNIUM_ART_PASS separate editable head, real saloon and cockpit, distinct native straddle carriers")
