#!/usr/bin/env python3
"""Original company-owned land stake, icon, and bare ground."""
from argparse import ArgumentParser
from pathlib import Path
from PIL import Image, ImageDraw

p=ArgumentParser(description=__doc__)
p.add_argument("--check",action="store_true")
check=p.parse_args().check
root=Path(__file__).resolve().parents[1]/"mods/luanttd_core"
colors=[(82,68,56),(146,128,92),(208,209,179),(112,164,189),(32,45,51)]
def png(im,name):
    path=root/"textures"/f"bl_{name}.png"
    if check: assert Image.open(path).convert(im.mode).tobytes()==im.tobytes(),path
    else: im.save(path,optimize=True)
pal=Image.new("RGB",(40,16))
for i,c in enumerate(colors): pal.paste(c,(8*i,0,8*(i+1),16))
png(pal,"owned_land_atlas")
sand=Image.new("RGB",(32,32))
for z in range(32):
    for x in range(32):
        n=((x*97+z*23)^(x*13+z*41))%25
        sand.putpixel((x,z),(124+n,106+n,78+n))
png(sand,"owned_land_ground")
icon=Image.new("RGBA",(48*4,48*4))
d=ImageDraw.Draw(icon)
def poly(pts,c): d.polygon([(x*4,y*4) for x,y in pts],c)
poly([(5,34),(25,26),(44,33),(24,44)],"#7d6845")
poly([(5,31),(25,23),(44,30),(24,40)],"#bba174")
poly([(20,14),(24,14),(24,35),(21,35)],"#695438")
poly([(14,11),(32,9),(32,22),(14,25)],"#33516b")
poly([(15,12),(31,10),(31,20),(15,23)],"#9fd3ee")
poly([(23,13),(26,13),(26,16),(29,16),(29,18),(26,19),(26,21),(23,21),(23,19),(20,19),(20,17),(23,17)],"#3e6d80")
png(icon.resize((48,48),Image.Resampling.LANCZOS),"dispatch_buy_land")
for lift in range(3):
    y=-1.5+lift/2
    out=["# Original land purchase stake; tools/build_owned_land_art.py","o Owned_land"]
    for i in range(5):out.append(f"vt {(i+.5)/5:.6f} .5")
    def box(x0,z0,bottom,x1,z1,top,parts):
        points=[(x0,bottom,z0),(x1,bottom,z0),(x1,bottom,z1),(x0,bottom,z1),
                (x0,top,z0),(x1,top,z0),(x1,top,z1),(x0,top,z1)]
        a=sum(l.startswith("v ") for l in out)+1
        out.extend(f"v {-x:.6f} {h:.6f} {z:.6f}" for x,h,z in points)
        for ids,c in zip([(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],parts):
            out.append("f "+" ".join(f"{a+i}/{c+1}" for i in ids))
    box(.455,.45,y-.035,.545,.55,y+.71,[0,1,1,0,1,0])
    box(.31,.465,y+.48,.69,.535,y+.685,[2,2,3,2,3,2])
    box(.365,.451,y+.565,.635,.548,y+.59,[4,4,4,4,4,4])
    path=root/"models"/f"bl_owned_land_{lift}.obj"
    data="\n".join(out)+"\n"
    if check: assert path.read_text()==data,path
    else:path.write_text(data)
print("PASS original company-plot stake, palette, icon and three founded lifts")
