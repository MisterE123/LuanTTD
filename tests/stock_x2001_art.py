#!/usr/bin/env python3
"""Native monorail geometry: real beam tires on a solid running crown."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from math import isfinite

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "mods/luanttd_core/models"


def mesh(stem):
    points, groups, uv = [], {}, 0
    for line in (MODELS / f"bl_{stem}.obj").read_text().splitlines():
        if line.startswith("o "):
            group = line[2:]
            groups[group] = set()
        elif line.startswith("vt "):
            uv += 1
        elif line.startswith("v "):
            x, y, z = map(float, line.split()[1:])
            assert all(map(isfinite, (x,y,z))), (stem, line)
            points.append((-x/10, z/10, y/10))
        elif line.startswith("f "):
            for v in line.split()[1:]:
                i, t, _ = map(int, v.split("/"))
                assert 1 <= i <= len(points) and 1 <= t <= uv, (stem, line)
                groups[group].add(points[i-1])
    assert all(groups.values()), stem
    return groups


def enamel(pts):
    return {round(p[0], 6) for p in pts if abs(p[2]) < 1e-6}


VA = "rail_x2001"
labels = ((VA, "Twin_bonded_driver_panes_with_physical_centre_mullion"),
    ("rail_mono_passenger", "Two_formed_passenger_door_leaves"),
    ("rail_mono_mail", "Twin_postal_loading_roller-door_recesses"))
tires="Load_tires_seated_on_beam_crown"
rollers="Under-beam_side_guide_rollers"
for asset, feature in labels:
    assert (ROOT / "art" / (asset+".blend")).stat().st_size > 20000
    assert (ROOT / "mods/luanttd_core/textures" / f"bl_{asset}.png").stat().st_size > 90
    groups=mesh(asset)
    body=mesh(asset+"_body")
    assert feature in groups and feature in body and tires not in body
    bounds=([min(v[k] for g in groups.values() for v in g) for k in range(3)],
            [max(v[k] for g in groups.values() for v in g) for k in range(3)])
    assert .37 <= bounds[1][0]-bounds[0][0] < .45
    assert .89 <= bounds[1][1]-bounds[0][1] < 1.
    assert .555 <= bounds[1][2]-bounds[0][2] < .57
    assert enamel(groups[tires]) == {-.06,-.02,.02,.06}
    contacts={(round(z,3)) for _,z,y in groups[tires] if abs(y)<1e-6}
    assert contacts=={-.299,-.219,.206,.286}, (asset, contacts)
    min_roller=min(abs(x) for x,_,_ in groups[rollers])
    assert .11799 < min_roller < .11801, (asset, min_roller)
    assert all(h<-.03 for _,_,h in groups[rollers])

bogie=mesh("rail_mono_bogie")
assert enamel(bogie[tires])=={-.06,-.02,.02,.06}
assert not any("shell" in k for k in bogie)
assert max(abs(z) for g in bogie.values() for _,z,_ in g) < .077
drawbar=mesh("rail_mono_drawbar")
assert {round(z,6) for f in drawbar.values() for _,z,_ in f}.issuperset({-.06,.06})
print("PASS X2001, 45-seat coach, and separate stock Mail Van: eight beam contacts each, isolated pivots and curve-ready split bodies.")
