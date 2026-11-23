#!/usr/bin/env python3
"""Original stock farm rail freight icons and a distinct Goods submenu icon."""
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
def ear(d,x,y):
    ink="#d6ae64";light="#f8dda1"
    d.line((x,y+9,x+10,y-11),fill=light,width=2)
    for ax,az in ((0,3),(2,-2),(5,-6),(8,-10)):
        d.ellipse((x+ax-3,y+az-4,x+ax+1,y+az+1),fill=ink)
        d.ellipse((x+ax+2,y+az-2,x+ax+6,y+az+3),fill=light)
def cow(d,x,y):
    fill="#b8cbbd";dark="#2d403f"
    d.polygon([(x-9,y-6),(x-6,y-2),(x-5,y+6),(x+4,y+6),(x+6,y-2),(x+9,y-6),(x+4,y-5),(x-4,y-5)],fill=fill)
    d.rounded_rectangle((x-6,y+4,x+6,y+8),2,fill="#d6af97")
    d.point((x-3,y),fill=dark);d.point((x+3,y),fill=dark)
def draw(name,cargo,mode=None):
    im=Image.new("RGBA",(48,48));d=ImageDraw.Draw(im)
    shell="#243631";metal="#84948a"
    d.rounded_rectangle((3,3,44,44),7,fill=shell,outline=metal,width=2)
    d.line((8,36,40,36),fill=metal,width=2)
    if cargo=="farm":
        ear(d,10,25);cow(d,31,24)
    elif cargo=="goods":
        for x,y in ((12,23),(24,23),(18,12)):
            d.rectangle((x,y,x+11,y+11),fill="#9c733c",outline="#f4d68d")
            d.line((x+1,y+1,x+10,y+10),fill="#dfbb71",width=1)
    else:
        if cargo=="grain":ear(d,12,25)
        else:cow(d,17,24)
        arrow=[(31,16),(37,16),(37,24),(41,24),(34,32),(27,24),(31,24)]
        if mode=="unload":arrow=[(x,48-y) for x,y in arrow]
        d.polygon(arrow,fill="#6c9c95",outline="#dce6da")
    im.save(root/("bl_dispatch_"+name+".png"),optimize=True)
draw("rail_farm_freight","farm")
draw("rail_goods_freight","goods")
for cargo in ("grain","livestock"):
    for mode in ("load","unload"):draw(f"rail_{cargo}_{mode}",cargo,mode)
