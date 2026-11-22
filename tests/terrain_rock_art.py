#!/usr/bin/env python3
"""Check generated stone is reproducible, opaque and unintrusive in mipmaps."""
from pathlib import Path
import statistics
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "mods/bayline/textures"
sys.path.insert(0, str(ROOT / "tools"))
from terrain_rock_raster import SIZE, texture_set, rock_surface, tunnel_sheet


def pixels(image):
    if hasattr(image, "get_flattened_data"):
        return image.get_flattened_data()
    return list(image.getdata())


def main():
    means = {}
    hill_edges = []
    for name, source in texture_set():
        asset = ASSETS / f"bl_{name}.png"
        with Image.open(asset) as checked:
            assert checked.mode == "P", name
            assert checked.size == source.size
            im = checked.convert("RGB")
            assert im.tobytes() == source.convert("RGB").tobytes(), name
            assert checked.convert("RGBA").getextrema()[-1] == (255, 255), name
        assert asset.stat().st_size < (12_000 if name == "hill_side" else 2600)
        gray = im.convert("L")
        means[name] = tuple(statistics.mean(c) for c in zip(*pixels(im)))
        assert 3 < statistics.pstdev(pixels(gray)) < 9, name
        far = gray.resize((16, 16), Image.Resampling.LANCZOS)
        assert 1 < statistics.pstdev(pixels(far)) < 6, name
        n = im.width
        if name.startswith("hill") and n == 32:
            assert max(means[name]) - min(means[name]) < 6, name
            hill_edges.append(gray.crop((1, 0, n - 1, 1)))
        lookup = gray.load()
        for transpose in (False, True):
            def difference(a, b, y):
                return abs((lookup[y, a] - lookup[y, b]) if transpose else
                           (lookup[a, y] - lookup[b, y]))
            seam = statistics.mean(difference(n - 1, 0, y) for y in range(n))
            inside = statistics.mean(difference(x, x + 1, y)
                                     for x in range(n - 1) for y in range(n))
            assert seam <= 1.35 * inside, (name, seam, inside)

    for tops in hill_edges[1:]:
        a, b = pixels(hill_edges[0]), pixels(tops)
        assert max(abs(x-y) for x, y in zip(a, b)) <= 5
    assert means["clear_rough"][1] - means["clear_rough"][0] >= 10
    assert means["clear_rocks"][0] - means["clear_rough"][0] >= 10

    # Source is actually periodic, not just a copy of its end columns.
    sample = rock_surface()
    for i in range(SIZE):
        uv = (i + .375) / SIZE
        assert sample(0, uv) == sample(1, uv)
        assert sample(uv, 0) == sample(uv, 1)

    tunnel_bytes = 0
    for mode in ("road", "rail"):
        for mask in range(16):
            sheet = tunnel_sheet(ASSETS, mode, mask).convert("RGB")
            for q in range(4):
                x, y = q % 2 * 16, q // 2 * 16
                asset = ASSETS / f"bl_{mode}_{mask}_tunnel_q{q}.png"
                with Image.open(asset) as piece:
                    assert piece.mode == "P"
                    assert piece.convert("RGB").tobytes() == sheet.crop((x,y,x+16,y+16)).tobytes(), asset
                tunnel_bytes += asset.stat().st_size
    assert tunnel_bytes <= 35_000, tunnel_bytes
    print("Terrain art: seven opaque subdued materials and 128 native tunnel quadrants match deterministic source")


if __name__ == "__main__":
    main()
