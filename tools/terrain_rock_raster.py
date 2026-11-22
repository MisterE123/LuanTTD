"""Original tileable weathered bedrock, generated with Pillow and stdlib only."""
from pathlib import Path
from random import Random
from math import floor, sin, tau

from PIL import Image

SIZE = 128


def mix(a, b, t):
    return a + (b - a) * t


def smooth(t):
    return t * t * (3 - 2 * t)


def noise(rand, columns, rows):
    """Periodic, smoothly interpolated value noise in unit UV coordinates."""
    values = [[rand.uniform(-1, 1) for _ in range(columns)] for _ in range(rows)]

    def sample(u, v):
        x, y = u * columns, v * rows
        ix, iy = floor(x), floor(y)
        sx, sy = smooth(x - ix), smooth(y - iy)
        a, b = ix % columns, (ix + 1) % columns
        top, bottom = values[iy % rows], values[(iy + 1) % rows]
        return mix(mix(top[a], top[b], sx), mix(bottom[a], bottom[b], sx), sy)
    return sample


def rock_surface(seed=25641, bedded=True):
    rand = Random(seed)
    warp_x = noise(rand, 6, 8)
    warp_y = noise(rand, 7, 8)
    bed = noise(rand, 6, 34)
    mineral = noise(rand, 39, 38)
    granular = noise(rand, 73, 66)
    rough = noise(rand, 17, 23)
    stain = noise(rand, 8, 13)

    # Jittered fragments of worn bedding. In addition to changing their size
    # and depth, taper seams so the surface reads as strata, not a stone wall.
    cols, rows = 7, 15
    cells = [[(rand.uniform(.03, .97), rand.uniform(.08, .92),
               rand.uniform(-1, 1), rand.uniform(.35, 1.15))
              for _ in range(cols)] for _ in range(rows)]

    def strata(u, v):
        u *= cols
        v *= rows
        bx, by = floor(u), floor(v)
        best, other, shade, depth = float("inf"), float("inf"), 0, 0
        for j in range(by - 2, by + 3):
            for i in range(bx - 2, bx + 3):
                dx, dy, tint, contrast = cells[j % rows][i % cols]
                d = (u - i - dx) ** 2 + (v - j - dy) ** 2
                if d < best:
                    best, other, shade, depth = d, best, tint, contrast
                elif d < other:
                    other = d
        return shade, depth * max(0, 1 - 6 * (other - best))

    def sample(u, v):
        a = u + .024 * warp_x(u, v)
        # Low-amplitude bedding rises and dips, without a bold repeat stripe.
        b = v + (.046 if bedded else .018) * sin(tau * u) + .028 * warp_y(u, v)
        value, seam = strata(a, b)
        mineral_value = mineral(u, v)
        rock = (123 + (4 if bedded else 1) * bed(a, b) + 4 * value - 9 * seam +
                8 * rough(u, v) + 5 * mineral_value + 3 * granular(u, v))
        weathering = stain(u, v)
        return (round(rock + 1 + 2.3 * weathering),
                round(rock + .2 * weathering),
                round(rock - 3 - 3.5 * weathering))
    return sample


def rasterize(sample, size, colors):
    im = Image.new("RGB", (size, size))
    im.putdata([sample((x + .5) / size, (y + .5) / size)
                for y in range(size) for x in range(size)])
    # No dithering: it would add repeating checker detail to distant terrain.
    return im.quantize(colors=colors, dither=Image.Dither.NONE)


def rock_raster():
    """Native wall UV tile; no alpha, padding, baked light or glyphs."""
    return rasterize(rock_surface(), SIZE, 40)


def hill_raster(variant):
    """Shelf and tunnel earth, with tile variants sharing a continuous edge."""
    shared = rock_surface(874981, bedded=False)
    detail = noise(Random(20568 + variant), 12, 11)

    def sample(u, v):
        blend = smooth(min(1, min(u, v, 1 - u, 1 - v) * 8))
        amount = 9 * blend * detail(u, v)
        shade = max(0, min(7, round((shared(u, v)[1] + amount - 107) / 5)))
        gray = 107 + shade * 5
        return gray + 1, gray, gray - 3


    # Keep compatibility with the 32px road/rail surface compositing pipeline.
    return rasterize(sample, 32, 8)


def clear_raster(rocky):
    """Stock rough is stony turf; stock rocks are mostly exposed slate."""
    rand = Random(3452 if rocky else 7620)
    rock = rock_surface(26476 if rocky else 20783, bedded=False)
    cover = noise(rand, 7, 6)
    detail = noise(rand, 23, 24)
    fine = noise(rand, 47, 41)

    def sample(u, v):
        mineral = rock(u, v)
        vegetation = cover(u, v)
        granular = detail(u, v)
        crumb = fine(u, v)
        turf = (91, 115, 76) if rocky else (94, 121, 76)
        dirt = (118, 113, 96) if rocky else (114, 113, 88)
        turf = tuple(mix(dirt[i], turf[i], .62 + .27 * vegetation)
                     + 7 * granular + 2 * crumb for i in range(3))
        if rocky:
            bare = .72 + .35 * vegetation + .08 * granular
        else:
            bare = .18 + .33 * vegetation + .18 * granular
        bare = smooth(max(0, min(1, bare)))
        return tuple(round(mix(turf[i], mineral[i], bare)) for i in range(3))

    return rasterize(sample, 64, 24)


def texture_set():
    yield "hill_side", rock_raster()
    for variant in range(4):
        yield "hill" + str(variant), hill_raster(variant)
    yield "clear_rough", clear_raster(False)
    yield "clear_rocks", clear_raster(True)


def tunnel_sheet(root, mode, mask):
    with Image.open(root / "bl_hill0.png") as image:
        sheet = image.convert("RGBA")
    with Image.open(root / f"bl_{mode}{mask}.png") as image:
        sheet.alpha_composite(image.convert("RGBA").transpose(Image.Transpose.FLIP_TOP_BOTTOM))
    with Image.open(root / "bl_tunnel.png") as image:
        sheet.alpha_composite(image.convert("RGBA"))
    # Lossless indexing keeps the 128 old quarter assets small; asphalt,
    # ballast and portal accents retain exactly their original RGB values.
    image = sheet.convert("RGB")
    pixels = list(image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata())
    palette = sorted(set(pixels))
    assert len(palette) <= 16, (mode, mask, len(palette))
    indices = {color: index for index, color in enumerate(palette)}
    indexed = Image.new("P", image.size)
    indexed.putpalette([channel for color in palette for channel in color] + [0] * (3 * (16 - len(palette))))
    indexed.putdata([indices[color] for color in pixels])
    return indexed


def write_tunnels(root):
    for mode in ("road", "rail"):
        for mask in range(16):
            sheet = tunnel_sheet(root, mode, mask)
            for q in range(4):
                x, y = q % 2 * 16, q // 2 * 16
                sheet.crop((x, y, x + 16, y + 16)).save(
                    root / f"bl_{mode}_{mask}_tunnel_q{q}.png", optimize=True, bits=4)


if __name__ == "__main__":
    out = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"
    for name, image in texture_set():
        image.save(out / f"bl_{name}.png", optimize=True)
    write_tunnels(out)
