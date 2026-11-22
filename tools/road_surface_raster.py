"""Original 32px road-bit raster (north=-Z, east=+X, two nodes/tile).

The shared edge profile remains untouched. Only adjacent two-arm bends get
a local fillet, because stock sixteen-sample turning sweeps across the
rectangular inset which used to be grass. No path or width semantics change.

Run as a script to regenerate just the four road-bend art families, then run
build_sloped_road_art.py and build_town_streets.py for their derived palettes.
"""
from math import cos, hypot, pi
from pathlib import Path

from PIL import Image

TEXTURES = Path(__file__).resolve().parents[1] / "mods/bayline/textures"
FLIP = Image.Transpose.FLIP_TOP_BOTTOM
CORNERS = {6: 0, 12: 1, 9: 2, 3: 3}  # clockwise rotations of +X/+Z
DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))
ASPHALT = (79, 82, 85, 255)
GRAVEL = (154, 147, 126, 255)
STRIPE = (239, 227, 182, 255)
CLEAR = (0, 0, 0, 0)


def straight_pixel(mask, x, z):
    a, b = x - 15.5, z - 15.5
    shoulders = abs(a) < 6 and abs(b) < 6
    asphalt = abs(a) < 5 and abs(b) < 5
    dash = False
    for i, (dx, dz) in enumerate(DIRS):
        if not mask & (1 << i):
            continue
        along, cross = a * dx + b * dz, abs(a * dz - b * dx)
        if along >= 0:
            shoulders |= cross < 6
            asphalt |= cross < 5
            dash |= cross < 1 and (6.5 <= along <= 8.5 or 12.5 <= along <= 13.5)
    return STRIPE if dash else ASPHALT if asphalt else GRAVEL if shoulders else CLEAR


def rotate(x, z, q):
    return ((x, z), (31-z, x), (31-x, 31-z), (z, 31-x))[q % 4]


def connector(x, z):
    """Two immutable rows keep the final straight profile at every mouth."""
    return min(x, z, 31-x, 31-z) < 2


def flare(along):
    # Local S-roll on the outside gives the rear/front wheel on the wide swing
    # a real dark base (not a one-pixel fragment of white shoulder).
    d = abs(along-6.5)
    return 2.45*cos(pi*d/16)**2 if d < 8 else 0.


def corner_asphalt(x, z):
    """Canonical +X/+Z corner. Coordinates are raster texel centers."""
    if connector(x, z):
        return straight_pixel(6, x, z) in (ASPHALT, STRIPE)
    a, b = x-15.5, z-15.5
    if straight_pixel(6, x, z) in (ASPHALT, STRIPE):
        # Clip just the dead square outside tip to let the verge turn
        # around it. This area is disjoint from the stock sweep.
        return not (a < -3 and b < -3 and hypot(a+1.05, b+1.05) > 4.65)
    if a >= 5 and b >= 5:
        # Concave fillet under the stock inside wheel. Nine texels of
        # reach along the verge but only a four-texel gain at the diagonal.
        # Curve side tapers to the unchanged straight edge in two texels.
        return x+z <= 50
    return (a >= -1 and b < 0 and -b < 5+flare(a)) or (
            b >= -1 and a < 0 and -a < 5+flare(b))


def corner_stripe(x, z):
    a, b = x-15.5, z-15.5
    if max(a, b) >= 6.5:
        # Keep the approach dashes rectangular and exactly in phase with
        # the adjoining straight. Don't draw cropped T-shaped tangent ends.
        return straight_pixel(6, x, z) == STRIPE
    # A compact 45° dash visually follows the curve around the centre.
    # The bound is slightly oval along the diagonal, not a cross or corner.
    return 3.25 <= a+b <= 5.75 and abs(a-b) <= 2


def corner_seed():
    image=Image.new("RGBA", (32,32))
    for z in range(32):
        for x in range(32):
            if connector(x, z):
                color=straight_pixel(6, x, z)
            elif corner_asphalt(x, z):
                color=STRIPE if corner_stripe(x, z) else ASPHALT
            elif any(corner_asphalt(x+i,z+j) for i,j in ((-1,0),(1,0),(0,-1),(0,1))):
                color=GRAVEL
            else:
                color=CLEAR
            image.putpixel((x,z),color)
    return image


def road_raster(mask):
    if mask not in CORNERS:
        image=Image.new("RGBA",(32,32))
        image.putdata([straight_pixel(mask,x,z) for z in range(32) for x in range(32)])
        return image
    seed=corner_seed()
    image=Image.new("RGBA",(32,32))
    for z in range(32):
        for x in range(32):
            image.putpixel(rotate(x,z,CORNERS[mask]),seed.getpixel((x,z)))
    return image


def write_corner_families():
    from terrain_rock_raster import write_tunnels
    for mask in CORNERS:
        road=road_raster(mask)
        road.save(TEXTURES/f"bl_road{mask}.png",optimize=True)
        for kind,base in (("plain","grass0"), ("bridge","water0")):
            with Image.open(TEXTURES/f"bl_{base}.png") as ground:
                sheet=ground.convert("RGBA")
            sheet.alpha_composite(road.transpose(FLIP))
            if kind != "plain":
                with Image.open(TEXTURES/f"bl_{kind}.png") as object_sheet:
                    sheet.alpha_composite(object_sheet.convert("RGBA"))
            for q in range(4):
                x,z=(q%2)*16,(q//2)*16
                sheet.crop((x,z,x+16,z+16)).save(
                    TEXTURES/f"bl_road_{mask}_{kind}_q{q}.png",optimize=True)

    write_tunnels(TEXTURES)


if __name__ == "__main__":
    write_corner_families()
