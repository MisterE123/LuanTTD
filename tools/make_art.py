#!/usr/bin/env python3
"""Deterministic original pixel art. Requires Pillow; not needed to play."""
from pathlib import Path
from random import Random
from PIL import Image, ImageDraw

from road_surface_raster import road_raster
from terrain_rock_raster import texture_set, write_tunnels
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "mods/luanttd_core/textures"
OUT.mkdir(parents=True, exist_ok=True)
def canvas(fill=None):
    im = Image.new("RGBA", (32,32), fill)
    return im, ImageDraw.Draw(im)
def save(im, name):
    im.save(OUT / f"bl_{name}.png", optimize=True)
for terrain,base in {"grass":(87,129,76),"water":(42,97,126)}.items():
    for v in range(4):
        rand=Random(225+v)
        im,d=canvas((*base,255))
        if terrain=="water":
            for y in (6,15,24,29):
                x=rand.randrange(1,23)
                d.line((x,y,x+4+rand.randrange(6),y),fill=(69,132,158,255))
        else:
            for _ in range(39):
                x,y=rand.randrange(31),rand.randrange(31)
                diff=rand.choice((-13,-7,8,18))
                d.line((x,y,x+1,y),fill=tuple(c+diff for c in base)+(255,))
        # Keep ground edges the same base color. The 3D view does not
        # need a permanent voxel grid to expose tile boundaries.
        save(im,f"{terrain}{v}")
    save(im, f"{terrain}_side")
for name, image in texture_set():
    save(image, name)
def house(d,x,y,w=11,h=11,roof="#a95f50",wall="#edcf9c"):
    d.rectangle((x+2,y+3,x+w+2,y+h+2),fill=(32,43,32,145))
    d.rectangle((x,y+4,x+w,y+h),fill=wall)
    d.polygon([(x-1,y+5),(x+w//2,y),(x+w+1,y+5),(x+w,y+7),(x,y+7)],fill=roof)
    if w>=9:
        d.rectangle((x+2,y+8,x+3,y+9),fill="#36525b")
        d.rectangle((x+w-4,y+8,x+w-3,y+9),fill="#36525b")
    d.point((x+w//2,y+h),fill="#605247")
for name in ("house","town","mine","farm","mill","factory"):
    im,d=canvas()
    if name=="house":
        house(d,8,9,12,12)
        d.ellipse((23,16,28,24),fill="#3a693c")
    elif name=="town":
        d.rectangle((2,4,30,28),fill="#a29377")
        d.line((3,18,30,18),fill="#ddd4b7")
        house(d,4,4,9,10); house(d,18,8,10,9,"#8d5550");house(d,7,19,13,9,"#486278")
        d.rectangle((23,21,27,26),fill="#7a9a5b")
    elif name=="mine":
        d.polygon([(2,25),(4,16),(11,9),(17,12),(22,8),(30,26)],fill="#5a5b5e")
        d.polygon([(10,24),(10,19),(14,15),(18,15),(22,19),(22,24)],fill="#272934")
        d.line((13,24,9,30),fill="#bcad93",width=2);d.line((18,24,22,30),fill="#bcad93",width=2)
    elif name=="farm":
        d.rectangle((1,3,29,28),fill="#8c693f")
        for i in range(4,29,4):d.line((i,4,i,26),fill="#dbb865",width=2)
        house(d,14,5,12,10,"#903d38")
    else:
        d.rectangle((3,12,29,27),fill="#a5806e" if name=="factory" else "#849298")
        d.rectangle((3,12,29,16),fill="#465661")
        for i in range(6,27,5):d.rectangle((i,20,i+2,24),fill="#eecc80")
        d.rectangle((8,4,11,15),fill="#704e42")
        d.rectangle((20,1,23,13),fill="#725549")
    save(im,name)
for mode in ("rail","road"):
    for mask in range(16):
        im,d=canvas()
        if mode=="road":
            save(road_raster(mask),mode+str(mask))
            continue
        stroke="#ae997e"
        d.rectangle((12,12,19,19),fill=stroke)
        for i,(x,y) in enumerate(((16,0),(31,16),(16,31),(0,16))):
            if not mask & 1<<i:continue
            d.line((16,16,x,y),fill=stroke,width=8)
            if mode=="rail":
                if x==16:
                    for a in range(min(y,16),max(y,16)+1,4): d.line((12,a,20,a),fill="#544235")
                    for a in (14,18):d.line((a,16,a,y),fill="#e1dfc4")
                else:
                    for a in range(min(x,16),max(x,16)+1,4): d.line((a,12,a,20),fill="#544235")
                    for a in (14,18):d.line((16,a,x,a),fill="#e1dfc4")
            else:
                for a in range(0,16,6):
                    xx=round(16+(x-16)*a/16);yy=round(16+(y-16)*a/16)
                    d.line((xx,yy,xx+(x-16)//15,yy+(y-16)//15),fill="#f6dd97")
        save(im,mode+str(mask))
for name in ("rail_station","road_station","dock","airport","bridge","tunnel","signal","closed","canal",
             "sel","anchor","coverage","railv","roadv","waterv","airv"):
    im,d=canvas()
    if name in ("rail_station","road_station","dock","airport"):
        color={"rail_station":"#d4814a","road_station":"#e1b450","dock":"#5ccbc5","airport":"#9fa6ef"}[name]
        d.rounded_rectangle((5,6,26,24),radius=2,fill="#182636",outline=color,width=2)
        if name=="airport":
            d.line((15,9,15,20),fill=color,width=2);d.line((10,15,20,15),fill=color,width=2);d.line((12,20,18,20),fill=color)
        elif name=="dock":
            d.line((8,20,23,20),fill=color,width=2)
            d.polygon([(10,15),(23,15),(20,19),(13,19)],fill=color)
        elif name=="rail_station":
            d.rounded_rectangle((11,9,21,20),radius=2,fill=color)
            d.rectangle((13,11,19,14),fill="#182636");d.point((13,18),fill="white");d.point((19,18),fill="white")
        else:
            d.rounded_rectangle((9,10,23,19),radius=2,fill=color)
            d.rectangle((11,11,20,14),fill="#182636");d.ellipse((11,17,14,21),fill="#182636");d.ellipse((19,17,22,21),fill="#182636")
    elif name=="bridge":
        d.rectangle((3,3,28,28),outline="#d7b28b",width=2)
    elif name=="tunnel":
        d.arc((4,2,27,27),180,360,fill="#e1cc99",width=2)
    elif name in ("signal","closed"):
        d.rectangle((23,4,27,15),fill="#202b38")
        d.ellipse((23,4,27,8),fill="#ee5a51" if name=="closed" else "#bce95a")
    elif name=="canal":
        d.rectangle((2,2,29,29),fill="#397d9b",outline="#5da1a9",width=2)
        d.line((7,12,15,12),fill="#70aeb3");d.line((17,20,26,20),fill="#70aeb3")
    elif name in ("sel","anchor","coverage"):
        color={"sel":"#fff09b","anchor":"#ff975b","coverage":"#a6cba4"}[name]
        d.rectangle((0,0,31,31),outline=color,width=2 if name!="coverage" else 1)
    else:
        color={"railv":"#f19c58","roadv":"#ffdd69","waterv":"#61e8e3","airv":"#c8b5ff"}[name]
        d.rounded_rectangle((17,16,30,29),radius=2,fill="#0c1721",outline=color)
        if name=="airv":
            d.line((23,19,23,26),fill=color,width=2);d.line((19,23,28,23),fill=color)
        elif name=="waterv":
            d.polygon([(19,22),(28,22),(25,26),(21,26)],fill=color)
        else:
            d.rectangle((20,20,27,25),fill=color);d.point((21,24),fill="#4c4441");d.point((26,24),fill="#4c4441")
    save(im,name)
for name,color in {"panel":"#101c2b","frame":"#18293b","paper":"#152537","fog":"#6e7d94"}.items():
    save(canvas(color)[0],name)
for name,fill,edge in (
    ("button","#314758","#587389"),
    ("button_active","#3d6865","#80aaa0"),
    ("button_primary","#c9a25e","#f4d18a"),
    ("button_hover","#4e6a7e","#96b0bc"),
):
    im,d=canvas()
    d.rounded_rectangle((0,0,31,31),radius=4,fill=fill,outline=edge)
    save(im,name)
for v in range(4):
    im,d=canvas()
    def tree(x,y,shade):
        d.rectangle((x+3,y+9,x+5,y+14),fill="#523f31")
        d.ellipse((x,y,x+9,y+11),fill=shade)
        d.line((x+3,y+2,x+6,y+2),fill="#74994d")
    tree(5+v,5,"#355b3d");tree(15,11-v,"#436b43");tree(8,14,"#466a45")
    save(im,"wood"+str(v))
for name,symbol in (("road","R"),("rail","T"),("stop","B"),("station","S"),("tools","+"),("company","C"),("map","M")):
    img,d=canvas()
    d.rounded_rectangle((1,1,30,30),radius=5,fill="#22394b",outline="#8ca6a9",width=2)
    if name in ("road","rail","stop","station"):
        icon={"road":"road10","rail":"rail10","stop":"road_station","station":"rail_station"}[name]
        img.alpha_composite(Image.open(OUT / f"bl_{icon}.png"))
    else:
        d.rounded_rectangle((7,7,24,24),radius=3,outline="#efc777")
        d.text((13,10),symbol,fill="#f5e3a7")
    save(img,"hot_"+name)
# This texture is used by Blender-built meshes, with one UV swatch per colour.
vehicle_colors=("22656a","e7d29f","283b48","282d35","1c3540","a7b3ae","ffe4ab","9e352f","aa6947")
im=Image.new("RGBA",(128,16),"#ffffff")
d=ImageDraw.Draw(im)
for i,hexcolor in enumerate(vehicle_colors):d.rectangle((8*i,0,8*i+7,15),fill="#"+hexcolor)
save(im,"vehicle_palette")


im,d=canvas("#c19168")
for y in (3,15,28):d.line((0,y,31,y),fill="#865e4c")
for z in (6,20):
    for x in (4,20):
        d.rectangle((x,z,x+7,z+6),fill="#415361",outline="#e2bf85")
save(im,"house_wall")

for mode in ("road","rail"):
    for mask in range(16):
        for kind,base in (("plain","grass0"),("bridge","water0")):
            sheet=Image.open(OUT / f"bl_{base}.png").convert("RGBA")
            overlay=Image.open(OUT / f"bl_{mode}{mask}.png")
            # Luanti's default +Y UV origin is at the +Z edge. The schematic
            # texture uses north at -Z. Flip the entire connectivity layer.
            overlay=overlay.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            sheet.alpha_composite(overlay)
            if kind != "plain":sheet.alpha_composite(Image.open(OUT / f"bl_{kind}.png"))
            for q in range(4):
                x,y=(q%2)*16,(q//2)*16
                save(sheet.crop((x,y,x+16,y+16)),f"{mode}_{mask}_{kind}_q{q}")

write_tunnels(OUT)

for tag, color in (("ok","#8ef1bb"),("no","#ff816e")):
    im,d=canvas()
    d.polygon([(16,4),(28,16),(16,28),(4,16)],fill="#193038")
    d.line([(16,4),(28,16),(16,28),(4,16),(16,4)],fill=color,width=3)
    save(im,"preview_"+tag)
