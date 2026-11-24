#!/usr/bin/env python3
"""Original compact RC1 bare/young grass textures, keeping the game's pixel scale."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
from random import Random
from PIL import Image

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"

def generate():
    old = Image.open(root/"bl_grass0.png").convert("RGB")
    width,height = old.size
    random=Random(0xC1EA)
    specks=[random.random() for _ in range(width*height)]
    for density,cover in enumerate((0,.23,.54)):
        frame=Image.new("RGB",(width,height))
        for y in range(height):
            for x in range(width):
                g=old.getpixel((x,y))
                index=x+y*width
                mixed=.87 if specks[index]<cover else (.10*density if cover>0 else 0)
                noise=min(1,max(0,((g[1]-65)/98+.25*(specks[index]-.5))))
                soil=tuple(round(a+(b-a)*noise) for a,b in zip((93,73,52),(145,123,86)))
                frame.putpixel((x,y),tuple(round(v+(w-v)*mixed) for v,w in zip(soil,g)))
        out=BytesIO()
        frame.save(out,format="PNG",optimize=True)
        yield root/f"bl_clear_grass_{density}.png",out.getvalue()

if __name__=="__main__":
    p=ArgumentParser(description=__doc__)
    p.add_argument("--check",action="store_true")
    check=p.parse_args().check
    for path,data in generate():
        if check:
            assert path.read_bytes()==data,path
        else:
            temp=path.with_suffix(".tmp")
            temp.write_bytes(data)
            temp.replace(path)
