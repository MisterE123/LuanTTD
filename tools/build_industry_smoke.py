"""Original feathered smoke billboard, independent of gameplay RNG."""
from math import exp, hypot, sin
from pathlib import Path
from PIL import Image

im = Image.new("RGBA", (48, 48))
lobes = [(-.25, -.21, .47, .6), (.29, -.21, .39, .62), (.21, .33, .41, .67),
         (-.35, .29, .46, .57), (.08, -.46, .34, .61), (-.10, .00, .55, 1)]
for y in range(48):
    for x in range(48):
        u,v=(x-23.5)/23,(y-23.5)/23
        envelope=max(0,1-(hypot(u,v)/.97)**2)**1.30
        density=min(1.2,sum(a*exp(-2.3*((u-h)**2+(v-k)**2)/r**2) for h,k,r,a in lobes))
        grain=sin(x*2.56+y*1.97)*.10+sin(x*.56-y*.94)*.06
        intensity=round(198+min(1,density)*29+grain*23)
        alpha=round(200*envelope*density*(1+grain))
        im.putpixel((x,y),(intensity,intensity,intensity,alpha))
im.save(Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures/bl_industry_smoke.png",optimize=True)
