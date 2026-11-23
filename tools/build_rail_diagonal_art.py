#!/usr/bin/env python3
"""Regenerate the 12 original beveled diagonal railway mesh variants.

Run with blender -b -t 2 --python tools/build_rail_diagonal_art.py.
The common rail authoring library supplies materials and real profiles.
The game topology is not encoded in these meshes.
"""
from math import hypot
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_rail_art as art


class EasedPath(art.TrackPath):
    def __init__(self, index, mode):
        super().__init__(index)
        self.sides = mode
        self.direct = mode == 3
        a, b = self.a, self.b
        self.chord = tuple((b[i] - a[i]) for i in (0, 1))
        dx, dz = self.chord
        inv = 1 / hypot(dx, dz)
        self.unit = (dx * inv, dz * inv)
        t0 = self.unit if mode & 1 else (-a[0], -a[1])
        t1 = self.unit if mode & 2 else b
        # Same as the visual train projection in rail_diagonal.lua.
        # A linear half-unit through an oblique port guarantees that
        # the cross-sections at the clipping plane match the next tile.
        lead = .50 * inv
        self.begin = lead if mode & 1 else 0.
        self.end = 1.-lead if mode & 2 else 1.
        self.ease_a = tuple(a[i]+self.begin*self.chord[i] for i in (0, 1))
        self.ease_b = tuple(a[i]+self.end*self.chord[i] for i in (0, 1))
        handle = .55*(self.end-self.begin)
        self.c = tuple(self.ease_a[i] + handle*t0[i] for i in (0, 1))
        self.d = tuple(self.ease_b[i] - handle*t1[i] for i in (0, 1))
        self.t0, self.t1 = t0, t1
        self.sections = [self.sample(j / 32)[:2] for j in range(33)]
        self.length = sum(hypot(v[0] - u[0], v[1] - u[1])
                          for u, v in zip(self.sections, self.sections[1:]))

    def sample(self, t):
        if self.direct or t <= self.begin and self.sides & 1 or t >= self.end and self.sides & 2:
            return self.a[0]+t*self.chord[0], self.a[1]+t*self.chord[1], *self.unit
        v = (t-self.begin)/(self.end-self.begin)
        u, a, b, c, d = 1-v, self.ease_a, self.ease_b, self.c, self.d
        xy = tuple(u**3*a[i]+3*u*u*v*c[i]+3*u*v*v*d[i]+v**3*b[i] for i in (0, 1))
        dx, dz = tuple(u*u*(c[i]-a[i])+2*u*v*(d[i]-c[i])+v*v*(b[i]-d[i]) for i in (0, 1))
        n = hypot(dx, dz)
        return *xy, dx/n, dz/n

    def sweep(self, low, high, begin=0., end=1.):
        assert begin == 0 and end == 1
        def run(offset):
            out = []
            for end_, anchor, direction, eased in ((0, self.a, self.t0, self.sides & 1),
                                                        (1, self.b, self.t1, self.sides & 2)):
                if end_:
                    # Include exact straight-tail boundaries. The tail and
                    # its extension need no redundant tessellation.
                    samples = [0., 1.] if self.direct else sorted({
                        0., 1., *(self.begin+(self.end-self.begin)*i/12 for i in range(13))
                    })
                    out.extend(self.offset(t, offset) for t in samples)
                if eased:
                    extension = .8 if end_ else -.8
                    dx, dz = direction
                    out.append((anchor[0]+extension*dx-offset*dz, anchor[1]+extension*dz+offset*dx))
            return out
        return run(low) + list(reversed(run(high)))

    def ribbon_points(self):
        points = [self.a, self.b] if self.direct else list(self.sections)
        if self.sides & 1:
            points.insert(0, tuple(self.a[i]-.8*self.t0[i] for i in (0,1)))
        if self.sides & 2:
            points.append(tuple(self.b[i]+.8*self.t1[i] for i in (0,1)))
        return points

    def distance(self, x, z):
        if self.direct:
            dx, dz = self.unit
            return abs((x-self.a[0])*dz-(z-self.a[1])*dx)
        best = 9
        for a, b in zip(self.sections, self.sections[1:]):
            dx, dz = b[0]-a[0], b[1]-a[1]
            t = min(1, max(0, ((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
            best = min(best, (x-a[0]-t*dx)**2+(z-a[1]-t*dz)**2)
        return best**.5

    def sleeper_points(self, count):
        # A half sleeper meets its other half at each diagonal seam.
        lo = 0 if self.sides & 1 else .5
        hi = count if self.sides & 2 else count - .5
        n = max(2, round(hi-lo)+1)
        return ((lo+(hi-lo)*i/(n-1))/count for i in range(n))


def main():
    geos = art.Geos()
    art.bpy.ops.wm.read_factory_settings(use_empty=True)
    art.bpy.context.preferences.filepaths.save_version = 0
    art.bpy.context.scene.name = "LuanTTD / continuous diagonal rail presentation"
    mats = art.materials()
    for index in range(2, 6):
        mask = 2**index
        for mode in (1, 2, 3):
            mesh = art.rail_geometry(mask, 0, geos, detail=False, paths=[EasedPath(index, mode)])
            coll = art.stash(mesh, mats, f"{mask} / diagonal ports {mode}")
            art.instance(art.bpy.context.scene, coll, 3*(mode-2), 3*(index-3))
            art.export_obj(art.MODELS / f"bl_rail_eased_{mask}_{mode}.obj", mesh)
    art.bpy.ops.wm.save_as_mainfile(filepath=str(art.ROOT/"art/rail_diagonal_tracks.blend"), compress=True)


if __name__ == "__main__":
    main()
