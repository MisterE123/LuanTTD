"""Generate an original moon disk (no external image assets)."""
from math import exp, hypot, sqrt
from pathlib import Path
from random import Random

from PIL import Image

from terrain_rock_raster import noise


def moon_raster():
    rand = Random(8711)
    mottling = noise(rand, 10, 10)
    regolith = noise(rand, 28, 26)
    grains = noise(rand, 64, 59)
    maria = [(-.28,-.40,.32,.22),(.19,-.21,.29,.33),
             (-.46,.02,.27,.20),(.34,.20,.22,.20),(-.14,.25,.19,.12)]
    craters = [(-.44,.29,.11),(.37,-.52,.09),(.31,.38,.10),
               (.07,.56,.08),(-.22,-.61,.05),(.58,-.15,.07),
               (-.64,-.14,.07),(.05,.21,.065),(.21,-.02,.08)]
    values = []
    size = 128
    for y in range(size):
        for x in range(size):
            u, v = ((j+.5-size/2)/(size*.44) for j in (x,y))
            radius = hypot(u,v)
            if radius > 1:
                values.append((0,0,0,0))
                continue
            area = mottling(u,v)
            maria_density = min(1.3,sum(exp(-((u-a)/rx)**2-((v-b)/ry)**2)
                                  for a,b,rx,ry in maria)+.22*area)
            crater_contrast = 0
            for a,b,r in craters:
                dx,dy = u-a,v-b
                d=hypot(dx,dy)/r
                crater_contrast += ((7 - 13*(dx+dy)/max(.01,hypot(dx,dy))) *
                                    exp(-((d-.87)/.25)**2) - 13*exp(-2*d*d))
            light=208+31*sqrt(1-radius*radius)-17*(u+v)/2
            intensity=round(light-49*maria_density+12*area+9*regolith(u,v)+
                            5*grains(u,v)+crater_contrast)
            rgb=tuple(max(0,min(255,intensity+shift)) for shift in (4,4,0))
            values.append((*rgb,255))
    im=Image.new("RGBA",(size,size))
    im.putdata(values)
    return im.resize((64,64),Image.Resampling.LANCZOS)


if __name__ == "__main__":
    out=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures/bl_coastal_moon.png"
    moon_raster().save(out,optimize=True)
