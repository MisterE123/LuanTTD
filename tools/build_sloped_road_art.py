#!/usr/bin/env python3
"""Make one top texture per road mask and regenerate the retaining-wall tile.

Requires Pillow. OBJ contract: north (-Z) at image top, east (+X) right.
The original flat road map tiles use inverted V and are composed in
engine orientation. Convert the grass too, not just its road layer, so
the ramp tops match the flat road tile raster exactly in world space.
"""
from pathlib import Path
from random import Random

from PIL import Image, ImageDraw

TEXTURES = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
SIZE = 32
FLIP_V = Image.Transpose.FLIP_TOP_BOTTOM
ASPHALT = (79, 82, 85)
SHOULDER = (154, 147, 126)
STRIPE = (239, 227, 182)


def input_texture(name):
    with Image.open(TEXTURES/f"bl_{name}.png") as image:
        return image.convert("RGBA")


def road_surface(mask):
    img = input_texture("grass0").transpose(FLIP_V)
    img.alpha_composite(input_texture(f"road{mask}"))
    return img.convert("RGB")


def tiled_wall():
    """Coursed limewashed rubble, with wrapped blocks at left/right edges."""
    rng = Random(2183)
    img = Image.new("RGB", (SIZE, SIZE), (83, 82, 71))
    draw = ImageDraw.Draw(img)
    # Common mortar across the top/bottom repeat; stagger each course.
    for y, offset in ((1, -6), (7, -2), (13, -9), (19, -5), (25, -1)):
        x = offset
        while x < SIZE:
            span = rng.randint(6, 11)
            tone = rng.choice(((123, 120, 103), (132, 131, 120), (146, 139, 117),
                               (116, 111, 99), (156, 145, 119), (134, 128, 113)))
            if x+span > SIZE:
                span = SIZE-x
            if span >= 2:
                block = (x, y, x+span-2, y+4)
                draw.rectangle(block, fill=tone)
                draw.line((x+1,y,x+span-2,y), fill=tuple(min(255,v+15) for v in tone))
                draw.line((x+1,y+4,x+span-2,y+4), fill=tuple(v-12 for v in tone))
                for _ in range(span//3):
                    xx, yy = rng.randint(x,x+span-2), rng.randint(y+1,y+3)
                    draw.point((xx,yy), fill=tuple(v+rng.choice((-7,6)) for v in tone))
            x += span
    # Border columns reuse the same mortar/color strip to avoid a bright texture
    # seam when a long retaining wall is wrapped over neighboring tiles.
    for y in range(SIZE):
        img.putpixel((0,y),img.getpixel((SIZE-1,y)))
    return img


def flat_world_raster(mask):
    """Reassemble the committed Luanti quadrant images in world orientation."""
    out = Image.new("RGB", (SIZE,SIZE))
    for q in range(4):
        source=input_texture(f"road_{mask}_plain_q{q}").convert("RGB")
        out.paste(source, ((q%2)*16,(q//2)*16))
    return out.transpose(FLIP_V)


def world_edge(img,direction):
    if direction==1:
        return [img.getpixel((i,0)) for i in range(SIZE)]
    if direction==2:
        return [img.getpixel((SIZE-1,i)) for i in range(SIZE)]
    if direction==4:
        return [img.getpixel((i,SIZE-1)) for i in range(SIZE)]
    return [img.getpixel((0,i)) for i in range(SIZE)]


def test(surfaces):
    def asphalt_profile(edge):
        return [px if px in (ASPHALT,SHOULDER,STRIPE) else None for px in edge]
    joined = [None]*10+[SHOULDER]+[ASPHALT]*10+[SHOULDER]+[None]*10
    opposite={1:4,2:8,4:1,8:2}
    joints=0
    for mask,top in enumerate(surfaces):
        assert top.mode=="RGB" and top.size==(SIZE,SIZE)
        existing=flat_world_raster(mask)
        assert top.tobytes()==existing.tobytes(), f"road mask {mask}: raster mismatch with flat road"
        for direction,other in opposite.items():
            actual = asphalt_profile(world_edge(top,direction))
            assert actual == (joined if mask&direction else [None]*SIZE), (mask,direction,actual)
            for neighbor in range(16):
                if bool(mask&direction)==bool(neighbor&other):
                    adjacent=asphalt_profile(world_edge(surfaces[neighbor],other))
                    assert actual==adjacent, (mask,direction,neighbor)
                    joints+=1
    print(f"PASS: 16 native road rasters; {joints} compatible paired edges match asphalt, shoulders and stripe phase")


def main():
    surfaces=[road_surface(mask) for mask in range(16)]
    # Check first; leave existing exports alone if upstream flat roads changed.
    test(surfaces)
    for mask,img in enumerate(surfaces):
        img.save(TEXTURES/f"bl_road_surface_{mask}.png",optimize=True)
    tiled_wall().save(TEXTURES/"bl_road_surface_retaining.png",optimize=True)


if __name__=="__main__":
    main()
