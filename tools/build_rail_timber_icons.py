#!/usr/bin/env python3
"""Original compact-route tools for the conventional rail Wood carrier."""
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
for name,mode in (("rail_timber_freight","section"),("rail_wood_load","load"),("rail_wood_unload","unload")):
    im=Image.new("RGBA",(48,48));d=ImageDraw.Draw(im)
    shell,metal="#263e41","#8ba09b"
    dark,wood,grain="#60422c","#a6754d","#e1be81"
    d.rounded_rectangle((3,3,44,44),7,fill=shell,outline=metal,width=2)
    d.line((8,36,40,36),fill=metal,width=2)
    for i,(x,y) in enumerate(((10,25),(15,18),(17,27))):
        length=30 if mode=="section" else 25
        d.polygon([(x,y),(length,y-4),(length+1,y+5),(x,y+8)],fill=dark,outline=wood)
        d.ellipse((x-3,y,x+5,y+8),fill=wood,outline=grain)
        d.ellipse((x-1,y+2,x+3,y+6),outline=grain)
    if mode!="section":
        arrow=[(32,17),(38,17),(38,24),(42,24),(35,32),(28,24),(32,24)]
        if mode=="unload":arrow=[(x,48-y) for x,y in arrow]
        d.polygon(arrow,fill="#739295",outline="#e4ebe2")
    else:
        d.line((32,14,28,32),fill="#6c8a99",width=3)
    im.save(root/("bl_dispatch_"+name+".png"),optimize=True)
