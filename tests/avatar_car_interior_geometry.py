#!/usr/bin/env python3
"""Ray and triangle checks for the private driver cabin, in world nodes."""
from math import cos, radians, sqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CABIN = ROOT / "mods/luanttd_core/models/bl_sightseeing_car_interior.obj"


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x*k for x in a)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def point_inside(p, edges, normal):
    return all(dot(cross(sub(v, u), sub(p, u)), normal) >= -1e-9 for u, v in edges)


def distance(tri):
    """Closest face point, including a triangle's interior and edges."""
    a, b, c = tri
    edges = ((a, b), (b, c), (c, a))
    best = min(dot(p, p) for p in tri)
    for u, v in edges:
        line = sub(v, u)
        norm = dot(line, line)
        if norm > 1e-12:
            t = -dot(u, line)/norm
            if 0 < t < 1:
                nearest = sub(u, mul(line, -t))
                best = min(best, dot(nearest, nearest))
    normal = cross(sub(b, a), sub(c, a))
    norm = dot(normal, normal)
    if norm > 1e-12:
        nearest = mul(normal, dot(normal, a)/norm)
        if point_inside(nearest, edges, normal):
            best = min(best, dot(nearest, nearest))
    return sqrt(best)


def ray(direction, triangles):
    for a, b, c in triangles:
        normal = cross(sub(b, a), sub(c, a))
        divisor = dot(normal, direction)
        if abs(divisor) < 1e-10:
            continue
        depth = dot(normal, a)/divisor
        if depth <= 0:
            continue
        p = mul(direction, depth)
        if point_inside(p, ((a, b), (b, c), (c, a)), normal):
            return True
    return False


def load(path):
    vertices, triangles = [], []
    for line in path.read_text().splitlines():
        cols = line.split()
        if not cols:
            continue
        if cols[0] == "v":
            x, y, z = (float(v)/10 for v in cols[1:])
            vertices.append((-x, y, z))  # Luanti OBJ import mirrors X.
        elif cols[0] == "f":
            p = [vertices[int(ref.split("/")[0])-1] for ref in cols[1:]]
            triangles.extend((p[0], p[i], p[i+1]) for i in range(1, len(p)-1))
    return triangles


def main():
    triangles = load(CABIN)
    assert len(triangles) >= 465
    clearance = min(distance(t) for t in triangles)
    # For *any* mouse direction with a viewing cone of this radius,
    # positive camera depth >= distance*cos(angle). This tests complete
    # triangle surfaces, not vertices alone, and leaves a numerical margin.
    engine_near = .10
    assert clearance*cos(radians(53)) >= engine_near + .002, clearance
    # The capsule is 0.222 nodes above the chassis pivot. No private
    # surface should span the road plane or fall below the chassis.
    assert min(v[1] for t in triangles for v in t) >= -.217001
    # Clear actual air apertures, not texture-based holes or absent doors.
    for direction in ((0, 0, 1), (1, 0, 0), (-1, 0, 0),
                      (.09, .04, 1), (-.10, .05, 1),
                      (1, .09, .22), (-1, .09, .22)):
        assert not ray(direction, triangles), direction
    # Floor, roof and both lower door joins are still enclosed when looking
    # steeply down; clearing the near plane must not leave a transparent gap.
    for direction in ((0, 1, 0), (0, -1, 0), (1, -.8, 0), (-1, -.8, 0),
                      (1, -1.2, .5), (-1, -1.2, .5)):
        assert ray(direction, triangles), direction
    print(f"CAR_CABIN_CLEARANCE_PASS {clearance:.3f} nodes; clear front/side apertures and closed roof/floor")


if __name__ == "__main__":
    main()
