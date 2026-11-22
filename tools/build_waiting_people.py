#!/usr/bin/env python3
"""Original 1950s pedestrian silhouettes for a small station-platform crowd."""
from pathlib import Path
from PIL import Image, ImageDraw
out=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
pal=[
    ("#d8ad7c","#346358","#cfa352"),
    ("#a86444","#8c4331","#debc80"),
    ("#e0bc98","#345276","#537299"),
    ("#845337","#756338","#d6aa63"),
    ("#dcad86","#76576d","#b7838e"),
    ("#b67f59","#52735a","#a4b175"),
]
for i,(skin,coat,hat) in enumerate(pal,1):
    im=Image.new("RGBA",(64,64),(0,0,0,0))
    d=ImageDraw.Draw(im)
    dark="#242b32"
    # Transparent side padding means a square billboard shows a narrow
    # person, with occupied pixel height nearly equal to particle size.
    d.rounded_rectangle((25,9,38,25),radius=6,fill=dark)
    d.rounded_rectangle((27,11,36,24),radius=5,fill=skin)
    d.line((25,11,38,11),fill=hat,width=3)
    d.rounded_rectangle((26,6,37,11),radius=2,fill=hat)
    d.polygon([(26,22),(37,22),(43,29),(40,42),(37,42),
               (38,47),(26,47),(27,42),(24,42),(21,29)],
              fill=dark)
    d.polygon([(27,24),(36,24),(40,29),(37,43),(26,43),(24,30)],fill=coat)
    d.line((31,25,32,42),fill=hat,width=2)
    d.rectangle((25,43,30,58),fill=dark)
    d.rectangle((33,43,38,58),fill=dark)
    d.rectangle((23,57,31,60),fill="#22242b")
    d.rectangle((33,57,40,60),fill="#22242b")
    im.crop((0,6,64,61)).resize((64,64),Image.Resampling.NEAREST).save(out/f"bl_waiting_{i}.png",optimize=True)
print("Wrote six original transparent passenger silhouettes")
