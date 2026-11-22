"""Original periodic sea ripples and advecting river surface for Luanti."""
from math import cos, sin, tau
from pathlib import Path
from random import Random

from PIL import Image

from terrain_rock_raster import mix, noise

SIZE = 64
FRAMES = 10
# PNG vectors: increasing U right; increasing V down. Rotate each frame, not
# the complete image; Luanti's vertical_frames require a contiguous column.
RIVER_DIRECTIONS = {
    "river": None,
    "river_north": Image.Transpose.ROTATE_180,
    "river_east": Image.Transpose.ROTATE_90,
    "river_west": Image.Transpose.ROTATE_270,
}
OUT = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"


def palette(colors):
    """A small blue or blue-green gradient; avoid stark white floating marks."""
    shades = []
    for i in range(16):
        a, b, w = (*colors[:2], i / 10) if i <= 10 else (*colors[1:], (i - 10) / 5)
        shades.extend(round(mix(x, y, w)) for x, y in zip(a, b))
    return shades


def sea_surface():
    rand = Random(10303)
    wind = noise(rand, 4, 4)
    sheen = noise(rand, 5, 6)
    cap = noise(rand, 9, 7)

    def sample(u, v, t):
        # Small wind waves, not particles drawn as separate strokes per tile.
        # Both phase functions close in UV and time, with texture over a
        # larger patch rather than trying to make a shore in every square.
        a = cos(tau * (u + 3*v - t + .24*wind(u, v)))
        b = cos(tau * (3*u - 2*v + t + .30*sheen(u, v)))
        c = cos(tau * (4*u + 5*v - t + .33*cap(u, v)))
        glint = max(0, .67*a + .27*b + .23*c - .47) ** 2
        return 7 + 1.7*a + 1.2*b + .95*c + 9*glint + 1.2*sheen(u, v)
    return sample


def river_surface():
    rand = Random(30117)
    winding = noise(rand, 4, 3)
    streaks = noise(rand, 10, 3)
    surface = noise(rand, 8, 9)

    def sample(u, v, t):
        # Carry texture features downstream in image +V. The local
        # eddies and fine ripple interruptions travel with the current.
        q = v - t
        x = u + .058*winding(u, q) + .032*sin(tau*q)
        a = cos(tau * (7*x + .52*winding(u, q)))
        b = cos(tau * (u + 6*q + .48*surface(u, q)))
        grit = surface(u, q)
        patch = streaks(x, q)
        crest = max(0, .72*a + .7*patch + .24*b - .50) ** 2
        return 7 + (.55 + .35*patch)*a + 1.0*b + .85*grit + 11*crest
    return sample


def frames(sample, colors):
    for i in range(FRAMES):
        im = Image.new("P", (SIZE, SIZE))
        im.putpalette(palette(colors))
        im.putdata([min(15, max(0, round(sample((x + .5) / SIZE, (y + .5) / SIZE, i / FRAMES))))
                    for y in range(SIZE) for x in range(SIZE)])
        yield im


def strip(images, transform=None):
    result = Image.new("P", (SIZE, FRAMES * SIZE))
    result.putpalette(images[0].getpalette())
    for i, im in enumerate(images):
        result.paste(im.transpose(transform) if transform is not None else im, (0, i * SIZE))
    return result


def water_strips():
    sea = ((33, 83, 111), (55, 121, 153), (95, 155, 180))
    river = ((37, 88, 91), (61, 124, 128), (106, 155, 150))
    yield "sea", strip(tuple(frames(sea_surface(), sea)))
    flow = tuple(frames(river_surface(), river))
    for name, transform in RIVER_DIRECTIONS.items():
        yield name, strip(flow, transform)


if __name__ == "__main__":
    for name, image in water_strips():
        image.save(OUT / f"bl_water_{name}_anim.png", optimize=True, bits=4)
