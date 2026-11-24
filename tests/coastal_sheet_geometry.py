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

for slope in (3, 6, 9, 12):
    shifted, coords, faces = parse(bank(slope, bridge=True))
    verts = [(round(x-1,8),y,z) for x,y,z in shifted]
    ordinary, uv, ordinary_faces = parse(bank(slope))
    top = lambda vertices, indices: sorted(tuple(sorted(vertices[i] for i in f))
        for f in indices if all(vertices[i][1]>=SEA for i in f))
    assert top(verts,faces) == top(ordinary,ordinary_faces), "Bridge top matches the stock sloping coast"
    assert all(-1.5 <= x <= .5 and -.5 <= z <= 1.5 for x,_,z in verts), "No mesh on neighbor"
    assert all(u <= 2/3 for u,v in coords), "Water is always the separate native ocean"
    walls=[tuple(verts[i] for i in f) for f in faces if any(verts[i][1]<SEA for i in f)]
    assert len(walls)==8, "All four edges have two closed wall triangles"
    assert all(min(v[1] for v in wall)==SEA-APRON for wall in walls)
print("PASS: four stock bridge-shore slopes preserve their exact top and close each bank to below the wave envelope")
