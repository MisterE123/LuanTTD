#!/usr/bin/env python3
"""Combine the editable rail profiles for independent, coplanar track pairs.

Regenerate after authoring the individual Blender/catenary/guideway pieces.
Each track keeps its original bevels, texture and connection profile.
"""
from itertools import product
from pathlib import Path
import argparse

MODELS = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
PAIRS = {12: (4, 8), 48: (16, 32)}


def combine(inputs):
    kinds = ("v", "vt", "vn")
    rows = {k: {} for k in kinds}
    faces = []
    for source in inputs:
        indices = {k: [0] for k in kinds}
        for line in source.read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            kind, _, value = line.partition(" ")
            if kind in rows:
                index = rows[kind].setdefault(value, len(rows[kind]) + 1)
                indices[kind].append(index)
            elif kind == "f":
                face = []
                for v in value.split():
                    triplet = tuple(map(int, v.split("/")))
                    assert all(i > 0 for i in triplet)
                    face.append("/".join(str(indices[k][i]) for k, i in zip(kinds, triplet, strict=True)))
                faces.append("f " + " ".join(face))
            elif kind not in ("o", "g", "s"):
                raise ValueError(f"Unknown OBJ feature {kind!r} in {source}")
    header = ["# LuanTTD / regenerate with tools/build_parallel_rail_art.py"]
    return "\n".join(header + [f"{k} {v}" for k in kinds for v in rows[k]] + faces) + "\n"


def models():
    for mask, parts in PAIRS.items():
        for a, b in product(range(4), repeat=2):
            key = f"{mask}_{a}_{b}"
            if not a and not b:
                continue  # the original dual mask already depicts two stock bends
            sources = [
                MODELS / (f"bl_rail_eased_{bit}_{mode}.obj" if mode else f"bl_rail_track_{bit}.obj")
                for bit, mode in zip(parts, (a, b))
            ]
            yield MODELS / f"bl_rail_dual_{key}.obj", sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    count = 0
    for destination, sources in models():
        content = combine(sources)
        if args.check:
            assert destination.read_text() == content, destination
        else:
            temp = destination.with_suffix(".new")
            temp.write_text(content)
            temp.replace(destination)
        count += 1
    print(f"{'Verified' if args.check else 'Generated'} {count} paired-track meshes")


if __name__ == "__main__":
    main()
