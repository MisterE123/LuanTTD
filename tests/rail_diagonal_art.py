#!/usr/bin/env python3
"""Verify actual generated OBJ railheads at stock tile ports."""
from pathlib import Path
from math import sqrt

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
ports = {4: (0, 3), 8: (2, 1), 16: (2, 3), 32: (0, 1)}
sides = ((-1., 0.), (0., 1.), (1., 0.), (0., -1.))


def read(name):
    seen = False
    all_v, head = [], []
    for ln in (root / f"bl_rail_{name}.obj").read_text().splitlines():
        if ln.startswith('o '):
            seen = ln == 'o Polished_railhead'
        if ln.startswith("v "):
            x, h, z = (float(v) for v in ln.split()[1:])
            p = (-x-.5, z-.5, h+.5)
            all_v.append(p)
            if seen and abs(p[2]-.114) < 1e-6:
                head.append(p[:2])
    assert all_v and head, name
    return all_v, head


def interval(vertices, side):
    target = sides[side]
    seam = sorted((z if side % 2 == 0 else x) for x, z in vertices
                  if abs(x*target[0]+z*target[1]-1) < 1e-6)
    assert seam and seam[0] < 0 < seam[-1], (side, seam)
    neg, pos = [v for v in seam if v < 0], [v for v in seam if v > 0]
    return [min(neg), max(neg), min(pos), max(pos)]


for mask, tile_ports in ports.items():
    plain = read(f"track_{mask}")[1]
    for mode in range(1, 4):
        all_v, head = read(f"eased_{mask}_{mode}")
        assert all(max(abs(x), abs(z)) <= 1.000001 for x, z, _ in all_v), (mask, mode)
        for idx, side in enumerate(tile_ports):
            oblique = bool(mode & (1 << idx))
            intervals = interval(head, side)
            before = interval(plain, side)
            reference = [x*(sqrt(2) if oblique else 1.) for x in before]
            assert max(abs(a-b) for a, b in zip(intervals, reference)) < 4e-6, (mask, mode, side, intervals, reference)
        if mode == 3:
            # Every railhead point stays within one of the two offset
            # stripes of a 45-degree centerline, not a quarter-turn arc.
            a, b = (sides[side] for side in tile_ports)
            for x, z in head:
                d = abs((x-a[0])*(b[1]-a[1]) - (z-a[1])*(b[0]-a[0])) / sqrt(2)
                assert .181999 <= d <= .242001, (mask, x, z, d)
print("PASS all 12 OBJ variants are tile-clipped and their diagonal/ordinary railheads fit exactly")
