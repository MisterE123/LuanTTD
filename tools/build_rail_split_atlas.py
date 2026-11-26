#!/usr/bin/env python3
"""Generate the grass / bare ground and shared retaining brick rail atlas."""
from pathlib import Path
from PIL import Image
import argparse
import io

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--check", action="store_true")
a = p.parse_args()
root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
out = Image.new("RGB", (128, 256))
brick = Image.open(root / "bl_road_surface_retaining.png").convert("RGB")
assert brick.size == (32, 32)
# Repeat the exact same texture used by solid retaining nodes. The central
# repeats of the lower half are sampled by the mesh (see rail_foundation_uv.lua);
# unused repeats let texture filtering safely wrap the brick across seams.
for y in range(128, 256, 32):
    for x in range(0, 128, 32):
        out.paste(brick, (x, y))

for ground in ("bl_grass0.png", "bl_rail_barren.png"):
    with Image.open(root / ground) as top:
        out.paste(top.convert("RGB").resize((128, 128), Image.Resampling.NEAREST), (0, 0))
    if ground == "bl_grass0.png":
        green = out.copy()
for suffix,atlas in (("",green),("_barren",out)):
    target = root / f"bl_rail_split_foundation{suffix}_atlas.png"
    buf = io.BytesIO()
    atlas.save(buf, format="PNG", optimize=True)
    if a.check:
        actual = Image.open(target)
        assert actual.size == atlas.size and actual.tobytes() == atlas.tobytes()
    else:
        target.write_bytes(buf.getvalue())
