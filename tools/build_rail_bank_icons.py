#!/usr/bin/env python3
"""Original rail-bank menu icons; nothing copied from the source sprites."""
from pathlib import Path
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
for name,mode in (("rail_bank_freight","bank"),("rail_valuables_load","load"),("rail_valuables_unload","unload")):
    im=Image.new("RGBA",(48,48));d=ImageDraw.Draw(im)
    d.rounded_rectangle((3,3,44,44),7,fill="#202c42",outline="#819087",width=2)
    ivory,gold,blue,dark="#f0e6cb","#edc97e","#5b83a7","#17222e"
    d.line((8,36,40,36),fill="#87918c",width=2)
    if mode=="bank":
        d.polygon([(9,18),(24,9),(39,18)],fill=ivory)
        d.rectangle((12,19,36,22),fill=blue)
        for x in (13,22,31):d.rectangle((x,22,x+4,31),fill=ivory)
        d.rectangle((10,32,38,35),fill=ivory)
    else:
        d.polygon([(10,24),(15,20),(14,16),(20,16),(19,20),(24,24),(25,29),(21,33),(12,33),(8,29)],
                  fill=gold,outline=ivory)
        d.line((14,20,19,20),fill=dark,width=2)
        arrow=[(31,16),(37,16),(37,24),(41,24),(34,32),(27,24),(31,24)]
        if mode=="unload":arrow=[(x,48-y) for x,y in arrow]
        d.polygon(arrow,fill=blue,outline=ivory)
    im.save(root/("bl_dispatch_"+name+".png"),optimize=True)
