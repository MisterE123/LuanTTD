#!/usr/bin/env python3
"""Draw pixel-scale copper/blue ore and steel freight tools."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
shell, charcoal, metal = "#1a2f38", "#101e24", "#d8ded9"
ore, steel = "#c88c5b", "#82b9c1"

def paint(name, cargo=None, unload=False):
    im = Image.new("RGBA", (48, 48))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((3, 3, 44, 44), 7, fill=shell, outline="#729492", width=2)
    d.line((7, 36, 40, 36), fill="#849893", width=2)
    for x in (10, 16, 31, 37):
        d.line((x, 39, x+3, 35), fill="#61767a", width=2)
    if not cargo:
        d.polygon([(8, 29), (16, 13), (25, 20), (27, 30)], fill=ore, outline=metal)
        d.polygon([(25, 29), (29, 24), (38, 24), (35, 29)], fill=steel, outline=metal)
        d.polygon([(24, 34), (29, 29), (39, 29), (36, 34)], fill=steel, outline=metal)
    else:
        color = ore if cargo == "iron_ore" else steel
        if cargo == "iron_ore":
            d.polygon([(8, 29), (11, 19), (17, 15), (23, 21), (24, 29)], fill=color, outline=metal)
            d.line((11, 20, 17, 23, 23, 21), fill=charcoal, width=2)
        else:
            for y in (16, 23):
                d.polygon([(8, y+5), (12, y), (26, y), (23, y+5)], fill=color, outline=metal)
        d.ellipse((12, 30, 17, 35), fill=charcoal)
        d.ellipse((20, 30, 25, 35), fill=charcoal)
        arrow = [(31, 21), (31, 28), (28, 28), (34, 35), (40, 28), (37, 28), (37, 21)]
        if unload:
            arrow = [(x, 48-y) for (x, y) in arrow]
        d.polygon(arrow, fill=color, outline=metal)
    im.save(root / ("bl_dispatch_" + name + ".png"), optimize=True)

paint("rail_metals")
for kind in ("iron_ore", "steel"):
    for role in ("load", "unload"):
        paint(f"rail_{kind}_{role}", kind, role == "unload")
