#!/usr/bin/env python3
"""Render original 32 px gauge picker icons; no third-party sprite art."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
for suffix,background,edge in (("standard","#41464e","#b3c6d2"),("mono","#173944","#ffe0a6")):
    im=Image.new("RGBA",(128,128))
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((4,4,123,123),radius=19,fill=background,outline=edge,width=4)
    if suffix=="standard":
        for n in range(4):
            y=21+22*n
            d.polygon([(22,y+15),(100,y+15),(107,y+3),(29,y+3)],fill="#765745")
        for x in (44,80):
            d.polygon([(x-11,110),(x+2,110),(x+17,17),(x+5,17)],fill=edge)
    else:
        d.polygon([(30,103),(78,103),(99,21),(66,21)],fill="#a7cacf")
        d.polygon([(30,103),(24,113),(71,113),(78,103)],fill="#5a8992")
        d.polygon([(78,103),(71,113),(94,31),(99,21)],fill="#426b73")
        for y in (42,67,92):
            x=66-round((y-21)*33/82)
            d.line((x,y,x+38,y),fill="#40616a",width=4)
        d.polygon([(88,61),(105,61),(104,55),(120,69),(97,76),(100,69),(87,69)],fill=edge)
    im.resize((32,32),Image.Resampling.LANCZOS).save(ROOT/f"bl_dispatch_gauge_{suffix}.png")
