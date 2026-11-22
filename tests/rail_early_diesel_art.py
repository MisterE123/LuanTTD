#!/usr/bin/env python3
"""Runtime source-art checks for two physically distinct stock locomotives."""
from pathlib import Path
from struct import unpack

root = Path(__file__).resolve().parents[1]
mod = root / "mods" / "luanttd_core"
for tag, trucks, name, minimum in [
    ("hendry_25", 4, "Central_headcode_inset", 6800),
    ("uu_37", 6, "Split_headcode_pod", 8400),
]:
    model = (mod / "models" / f"bl_rail_{tag}.obj").read_text().splitlines()
    verts = []
    groups = {}
    part = None
    for line in model:
        typ, _, body = line.partition(" ")
        if typ == "o":
            part = body
            groups[part] = []
        elif typ == "v":
            coords = tuple(map(float, body.split()))
            verts.append(coords)
            groups[part].append(coords)
    assert len(verts) >= minimum and max(abs(v[2]) for v in verts) == 4.99
    for part_name in [name, "Driver's_raked_screen_and_seal", "Crew_stair_grated_carriage_step",
                      "Pressed_intake_louvre_with_projected_visor", "Physical_formed_roof_fan_guard"]:
        assert len(groups[part_name]) >= 8
    axle = groups["Full_width_0.424-gauge_road_axle"]
    # Each axle's two longitudinal extremal vertices delimit a group of 12
    # rim vertices at each X cap. The groups use different real wheelbases.
    centers = sorted(set(round(v[2], 3) for v in groups["Outboard_bearing_shoulder"]))
    assert len(axle) >= trucks * 24 and len(centers) >= trucks * 3, (tag, trucks, len(axle), centers)
    png = (mod / "textures" / f"bl_rail_{tag}.png").read_bytes()
    assert png.startswith(b"\x89PNG") and unpack(">II", png[16:24]) == (336, 8)
    blend = (root / "art" / f"rail_{tag}.blend").read_bytes()
    assert len(blend) > 100_000 and blend[:4] == b"\x28\xb5\x2f\xfd"
assert (mod / "textures" / "bl_rail_hendry_25.png").read_bytes() != (mod / "textures" / "bl_rail_uu_37.png").read_bytes()
print("PASS two original rolling-stock meshes, 4/6 axles, source blend files, dimensions and independent liveries")
