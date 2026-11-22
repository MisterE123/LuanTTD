#!/usr/bin/env python3
"""Derive compact, below-node footings from the original pier meshes.

Retain the finished bridge, cap and bracing, continuing just the structural
column profiles into a lowered corner surface or a submerged bed. Source vertex and atlas UV
data come from the existing editable bridge art exports.
"""
from pathlib import Path

MODELS = Path(__file__).resolve().parents[1] / "mods/bayline/models"
COLUMNS = {
    "road_bridge_wood": "Trestle_legs",
    "road_bridge_concrete": "Pier_stack_load-bearing_core",
    "road_bridge_girder": "Octagonal_concrete_pier",
    "rail_bridge_wood": "Trestle_twin_king_posts",
}


def write_feet(family, group, axis, depth):
    source = MODELS / f"bl_{family}_pier_{axis}.obj"
    positions, uv, sides = [], [], []
    inside = False
    for line in source.read_text().splitlines():
        bits = line.split()
        if not bits:
            continue
        kind, *values = bits
        if kind == "o":
            inside = values == [group]
        if kind == "v":
            positions.append(tuple(map(float, values)))
        elif kind == "vt":
            uv.append(line)
        elif kind == "f" and inside:
            face = [tuple(int(index) for index in token.split("/")[:2]) for token in values]
            if len({positions[i - 1][1] for i, _ in face}) > 1:
                sides.append(face)
    assert 8 <= len(sides) <= 64, (source, len(sides))
    result = ["# Original pier core continuation; see tools/build_bridge_pier_feet.py", *uv]
    remap = {}
    for side in sides:
        for i, _ in side:
            if i not in remap:
                x, y, z = positions[i - 1]
                remap[i] = len(remap) + 1
                # Rendered in the spare southeast terrain node; track and
                # road geometry still use the even-position tile anchor.
                # Luanti reflects the OBJ X coordinate when importing.
                if depth == "water":
                    # Mounted one node above the water cell. The core joins
                    # the existing leg at y=-.5, and reaches beyond the
                    # maximum stock 4*0.5-node downward wave excursion.
                    y = -.482 if y > 0 else -2.55
                else:
                    y = .5 if y > 0 else .475 - depth
                result.append(f"v {x + 1:.6f} {y:.6f} {z - 1:.6f}")
    for side in sides:
        result.append("f " + " ".join(f"{remap[i]}/{t}" for i, t in side))
    output = MODELS / f"bl_{family}_foot_{axis}_{depth}.obj"
    output.write_text("\n".join(result) + "\n")


def main():
    for family, group in COLUMNS.items():
        for axis in (0, 1):
            for depth in (1, 2, "water"):
                write_feet(family, group, axis, depth)


if __name__ == "__main__":
    main()
