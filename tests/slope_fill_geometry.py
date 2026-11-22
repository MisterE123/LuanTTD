"""Natural slope triangles stay exact while their supporting cube has no top."""
from pathlib import Path

models = Path(__file__).resolve().parents[1] / "mods/bayline/models"


def obj(name):
    verts, faces = [], []
    for row in (models / f"bl_{name}.obj").read_text().splitlines():
        if row.startswith("v "):
            verts.append(tuple(map(float, row.split()[1:])))
        if row.startswith("f "):
            faces.append([verts[int(token.split("/")[0]) - 1] for token in row.split()[1:]])
    return verts, faces


verts, faces = obj("slope_fill_open")
assert len(verts) == 8 and len(faces) == 5
assert all(set(v[axis] for v in verts) == {-0.5, 0.5} for axis in range(3))
planes = [(axis, f[0][axis]) for f in faces for axis in range(3)
          if all(v[axis] == f[0][axis] for v in f)]
assert set(planes) == {(0, -0.5), (0, 0.5), (1, -0.5), (2, -0.5), (2, 0.5)}
for mask in (1, 2, 4, 8):
    _, slope = obj(f"land_{mask}")
    # These original corners both cover the exact tile AND contain a
    # genuine flat lower triangle. A cube top below the slope's node
    # would therefore land at precisely the same y as that triangle.
    assert len(slope) == 2
    assert sum(all(y == -0.5 for _, y, _ in tri) for tri in slope) == 1
    assert {p[0] for tri in slope for p in tri} == {-1.5, 0.5}
    assert {p[2] for tri in slope for p in tri} == {-0.5, 1.5}
print("PASS four stock one-corner meshes retain their exact planes, and open-top fill cannot redraw their flat half")
