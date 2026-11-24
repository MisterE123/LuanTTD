#!/usr/bin/env python3
"""Original, distinct overhead silhouettes for the two large-airport tools."""
from pathlib import Path
from PIL import Image, ImageDraw

out = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core/textures"
for kind in ("international", "intercontinental"):
    wide = kind == "intercontinental"
    im = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((3, 3, 60, 60), 8, fill="#183247", outline="#92b1b7", width=2)
    for y in (14, 47):
        d.rounded_rectangle((11, y, 52, y + 5), 2, fill="#9fe7dc")
        for x in range(15, 49, 6):
            d.point((x, y + 2), fill="#183247")
    if wide:
        d.polygon(((17, 24), (23, 24), (23, 29), (41, 29), (41, 24), (47, 24),
                   (47, 41), (41, 41), (41, 35), (23, 35), (23, 41), (17, 41)), fill="#efcd8b")
    else:
        d.rectangle((26, 26, 39, 39), outline="#efcd8b", width=3)
        d.line(((13, 33), (24, 33)), fill="#efcd8b", width=3)
        d.line(((41, 33), (51, 33)), fill="#efcd8b", width=3)
    im.save(out / f"bl_dispatch_{kind}_airport.png")
