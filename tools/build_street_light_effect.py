#!/usr/bin/env python3
"""Generate feathered radial lamp optics (no crossed alpha billboards)."""
from math import cos, pi, sin
from pathlib import Path
from PIL import Image

MOD = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
SIDES = 24
SHELLS = 12


def mesh(kind, rings, bands):
    vertices, faces = [], []
    for a, b in bands:
        # Keep an entire panel in one mesh buffer and use each ring's own
        # radial gradient without crossing transparent polygons.
        for i in range(SIDES):
            j = (i + 1) % SIDES
            faces.append((rings[a][i], rings[a][j], rings[b][j], rings[b][i]))
    for ring in rings:
        vertices.extend(ring)
    lines = [f"# Original LuanTTD {kind}, node-unit coordinates", "o street_light_" + kind]
    for x, y, z, u, v, idx in vertices:
        lines.append(f"v {x:.6f} {y:.6f} {z:.6f}")
    for x, y, z, u, v, idx in vertices:
        lines.append(f"vt {u:.6f} {v:.6f}")
    for a, b, c, d in faces:
        lines.append("f " + " ".join(f"{e[-1]}/{e[-1]}" for e in (a, b, c, d)))
    (MOD / "models" / f"bl_street_light_{kind}.obj").write_text("\n".join(lines) + "\n")


def ring(r, y, u, v, start):
    return [(r*cos(2*pi*i/SIDES), y, r*sin(2*pi*i/SIDES), u, v, start+i+1) for i in range(SIDES)]


rings = []
for i in range(SHELLS):
    fraction = (i + 1) / SHELLS
    u = (i + .5) / SHELLS
    for v, radius, height in ((.984, .033, 0), (.016, .38, -.91)):
        rings.append(ring(radius*fraction, height, u, v, len(rings)*SIDES))
mesh("cone", rings, [(2*i, 2*i+1) for i in range(SHELLS)])
img = Image.new("RGBA", (SHELLS, 64))
for i in range(SHELLS):
    for dy in range(64):
        t = dy/63
        fade = min(1, (1-t)*6) * (.82 + .18*sin(pi*t))
        weight = (1 - i / SHELLS)**.65
        img.putpixel((i, dy), (255, 210, 128, round(9*weight*fade)))
img.save(MOD / "textures" / "bl_street_light_cone.png", optimize=True)
rings = [ring(max(.0001, .56*i/12), 0, .5, 1-i/12, i*SIDES) for i in range(13)]
mesh("pool", rings, [(i,i+1) for i in range(12)])
img = Image.new("RGBA", (4, 64))
for y in range(64):
    for x in range(4):
        img.putpixel((x, y), (255, 213, 143, round(78*(1-y/63)**1.7)))
img.save(MOD / "textures" / "bl_street_light_pool.png", optimize=True)
