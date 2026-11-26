"""Check the shipped dry foundation OBJ edges against their own active top surface.

For each exposed perimeter segment, wall vertices must match both railhead
endpoints and the solid fill plane at y=-.5. The stone faces must point out,
not be backface-culled on one approach, and must have consistent course height.
"""
from collections import defaultdict
from pathlib import Path

models = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
perimeter_count = 0

for pattern, expects in (("bl_rail_inclined_*.obj", 16), ("bl_rail_foundation_split_*.obj", 40)):
    paths = [p for p in sorted(models.glob(pattern)) if not p.stem.endswith("_wet")]
    assert len(paths) == expects, (pattern, len(paths))
    for model in paths:
        vertices, uvs, caps, walls = [], [], [], []
        for row in model.read_text().splitlines():
            if row.startswith("v "):
                vertices.append(tuple(map(float, row[2:].split())))
            elif row.startswith("vt "):
                uvs.append(tuple(map(float, row[3:].split())))
            elif row.startswith("f "):
                indices = [tuple(map(int, ref.split("/"))) for ref in row[2:].split()]
                face = [vertices[v - 1] for v, _ in indices]
                tex = [uvs[t - 1] for _, t in indices]
                assert len(face) == len(set(face)), model.name
                if all(v[1] > .5 for v in tex):
                    caps.append(face)
                else:
                    assert all(abs(t[1] - (.06 + .125 * (v[1] + .5))) < .000002
                               for v, t in zip(face, tex)), model.name
                    walls.append(face)
        assert caps and walls, model.name
        lo_x = min(v[0] for v in vertices)
        hi_x = max(v[0] for v in vertices)
        lo_z = min(v[2] for v in vertices)
        hi_z = max(v[2] for v in vertices)
        edges = defaultdict(list)
        for face in walls:
            for dim, edge, sign in ((0, lo_x, -1), (0, hi_x, 1), (2, lo_z, -1), (2, hi_z, 1)):
                if all(v[dim] == edge for v in face):
                    a, b, c = face[:3]
                    u, v = [b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)]
                    normal = (u[1]*v[2] - u[2]*v[1], 0, u[0]*v[1] - u[1]*v[0])
                    assert normal[dim] * sign > 0, (model.name, face, "inward normal")
                    edges[dim, edge].append(set(face))
        for face in caps:
            for a, b in zip(face, face[1:] + face[:1]):
                for dim, edge in ((0, lo_x), (0, hi_x), (2, lo_z), (2, hi_z)):
                    if a[dim] != edge or b[dim] != edge:
                        continue
                    if a[1] == b[1] == -.5:
                        continue  # no exposed height, and no coplanar wall
                    expected = {a, b, (a[0], -.5, a[2]), (b[0], -.5, b[2])}
                    assert edges[dim, edge].count(expected) == 1, (model.name, expected)
                    perimeter_count += 1
        assert sum(len(v) for v in edges.values()) == sum(
            1 for f in caps for a, b in zip(f, f[1:] + f[:1])
            for d, e in ((0, lo_x), (0, hi_x), (2, lo_z), (2, hi_z))
            if a[d] == b[d] == e and max(a[1], b[1]) > -.5
        ), model.name
print(f"PASS 56 dry rail foundations: {perimeter_count} sealed, outward-facing, consistently UV-mapped perimeter walls")
