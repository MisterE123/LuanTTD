#!/usr/bin/env python3
"""Project all 12 native meshes back onto the pinned RC1 edge pixels."""
from pathlib import Path

models = Path("mods/luanttd_core/models")
points = (
    ((3, 0, 12), (4, 2, 10), (6, 2, 6)),
    ((0, 6, 14), (5, 12, 16), (6, 10, 14)),
    ((0, 14, 6), (2, 14, 10), (7, 16, 4)),
    ((1, 4, 0), (2, 6, 2), (4, 10, 2)),
)
contacts = ((0, 8), (8, 16), (16, 8), (8, 0))
slots = ((1, 0, 0), (0, 0, 1), (1, 0, 1), (0, 1, 0))

def center(rows, coord):
    axis = [row[coord] for row in rows]
    return (min(axis) + max(axis)) / 2

for edge, choices in enumerate(points):
    dx, dy, dz = slots[edge]
    for direction, px, pz in choices:
        path = models / f"bl_rail_distributed_pylon_{edge}_{direction}.obj"
        groups = {}
        for line in path.read_text().splitlines():
            if line.startswith("o "):
                part = groups[line[2:]] = []
            elif line.startswith("v "):
                u, y, v = map(float, line.split()[1:])
                part.append((-u-.5+dx, v-.5+dz, y+1.5+dy))
        base = groups["Cast_beveled_pier"]
        shoe = groups["Porcelain_shoe_hanger"]
        for part, point in ((base, (px, pz)), (shoe, contacts[edge])):
            for axis in range(2):
                assert abs(center(part, axis) - (point[axis]-8)/8) < 1e-5, (path, point)
        assert abs(min(row[2] for row in base)) < 1e-5, path
        clip = groups["Rigid_mounting_clip"]
        assert min(row[2] for row in clip) < .907 < max(row[2] for row in clip), path
for pattern in ("bl_rail_compound_contact_*.obj", "bl_rail_pair_contact_*.obj", "bl_rail_pair_single_*.obj"):
    for path in models.glob(pattern):
        raw = path.read_text()
        assert "Bolted_swing_support" not in raw and "portal_foundation" not in raw, path
print("PASS 12 exact edge support locations and grounded feet, including raised native node slot")
