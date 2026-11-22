#!/usr/bin/env python3
"""Combine existing original road and retaining rasters for Luanti's single-buffer OBJ."""
from pathlib import Path

from PIL import Image

textures = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
with Image.open(textures / "bl_road_surface_retaining.png") as raw:
    wall = raw.convert("RGB")
assert wall.size == (32, 32)
for mask in (5, 10):
    with Image.open(textures / f"bl_road_surface_{mask}.png") as raw:
        top = raw.convert("RGB")
    assert top.size == (32, 32)
    out = Image.new("RGB", (64, 32))
    out.paste(top, (0, 0))
    out.paste(wall, (32, 0))
    out.save(textures / f"bl_road_grade_foundation_{mask}.png", optimize=True)
