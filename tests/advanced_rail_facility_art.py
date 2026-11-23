#!/usr/bin/env python3
"""Facilities must leave their type's actual running surfaces connected."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from math import isfinite

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"mods/luanttd_core/models"
EPS=2e-6

def read(name,rot):
    points,groups=[],{}
    for l in (MODEL/f"bl_guideway_{name}.obj").read_text().splitlines():
        if l.startswith("o "):
            group=l[2:]
            groups[group]=[]
        elif l.startswith("v "):
            x,h,z=map(float,l.split()[1:])
            assert all(map(isfinite,(x,h,z)))
            x,z=-x-.5,z-.5
            for _ in range(rot):
                x,z=z,-x
            points.append(tuple(round(v,6) for v in (x,z,h+.5)))
        elif l.startswith("f "):
            tri=tuple(points[int(v.split("/")[0])-1] for v in l.split()[1:])
            assert len(tri)==3 and len(set(tri))==3
            groups[group].append(tri)
    return groups

def seam(groups,coord,v):
    t=1-coord
    return {(p[t],p[2]) for faces in groups.values() for f in faces for p in f if abs(p[coord]-v)<EPS}

for kind,head,base,top,nose,deck in (("mono",.096,.263,.246,.284,.431),
                                       ("maglev",.251,.338,.213,.358,.397)):
    track=read(f"{kind}_flat_1",0)
    rail_exit={(q,h) for q,h in seam(track,0,1.)}
    platform=read(f"{kind}_platform_0",0)
    for r,turn in enumerate((0,3)):
        frame=read(f"{kind}_platform_{r}",turn)
        assert frame==platform
        for direction in (-1,1):
            next_track=seam(frame,0,direction)
            assert rail_exit.issubset(next_track),(kind,direction)
            assert all(q>nose-EPS for q,h in next_track-rail_exit)
            for faces in frame.values():
                assert not any(all(abs(p[0]-direction)<EPS for p in f) for f in faces)
        edging={v for f in frame["Textured_tactile_platform_edge"] for v in f}
        assert abs(min(p[1] for p in edging)-nose)<EPS
        assert abs(max(p[2] for p in edging)-deck)<EPS
        assert deck-top>.18   # above the running surface, at the door sill
        cap={v for f in frame["Recessed_closed_platform_ends"] for v in f}
        assert {abs(x) for x,_,_ in cap}=={.982}
    depot=read(f"{kind}_depot_1",0)
    track_in=read(f"{kind}_flat_2",0)
    for r,turn in enumerate((1,0,3,2)):
        frame=read(f"{kind}_depot_{r}",turn)
        assert frame==depot
        assert seam(frame,1,1.)==seam(track_in,1,1.)
        assert not seam(frame,1,-1.)
        # Check every surface bounding box that could intersect a
        # conservative stock train envelope through the actual doorway.
        for label,faces in frame.items():
            if label in track_in:
                continue
            for f in faces:
                bounds=[(min(p[k] for p in f),max(p[k] for p in f)) for k in range(3)]
                (x0,x1),(z0,z1),(h0,h1)=bounds
                assert x1<-.250 or x0>.250 or z1<-.699 or z0>1 or h0>.82 or h1<top-.077, (kind,label,bounds)
assert (ROOT/"art/advanced_rail_facilities.blend").stat().st_size>20000
print("PASS 12 rail facilities: flush seams, recessed platform ends, correct deck and real clearway through every depot orientation.")
