#!/usr/bin/env python3
"""Test the exact ocean surface/UV joins and the stock shore's submerged art."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build_coastal_sheet import APRON, SEA, SIZE, MASKS, bank, ocean, source


def parse(text):
    vertices, uv, faces = [], [], []
    for line in text.splitlines():
        kind, *values = line.split()
        if kind == "v":
            vertices.append(tuple(map(float, values)))
        elif kind == "vt":
            uv.append(tuple(map(float, values)))
        elif kind == "f":
            faces.append(tuple(int(s.split("/")[0])-1 for s in values))
    return vertices, uv, faces


for z in range(SIZE):
    for x in range(SIZE):
        verts, uv, faces = parse(ocean(x, z))
        assert len(set(verts)) == 4 and len(faces) == 2 and {v[1] for v in verts} == {.5}
        u_next = parse(ocean((x+1)%SIZE,z))[1]
        v_next = parse(ocean(x,(z+1)%SIZE))[1]
        assert uv[1][0]%1 == u_next[0][0]%1 and uv[2][0]%1 == u_next[3][0]%1
        assert uv[3][1]%1 == v_next[0][1]%1 and uv[2][1]%1 == v_next[1][1]%1

skirts = 0
for slope in MASKS:
    verts, uv, faces = parse(bank(slope))
    raw = source(slope)
    for f in faces:
        points = [verts[i] for i in f]
        sub = any(v[1]<SEA for v in points)
        assert -1.5 <= min(v[0] for v in points) <= max(v[0] for v in points) <= .5
        assert -.5 <= min(v[2] for v in points) <= max(v[2] for v in points) <= 1.5
        assert all(0 <= uv[i][0] <= 2/3 for i in f), "Shore does not paint a second water layer"
        if sub:
            skirts += 1
            assert all(v[1] in (SEA,SEA-APRON) for v in points)
            # Only a stock rising triangle's zero-height edge can get a skirt.
            xy = {(a,c) for a,_,c in points}
            assert len(xy)==2 and any(xy <= {(a,c) for a,b,c in tri if b==SEA} and
                                     max(v[1] for v in tri)>SEA for tri in raw)
        else:
            assert max(v[1] for v in points)>SEA, "Zero-height water side has no flat ground cap"
assert skirts > 0 and APRON > 4 * .5, "Cover worst allowed stock native wave depression"
print(f"PASS: 16 seamless top-only water phases, {len(MASKS)} original wet banks and {skirts} submerged skirt triangles")
