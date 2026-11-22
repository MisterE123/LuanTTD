#!/usr/bin/env python3
"""Check original water strips tile, loop and preserve downstream direction."""
from pathlib import Path
import math
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from terrain_water_raster import FRAMES, RIVER_DIRECTIONS, SIZE, river_surface, sea_surface, water_strips


def check_fields():
    for kind in (sea_surface, river_surface):
        sample = kind()
        for i in range(19):
            a, b = (i + .3) / 19, (18 - i + .7) / 19
            assert math.isclose(sample(0, a, b), sample(1, a, b), abs_tol=1e-12)
            assert math.isclose(sample(a, 0, b), sample(a, 1, b), abs_tol=1e-12)
            assert math.isclose(sample(a, b, 0), sample(a, b, 1), abs_tol=1e-12)
            if kind == river_surface:
                # What was at (u,v) moves downstream along +V this interval.
                delta = 1 / FRAMES
                assert math.isclose(sample(a, b, 0), sample(a, b + delta, delta), abs_tol=1e-12)


def check_assets():
    total = 0
    loaded = {}
    for name, generated in water_strips():
        path = ROOT / f"mods/luanttd_core/textures/bl_water_{name}_anim.png"
        total += path.stat().st_size
        image = Image.open(path).convert("RGBA")
        assert image.size == (SIZE, FRAMES * SIZE)
        assert image.tobytes() == generated.convert("RGBA").tobytes()
        assert image.getextrema()[-1] == (255, 255)
        sequence = [image.crop((0, y, SIZE, y + SIZE)) for y in range(0, FRAMES * SIZE, SIZE)]
        assert len({im.tobytes() for im in sequence}) == FRAMES, (name, "identical frames")
        loaded[name] = sequence
    assert 20_000 < total < 45_000, total
    for name, transform in RIVER_DIRECTIONS.items():
        if transform is None:
            continue
        for base, turned in zip(loaded["river"], loaded[name]):
            assert base.transpose(transform).tobytes() == turned.tobytes(), name
    return total


if __name__ == "__main__":
    check_fields()
    print(f"Water art: 5 reproducible strips, 10 seamless animated frames each, {check_assets():,} bytes total")
