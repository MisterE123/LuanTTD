#!/usr/bin/env python3
"""Write original, deterministic Luanti demolition particle textures."""
from argparse import ArgumentParser
from io import BytesIO
from math import hypot
from pathlib import Path
from PIL import Image

SIZE = 32
ROOT = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
DUST = ((-.22,-.2,.60,.51,.76),(.27,-.17,.60,.51,.67),
        (-.11,.29,.70,.51,.72),(.22,.39,.49,.45,.61),
        (-.52,.06,.38,.40,.52),(.54,.16,.42,.52,.54))

def sample(kind, x, y):
    if kind == "flare":
        d = hypot(x, y)
        core = max(0,1-d/.67)
        ring = max(0,1-abs(d-.45)/.33)
        alpha = int(min(255, 292*core**1.4 + 90*ring**1.8))
        return 255, int(143+112*core), int(64+164*core), alpha
    if kind == "dust":
        light = 1.
        for cx, cy, rx, ry, opacity in DUST:
            d = hypot((x-cx)/rx,(y-cy)/ry)
            light *= 1-opacity*max(0,1-d)**.82
        a = int((1-light)*195)
        return 198 + a//12, 166 + a//10, 134 + a//11, a
    # Chips are angular instead of perfectly radial sprite dots.
    p = abs(x+.36*y)+abs(y-.23*x)
    alpha = int(255*max(0,min(1,(.79-p)*7.)))
    return 196 - int(y*36), 132 - int(y*29), 86 - int(y*19), alpha

def images():
    for kind in ("flare", "dust", "chips"):
        im=Image.new("RGBA",(SIZE,SIZE))
        for y in range(SIZE):
            for x in range(SIZE):
                im.putpixel((x,y),sample(kind, (x+.5)/16-1,(y+.5)/16-1))
        out=BytesIO()
        im.save(out,format="PNG",optimize=True)
        yield ROOT/f"bl_demolition_{kind}.png",out.getvalue()

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--check",action="store_true")
    check=p.parse_args().check
    for f,data in images():
        if check:
            assert f.read_bytes()==data,f
        else:
            t=f.with_suffix(".tmp")
            t.write_bytes(data)
            t.replace(f)
