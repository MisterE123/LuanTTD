#!/usr/bin/env python3
"""Prove the exported monorail and maglev fit the stock tile geometry."""
# SPDX-License-Identifier: GPL-2.0-only
from math import isclose, isfinite, sqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
SIDE = ((-1., 0.), (0., 1.), (1., 0.), (0., -1.))
TRACK_PORTS = ((0, 2), (3, 1), (0, 3), (2, 1), (2, 3), (0, 1))
EPS = 0.000006


def read(name, grade=False):
    path = ROOT / "models" / f"bl_guideway_{name}.obj"
    points, faces, group_faces = [], [], {}
    uv_count = normal_count = 0
    for line in path.read_text().splitlines():
        if line.startswith("o "):
            group = line[2:]
            group_faces[group] = []
        elif line.startswith("v "):
            x, y, z = map(float, line.split()[1:])
            assert all(map(isfinite, (x, y, z))), name
            point = (-x-.5, z-.5, y+(1.5 if grade else .5))
            assert max(map(abs, point[:2])) <= 1 + EPS, (name, point)
            points.append(point)
        elif line.startswith("vt "):
            uv_count += 1
        elif line.startswith("vn "):
            normal_count += 1
        elif line.startswith("f "):
            tri = []
            for item in line.split()[1:]:
                vi, uv, ni = map(int, item.split("/"))
                assert 1 <= vi <= len(points) and 1 <= uv <= uv_count and 1 <= ni <= normal_count, (name, line)
                tri.append(points[vi-1])
            assert len(set(tri)) == 3, (name, line)
            for sx, sz in SIDE:
                assert not all(isclose(x*sx+z*sz, 1., abs_tol=EPS) for x,z,_ in tri), (name, "doubled face on seam")
            faces.append(tri)
            group_faces[group].append(tri)
    assert faces and uv_count == 19, name
    assert all(group_faces.values()), name
    return points, group_faces


def cross_section(points, side, height=None):
    sx, sz = SIDE[side]
    return sorted({z if sx else x for x,z,y in points
                   if abs(x*sx + z*sz - 1.) < EPS and
                   (height is None or abs(y-height) < EPS)})


def check_span(points, name, side, width, height=None):
    cut = cross_section(points, side, height)
    assert cut and abs(cut[0]+width) < EPS and abs(cut[-1]-width) < EPS, (name, side, height, cut, width)
    return cut


for family, foot, wear, top in (("mono",.263,.096,.246), ("maglev",.338,.251,.213)):
    for mask in range(1, 64):
        name = f"{family}_flat_{mask}"
        pts, groups = read(name)
        expected = {p for i, ports in enumerate(TRACK_PORTS) if mask & 1 << i for p in ports}
        for side in range(4):
            if side in expected:
                check_span(pts, name, side, foot)
                check_span(pts, name, side, wear, top)
            else:
                assert not cross_section(pts, side), (name, "unexpected connecting edge", side)
        if family == "maglev":
            stator = {p[2] for t in groups["Exposed_copper_armature_segments"] for p in t}
            assert all(abs(y-.163)<EPS for y in stator), (name, stator)
            assert top-max(stator) > .045
        else:
            joint = {p[2] for t in groups["Real_recesses_at_segment_joints"] for p in t}
            assert all(abs(y-(top-.005))<EPS for y in joint), (name, joint)

    for grade, start, finish in ((1,0,2),(2,2,0),(3,3,1),(4,1,3)):
        name = f"{family}_grade_{grade}"
        pts,_ = read(name, grade=True)
        check_span(pts, name, start, wear, top)
        check_span(pts, name, finish, wear, 1+top)
        for x,z,h in pts:
            xf,zf = (x+1)/2, (z+1)/2
            assert .00799 <= h-(xf,1-xf,zf,1-zf)[grade-1] <= top+EPS, (name, x,z,h)

    for i, (a,b) in enumerate(TRACK_PORTS[2:], 2):
        for mode in (1,2,3):
            name = f"{family}_eased_{1<<i}_{mode}"
            pts,_ = read(name)
            for j, side in enumerate((a,b)):
                k = sqrt(2) if mode & 1 << j else 1.
                check_span(pts, name, side, foot*k)
                # The shoulders are projected to the centreline. At an oblique
                # port the half-width grows to sqrt(2) in the seam plane.
                check_span(pts, name, side, wear*k, top)
print("PASS 158 exported guideways; flat, grade, fork, crossing and 45-degree seams fit both rail types.")
