#!/usr/bin/env python3
"""Generate the original grass and dressed-stone atlas for split lines."""
from pathlib import Path
from PIL import Image
import argparse
import io

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--check", action="store_true")
a = p.parse_args()
root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
out = Image.new("RGB", (128, 128))
grass = Image.open(root / "bl_grass0.png").convert("RGB").resize((128, 64), Image.Resampling.NEAREST)
out.paste(grass, (0, 0))
for y in range(64, 128):
    course, v = divmod(y - 64, 16)
    for x in range(128):
        column, u = divmod(x + (course % 2) * 16, 32)
        grain = ((x * 17 + y * 37) ^ ((x + y) * 31)) % 9 - 4
        room = (column * 5 + course * 3) % 7 - 3
        if u < 2 or v < 2:
            c = (59, 67, 55)
        elif u == 2 or v == 2:
            c = (133, 141, 117)
        elif u == 31 or v == 15:
            c = (79, 88, 73)
        else:
            c = (105, 116, 96)
        out.putpixel((x, y), tuple(v + grain + room for v in c))
green=out.copy()
barren=Image.open(root / "bl_rail_barren.png").convert("RGB").resize((128,64),Image.Resampling.NEAREST)
out.paste(barren,(0,0))
for suffix,atlas in (("",green),("_barren",out)):
    target = root / f"bl_rail_split_foundation{suffix}_atlas.png"
    buf = io.BytesIO()
    atlas.save(buf, format="PNG", optimize=True)
    if a.check:
        actual = Image.open(target)
        assert actual.size == (128, 128) and actual.tobytes() == atlas.tobytes()
    else:
        target.write_bytes(buf.getvalue())
