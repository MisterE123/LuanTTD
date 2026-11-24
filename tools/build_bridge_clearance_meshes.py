#!/usr/bin/env python3
"""Make a clear span using the original continuous deck without center bearings."""

from argparse import ArgumentParser
from pathlib import Path

MODELS = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
BEARING_GROUPS = {
    "road_bridge_wood": {"Pier_cap_timber", "Pier_cap_king_posts"},
    "road_bridge_concrete": {"Integral_bent_support_head", "Tapered_cast_shoulder", "Continue_to_pier_course"},
    "road_bridge_girder": {"Crosshead_bearings", "Chamfered_pier_cap", "Battered_cap_haunch", "Pier_crown"},
    "rail_bridge_wood": {"Trestle_twin_king_posts", "Main_bearing_seat", "Cross_cap_immediately_below_four_stringers",
                        "Cross_cap_lower_sole", "Bearing_cap_carriage_bolts"},
}

for family in ("concrete","girder"):
    BEARING_GROUPS["rail_bridge_"+family]=BEARING_GROUPS["road_bridge_"+family]


def clear_span(path, groups):
    lines = ["# Center bearing omitted; tools/build_bridge_clearance_meshes.py"]
    removed = set()
    skip = False
    for line in path.read_text().splitlines():
        typ, _, name = line.partition(" ")
        if typ == "o":
            skip = name in groups
            if skip:
                removed.add(name)
                continue
        # Retain indexed positions, UVs and normals unchanged. The OBJ
        # face lists alone determine which points become rendered vertices.
        if not skip or typ in ("v", "vt", "vn"):
            lines.append(line)
    assert removed == groups, (path, groups - removed)
    return "\n".join(lines) + "\n"


def main():
    p = ArgumentParser(description=__doc__)
    p.add_argument("--check", action="store_true")
    a = p.parse_args()
    for prefix, groups in BEARING_GROUPS.items():
        for axis in (0, 1):
            name = f"bl_{prefix}_span_{axis}"
            authored = clear_span(MODELS / (name + ".obj"), groups)
            out = MODELS / (name + "_road_clear.obj")
            if a.check:
                assert out.read_text() == authored, out
            else:
                out.write_text(authored)


if __name__ == "__main__":
    main()
