#!/usr/bin/env python3
"""Generate a small original, soft-edged breakdown puff for Luanti."""
from math import exp
from pathlib import Path
from PIL import Image

p = Path(__file__).resolve().parents[1]
out = Image.new("RGBA", (48, 48))
# Asymmetric lobes read as smoke rather than uniform translucent discs.
lobes = [(-.12, -.05, .40, 1.00),(-.39,-.22,.24,.50),(.32,.07,.32,.61),
         (-.18,.34,.30,.48),(.30,-.34,.23,.36)]
for y in range(48):
    for x in range(48):
        xx, yy = (x-23.5)/22, (y-23.5)/22
        dens = sum(a*exp(-((xx-cx)**2+(yy-cy)**2)/(2*r*r)) for cx,cy,r,a in lobes)
        alpha = round(min(164,max(0,(dens-.17)*142)))
        shade = round(48 + 16*max(0,1-dens))
        out.putpixel((x,y),(shade,shade,shade+3,alpha))
out.save(p / "mods/luanttd_core/textures/bl_road_breakdown_smoke.png",optimize=True)
