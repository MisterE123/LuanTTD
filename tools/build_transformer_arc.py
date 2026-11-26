#!/usr/bin/env python3
"""Build the original small emissive RC1 transformer-arc particle."""
from pathlib import Path
from PIL import Image, ImageDraw

im = Image.new("RGBA",(16,16))
d = ImageDraw.Draw(im)
for radius,color in ((4,(61,123,249,30)),(3,(99,175,255,70)),(2,(164,228,255,149))):
    d.ellipse((7-radius,7-radius,8+radius,8+radius),fill=color)
d.line((4,12,7,7,5,7,11,3),fill=(183,240,255,234),width=2)
d.line((4,12,7,7,5,7,11,3),fill=(248,253,255,255),width=1)
im.save(Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures/bl_transformer_arc.png",optimize=True)
