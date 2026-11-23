#!/usr/bin/env python3
"""Verify the original magnetic suspension clears the native RC1 guideway."""
# SPDX-License-Identifier: GPL-2.0-only
from collections import defaultdict
from math import hypot
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "mods/luanttd_core/models"

def mesh(suffix, prefix="bl_rail_"):
    points, groups, group = [], defaultdict(set), None
    for line in (MODELS / f"{prefix}{suffix}.obj").read_text().splitlines():
        op, _, data = line.partition(" ")
        if op == "v":
            x, y, z = map(float, data.split())
            points.append((-x / 10, y / 10, z / 10))
        elif op == "o":
            group = data
        elif op == "f":
            assert group
            groups[group].update(int(v.split("/")[0]) - 1 for v in data.split())
    assert groups and points
    return {name: [points[i] for i in indices] for name, indices in groups.items()}

gear = mesh("maglev_suspension")
shoes = gear["Four_genuine_magnetic_load_shoes"]
fins = gear["Independent_lateral_stabilization_fin"]
assert len(shoes) >= 32 and len(fins) >= 64, (len(shoes), len(fins))
# Tie these dimensions to the modeled alloy walls and copper stator,
# rather than checking a nominal train height against itself.
guide = mesh("maglev_flat_1", "bl_guideway_")
rim = guide["Paired_polished_magnetic_guide_rails"]
stator = guide["Exposed_copper_armature_segments"]
shelf = guide["Recessed_steel_motor_shelf"]
# Guideway OBJ is tile-scaled by its renderer (10x relative to rolling stock).
rim_height = 10 * rim[0][1] + .5
half_channel = min(abs(10*z - .5) for _, _, z in shelf)
assert abs(half_channel - .091) < 1e-5  # the shelf extends to the .183 wall
half_channel = max(abs(10*z - .5) for _, _, z in shelf)
assert abs(half_channel - .183) < 1e-5
assert rim_height + min(y for _, y, _ in shoes) >= 10 * stator[0][1] + .5 + .019
assert rim_height + min(y for _, y, _ in fins) >= 10 * shelf[0][1] + .5 + .019
# Centered section and the sharpest standard quarter-circle bend (r=1).
# Check both sides; yaw is sampled at each independent gear pivot.
for x, y, z in [p for points in gear.values() for p in points if p[1] <= 0]:
    assert abs(x) < half_channel
    assert max(abs(hypot(1 + sign*x, z) - 1) for sign in [-1, 1]) < half_channel - .002

for name, detail in {
    "lev1": "Two_magnet-train_panoramic_cab_windscreens",
    "maglev_passenger": "Separately_framed_saloon_windows",
    "maglev_mail": "Two_explicit_postal_loading_bays",
}.items():
    body, coupled = mesh(name + "_body"), mesh(name)
    assert detail in body and detail in coupled
    assert gear.keys().isdisjoint(body) and gear.keys() <= coupled.keys()
    assert "Contact-free_mechanical_draw_link_pocket" in body
    assert all("wheel" not in label.lower() for label in coupled)
    source = ROOT / "art" / (f"rail_{name}.blend")
    assert source.read_bytes().startswith((b"BLENDER", bytes.fromhex("28 b5 2f fd")))
print("LEV1_ART_PASS three distinct editable bodies, separate magnetic carriers, and positive stator, fin and curve clearances")
