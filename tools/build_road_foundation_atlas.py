#!/usr/bin/env python3
"""Combine existing original road and retaining rasters for Luanti's single-buffer OBJ."""
from pathlib import Path

from PIL import Image

textures = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
with Image.open(textures / "bl_road_surface_retaining.png") as raw:
    wall = raw.convert("RGB")
assert wall.size == (32, 32)
def compose(top, filename):
    assert top.size == (32, 32)
    out = Image.new("RGB", (64, 32))
    out.paste(top, (0, 0))
    out.paste(wall, (32, 0))
    out.save(textures / f"bl_{filename}.png", optimize=True)


for mask in (5, 10):
    with Image.open(textures / f"bl_road_surface_{mask}.png") as raw:
        compose(raw.convert("RGB"), f"road_grade_foundation_{mask}")

# A mesh modifier such as ^[sheet supplies only the top image. A
# single-buffer OBJ still needs both halves in the same physical atlas.
with Image.open(textures / "bl_roadside_grade_sheet.png") as raw:
    roadside = raw.convert("RGB")
for cell in range(4):
    compose(roadside.crop((32 * cell, 0, 32 * (cell + 1), 32)), f"roadside_grade_foundation_{cell}")
for kind, source in (("grass", "bl_grass2.png"), ("barren", "bl_rail_barren.png")):
    with Image.open(textures / source) as raw:
        compose(raw.convert("RGB").resize((32, 32), Image.Resampling.NEAREST), f"pure_tram_grade_foundation_{kind}")
