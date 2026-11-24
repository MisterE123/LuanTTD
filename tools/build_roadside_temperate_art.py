#!/usr/bin/env python3
"""Original Temperate road frontage, from stock tile positions (no sprite art)."""
from argparse import ArgumentParser
from pathlib import Path
from math import cos, sin, pi, hypot
import re
from PIL import Image

root = Path(__file__).resolve().parents[1]
m = root / "mods/luanttd_core"
model, tex = m / "models", m / "textures"
raw = (m / "openttd/roadside_details.lua").read_text()
colors = [(67, 65, 57), (60, 65, 62), (81, 86, 81), (155, 157, 133), (249, 224, 151),
          (84, 62, 43), (69, 119, 60), (101, 149, 70), (53, 93, 54), (128, 160, 84),
          (158, 151, 127), (95, 93, 76)]
p = ArgumentParser(description=__doc__)
p.add_argument("--check", action="store_true")
check = p.parse_args().check


def save(image, name):
    target = tex / f"bl_{name}.png"
    if check:
        stored = Image.open(target).convert(image.mode)
        assert stored.size == image.size and stored.tobytes() == image.tobytes(), target
    else:
        image.save(target, optimize=True)


class Mesh:
    def __init__(self, name):
        self.name = name
        self.out = ["# Original LuanTTD Temperate road decoration", "o " + name]
        self.n = 0
        for i in range(len(colors)):
            self.out.append(f"vt {(i + .5)/len(colors):.6f} .5")

    def face(self, points, c):
        start = self.n + 1
        for x, y, z in points:
            self.out.append(f"v {-x:.5f} {y:.5f} {z:.5f}")
            self.n += 1
        self.out.append("f " + " ".join(f"{i}/{c+1}" for i in range(start, self.n+1)))

    def rod(self, a, b, r1, r2, color, sides=8):
        dx, dy, dz = (b[i]-a[i] for i in range(3))
        length = (dx*dx+dy*dy+dz*dz)**.5
        ux, uy, uz = dx/length, dy/length, dz/length
        v = (-uz, 0, ux) if abs(uy) < .9 else (0, -uz, uy)
        norm = sum(x*x for x in v)**.5
        v = tuple(x/norm for x in v)
        w = (uy*v[2]-uz*v[1], uz*v[0]-ux*v[2], ux*v[1]-uy*v[0])
        rim = [tuple(v[j]*cos(2*pi*i/sides)+w[j]*sin(2*pi*i/sides) for j in range(3))
               for i in range(sides)]
        near = [tuple(c+r1*d for c,d in zip(a,v)) for v in rim]
        far = [tuple(c+r2*d for c,d in zip(b,v)) for v in rim]
        self.face(list(reversed(near)), color)
        self.face(far, color)
        for i in range(sides):
            j=(i+1)%sides
            self.face([near[i],near[j],far[j],far[i]],color)

    def tree(self, x, y, z, seed):
        self.rod((x,y+.006,z),(x,y+.42,z),.035,.016,5,7)
        self.rod((x,y+.012,z),(x,y+.047,z),.116,.11,10,9)
        for i,(a,b,c,size) in enumerate([(0,.44,0,.164),(.087,.55,.045,.149),
               (-.073,.61,.03,.132),(.012,.71,-.016,.114),(-.017,.54,-.088,.131)]):
            angle=(seed%8)*pi/4
            xx, zz=x+a*cos(angle)+c*sin(angle),z-a*sin(angle)+c*cos(angle)
            self.rod((xx,y+b-size*.45,zz),(xx,y+b+size*.65,zz),size,size*.55,6+(seed+i)%4,7)

    def lamp(self,x,y,z,flip):
        dx,dz=-.5-x,-.5-z  # grid centre, relative to the +X/+Z anchor
        d=hypot(dx,dz)
        ux,uz=dx/d,dz/d
        self.rod((x,y+.006,z),(x,y+.043,z),.071,.061,0,9)
        self.rod((x,y+.035,z),(x,y+.87,z),.025,.015,1,8)
        at = (x+ux*.125,y+.99,z+uz*.125)
        end = (x+ux*.268,y+1.006,z+uz*.268)
        self.rod((x,y+.85,z),at,.017,.014,2)
        self.rod(at,end,.015,.013,2)
        a=(end[0],end[1]-.064,end[2])
        b=(end[0],end[1]+.005,end[2])
        self.rod(a,b,.057,.065,3,8)
        self.rod((a[0],a[1]-.013,a[2]),a,.046,.047,4,8)

    def write(self):
        path = model / f"bl_{self.name}.obj"
        text = "\n".join(self.out)+"\n"
        if check:
            assert path.read_text() == text, path
        else:
            path.write_text(text)


palette = Image.new("RGB",(12*8,16))
for i,c in enumerate(colors):
    palette.paste(c,(i*8,0,(i+1)*8,16))
save(palette,"roadside_temperate_atlas")
count = 0
for state in ("street_lights","trees"):
    group = re.search(rf"D\.{state}=\{{(.*?)\n\}}",raw,re.S)[1]
    for n,pts in re.findall(r"\[(\d+)\]=\{(.*?)\},(?:\n|$)",group):
        n=int(n)
        points=[tuple(int(x) for x in trip) for trip in re.findall(r"\{(\d+),(\d+),(\d+)\}",pts)]
        grades = {5:(0,6,9),10:(0,3,12)}.get(n,(0,))
        for grade in grades:
            mesh=Mesh(f"roadside_{state}_{n}_{grade}")
            for i,(x,z,facing) in enumerate(points):
                v={0:0,3:x/16,12:1-x/16,6:z/16,9:1-z/16}[grade]
                xx,zz=x/8-1.5,z/8-1.5
                if state=="trees":
                    mesh.tree(xx,-.5+v,zz,n+i)
                else:
                    mesh.lamp(xx,-.5+v,zz,facing)
            mesh.write()
            count+=1
assert count==28
# Compose stock shoulder states without recolouring any road, shoulder
# or painted striping. These have the same exits as adjacent grass roads.
flat_atlas=Image.new("RGBA",(16*16,16*4))
grade_atlas=Image.new("RGBA",(32*4,32))
for bits in range(16):
    road=Image.open(tex/f"bl_road{bits}.png").convert("RGBA").transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    sheet=Image.new("RGBA",(32,32))
    for z in range(32):
        for x in range(32):
            dust=((x*25+z*11)^(x*3+z*13))%13
            sheet.putpixel((x,z),(128+dust,113+dust,83+dust,255))
    sheet.alpha_composite(road)
    for q in range(4):
        a,b=(q%2)*16,(q//2)*16
        flat_atlas.paste(sheet.crop((a,b,a+16,b+16)),(bits*16,q*16))
    if bits in (5,10):
        origin=0 if bits==5 else 2*32
        grade_atlas.paste(sheet.transpose(Image.Transpose.FLIP_TOP_BOTTOM),(origin,0))
        paved=Image.new("RGBA",(32,32))
        for q in range(4):
            image=Image.open(tex/f"bl_town_street_{bits}_{q}.png").convert("RGBA")
            paved.paste(image,((q%2)*16,(q//2)*16))
        grade_atlas.paste(paved.transpose(Image.Transpose.FLIP_TOP_BOTTOM),(origin+32,0))
save(flat_atlas,"roadside_barren_sheet")
save(grade_atlas,"roadside_grade_sheet")
# The physical work barricades remain identical. The worksite appearance
# variant comes from native stock dry shoulders vs concrete sidewalks.
print(f"PASS original roadside package: {count} model variants and 68 shoulder textures in two atlases")
