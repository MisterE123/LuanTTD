#!/usr/bin/env python3
"""Generate the 46 nonempty RC1 dike layouts as native 2-node tile meshes."""
import argparse
from io import StringIO
from pathlib import Path
import random
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/luanttd_core"


def masks():
    # Cardinal then diagonal wetness, in DrawWaterEdges order.
    for wet in range(256):
        side = [bool(wet & (1 << i)) for i in range(4)]
        mask = 15 - (wet & 15)
        for i, a in enumerate(side):
            b = side[(i + 1) % 4]
            if not a and not b:
                mask |= 16 << i
            elif a and b and not wet & (16 << i):
                mask |= 256 << i
        yield mask


def mesh(mask):
    out = StringIO()
    out.write("# Dressed limestone in OpenTTD 16.0-RC1 water edge layout.\n")
    index = 1
    wet = [not bool(mask & (1 << i)) for i in range(4)]

    def face(vertices, uvs):
        nonlocal index
        # Luanti reflects OBJ X. Compensate here and reverse winding.
        for x, y, z in vertices:
            out.write(f"v {-x:.4f} {y:.4f} {z-1:.4f}\n")
        for u, v in uvs:
            out.write(f"vt {u:.4f} {v:.4f}\n")
        for j in range(1, len(vertices)-1):
            out.write(f"f {index}/{index} {index+j+1}/{index+j+1} {index+j}/{index+j}\n")
        index += len(vertices)

    def transform(x, y, z, turn):
        for _ in range(turn):
            x, z = z, 1-x
        return x, y, z

    def prism(profile, start, end, turn, caps=(True, True)):
        # CCW (x,y) profile. Side panels have dressing courses and
        # copings sample the top quarter of the material atlas.
        shape = [(x, y, z) for z in (start, end) for x, y in profile]
        def f(indices, uv):
            face([transform(*shape[i], turn) for i in indices], uv)
        n = len(profile)
        if caps[0]:
            f(list(range(n-1, -1, -1)), [(.25+(x-profile[0][0]), .05+(y+.73)) for x,y in reversed(profile)])
        if caps[1]:
            f(list(range(n, 2*n)), [(.25+(x-profile[0][0]), .05+(y+.73)) for x,y in profile])
        for i, (x,y) in enumerate(profile):
            j = (i+1)%n
            u0,u1=(start+.5)/2,(end+.5)/2
            if y>=-.355 and profile[j][1]>=-.355:
                v0,v1=.83,.98
            else:
                v0,v1=.04+(y+.73)*1.38,.04+(profile[j][1]+.73)*1.38
            f([i,j,j+n,i+n], [(u0,v0),(u0,v1),(u1,v1),(u1,v0)])

    wall=[(-.500,-.74),(-.340,-.74),(-.340,-.385),(-.365,-.348),(-.476,-.348),(-.500,-.377)]
    for i in range(4):
        if wet[i]:
            continue
        # Corner blocks replace both adjoining wall ends rather than
        # overlapping them. Straight opposite tiles do not have end caps.
        before=bool(mask & (16<<((i+3)%4)))
        after=bool(mask & (16<<i))
        prism(wall, -.34 if before else -.5, 1.34 if after else 1.5, i, (not before,not after))
    block=[(-.500,-.74),(-.340,-.74),(-.340,-.376),(-.363,-.340),(-.478,-.340),(-.500,-.371)]
    for i in range(4):
        if mask & (16<<i):
            # Convex corner blocks have top break and are full height.
            prism(block,1.34,1.5,i)
        if mask & (256<<i):
            # A dry diagonal needs only a compact nib inside the water square.
            inner=[(-.500,-.727),(-.389,-.727),(-.389,-.40),(-.447,-.356),(-.500,-.356)]
            prism(inner,1.385,1.5,i)
    return out.getvalue()


def texture():
    rnd=random.Random(1601)
    im=Image.new("RGB",(128,128))
    draw=ImageDraw.Draw(im)
    for row in range(6):
        h=16
        for col in range(-1,7):
            x=col*24+(row%2)*12
            level=rnd.randrange(-12,16)
            color=tuple(x+level for x in (139,130,111))
            y=row*h+32
            draw.rectangle((x,y,x+23,y+h-1),fill=(105,102,90))
            draw.rectangle((x+1,y+1,x+22,y+h-2),fill=color)
            draw.line((x+1,y+1,x+22,y+1),fill=tuple(min(255,v+22) for v in color))
            draw.line((x+2,y+h-2,x+22,y+h-2),fill=tuple(v-13 for v in color))
    for x in range(128):
        level=rnd.randrange(-5,6)
        draw.line((x,0,x,31),fill=(163+level,151+level,129+level))
        if x%32==0: draw.line((x,0,x,31),fill=(113,110,98))
    for y in range(128):
        for x in range(128):
            level=rnd.choice((-4,-2,0,0,2,4))
            im.putpixel((x,y),tuple(v+level for v in im.getpixel((x,y))))
    from io import BytesIO
    out=BytesIO()
    im.save(out,format="PNG")
    return out.getvalue()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    assets=sorted(set(masks())-{0})
    assert len(assets)==46
    entries={MOD/"models"/f"bl_canal_dike_{m}.obj":mesh(m).encode() for m in assets}
    entries[MOD/"textures/bl_canal_dike_limestone.png"]=texture()
    for path, value in entries.items():
        if args.check:
            assert path.read_bytes()==value, path
        else:
            path.write_bytes(value)
    print("46 stock RC1 canal side/corner meshes and limestone atlas")


if __name__=="__main__":
    main()
