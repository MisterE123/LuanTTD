#!/usr/bin/env python3
"""Derive 20 lightweight forest variants from the four original scenery trees.

Only vertex positions change. The authored topology, normals and UVs still
point at bl_scenery_palette.png. The input meshes and editable trees are
build_scenery_art.py's bl_scenery_tree_{0..3}.obj / scenery_tree_{0..3}.blend.
"""
from argparse import ArgumentParser
from pathlib import Path


ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
AUTHOR_ROOT_Y=-.5
SCALE=.72
LEVELS=5


def transform(lines,level):
    """Root height relative to node b+2; vertices are already native Y-up."""
    yroot=-1.5+level/2
    for line in lines:
        if line.startswith("v "):
            x,y,z=(float(v) for v in line.split()[1:])
            yield f"v {x*SCALE:.6f} {yroot+(y-AUTHOR_ROOT_Y)*SCALE:.6f} {z*SCALE:.6f}"
        elif not line.startswith("#"):
            yield line


def render(source,style,level):
    lines=source.read_text(encoding="utf-8").splitlines()
    header=(f"# Original scenery_tree_{style}.blend / bl_scenery_tree_{style}.obj, "
            "stock forest placement derived by tools/build_stock_forest_art.py")
    return "\n".join([header,*transform(lines,level)])+"\n"


def main(args):
    for style in range(4):
        source=MODELS/f"bl_scenery_tree_{style}.obj"
        for level in range(LEVELS):
            dest=MODELS/f"bl_stock_forest_{style}_{level}.obj"
            expected=render(source,style,level)
            if args.check:
                if not dest.exists() or dest.read_text(encoding="utf-8")!=expected:
                    raise SystemExit(f"stale stock forest asset: {dest.name}")
            else:
                dest.write_text(expected,encoding="utf-8",newline="\n")


if __name__=="__main__":
    p=ArgumentParser(description=__doc__)
    p.add_argument("--check",action="store_true",help="check deterministic outputs without rewriting")
    main(p.parse_args())
