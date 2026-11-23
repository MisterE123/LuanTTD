#!/usr/bin/env python3
"""Verify actual combined meshes, stock ports and open engine envelopes."""
from pathlib import Path
from itertools import combinations, product
from math import isclose
import re
import struct

from rail_span_art import vehicle

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
GAUGE=(-.242,-.182,.182,.242)
DIRECTIONS=((-1,0),(0,1),(1,0),(0,-1))


def read(stem):
    vertices=[]
    groups={}
    for line in (MODELS/f"bl_rail_{stem}.obj").read_text().splitlines():
        kind, _, rest=line.partition(" ")
        if kind=="v":
            a,b,c=map(float,rest.split())
            x,z,h=-a-.5,c-.5,b+.5
            assert -1.000002<=x<=1.000002 and -1.000002<=z<=1.000002,(stem,x,z)
            vertices.append((x,z,h))
        if kind=="o":
            polygons=groups.setdefault(rest,[])
        if kind=="f":
            indices=[int(ref.partition("/")[0])-1 for ref in rest.split()]
            assert len(indices)==3
            polygons.append(tuple(vertices[i] for i in indices))
    assert sum(map(len,groups.values()))>1500
    return groups


def edges(groups):
    result=[]
    for x,z in DIRECTIONS:
        candidates={round(p[0] if z else p[1],6) for tri in groups["Polished_railhead"] for p in tri
                    if isclose(p[2],.114,abs_tol=1e-6) and isclose(x*p[0]+z*p[1],1,abs_tol=1e-6)}
        result.append(tuple(sorted(candidates)))
    return result


def det(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def overlap_area(a,b):
    # Positive-area triangle intersection; touching at an edge/point is OK.
    orient=1 if det(*b)>0 else -1
    for first,last in zip(b,b[1:]+b[:1]):
        cut=[]
        for p,q in zip(a,a[1:]+a[:1]):
            u,v=orient*det(first,last,p),orient*det(first,last,q)
            pin,qin=(u>=-1e-12),(v>=-1e-12)
            if pin!=qin and abs(u-v)>1e-14:
                t=u/(u-v)
                cut.append(tuple(x+t*(y-x) for x,y in zip(p,q)))
            if qin:
                cut.append(q)
        if len(cut)<3:
            return 0
        a=cut
    return abs(sum(det((0,0),p,q) for p,q in zip(a,a[1:]+a[:1])))/2


def sections(faces,axis,h):
    return [tuple(tuple(v for j,v in enumerate(p) if j!=axis) for p in f)
            for f in faces if all(isclose(p[axis],h,abs_tol=1e-7) for p in f)]


def bounds(f):
    return tuple((min(v[i] for v in f),max(v[i] for v in f)) for i in range(2))


def assert_no_area_overlap(pairs):
    for a,b in pairs:
        if all(max(l1,l2)<min(h1,h2)-1e-8 for (l1,h1),(l2,h2) in zip(bounds(a),bounds(b))):
            assert overlap_area(a,b)<1e-9,(a,b)


def platform_surfaces(g,axis):
    paving=g["Platform_paving"]+g["Scored_paving_joints"]
    for h in {.279,.280,.281}:
        # The old raised cross and longitudinal joints doubled their exact
        # .281 upper faces at every intersection despite equal material.
        assert_no_area_overlap(combinations(sections(paving,2,h),2))
    top=sections(paving,2,.280)
    assert abs(sum(abs(det(*a))/2 for a in top)-2*.480)<1.e-8
    assert abs(sum(abs(det(*a))/2 for a in sections(g["Scored_paving_joints"],2,.280))-.05877)<1e-8
    all_faces=[t for faces in g.values() for t in faces]
    cap=g["Recessed_ashlar_platform_ends"]
    for sign in (-1,1):
        cap_section=sections(cap,axis,sign*.976)
        assert len(cap_section)==10
        assert_no_area_overlap(combinations(cap_section,2))
        assert not sections(all_faces,axis,sign), "Running joints must only share edges, never entire faces"
        dx,dz=(sign,0) if axis==0 else (0,sign)
        # Recession is directional; actual wall blocks sight into the deck.
        perp_sign=dx if axis==0 else -dz
        for offset,h in product((.380,.56,.88),(.020,.24,.272)):
            assert along_portal({"cap":cap},dx,dz,perp_sign*offset,h,.975,.977)
    # No long horizontal underside is coplanar with the rendered land.
    for group in ("Dressed_stone_platform","Platform_paving","Scored_paving_joints"):
        assert not sections(g[group],2,0),(axis,group)


def along_portal(g,dx,dz,x0,h,z0,z1):
    """Longitudinal ray against all triangles in depot-local coordinates."""
    for faces in g.values():
        for a,b,c in faces:
            p0,p1,p2=[(z*dx-x*dz, y,dx*x+dz*z) for x,z,y in (a,b,c)]
            vx,vy=p1[0]-p0[0],p1[1]-p0[1]
            wx,wy=p2[0]-p0[0],p2[1]-p0[1]
            qx,qy=x0-p0[0],h-p0[1]
            det=vx*wy-wx*vy
            if abs(det)<1e-12:
                continue
            u=(qx*wy-qy*wx)/det
            v=(vx*qy-vy*qx)/det
            if u>=-1e-8 and v>=-1e-8 and u+v<=1+1e-8:
                z=p0[2]+u*(p1[2]-p0[2])+v*(p2[2]-p0[2])
                if z0<=z<=z1:
                    return True
    return False


def main():
    atlas=ROOT/"mods/luanttd_core/textures/bl_rail_architecture_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24])==(42*8,8)
    for i in (1,2):
        g=read(f"platform_{i}")
        assert edges(g)==([GAUGE,(),GAUGE,()] if i==1 else [(),GAUGE,(),GAUGE])
        assert "Timber_seat" in g and "Platform_canopy" in g
        shade=[p[2] for tri in g["Platform_canopy"] for p in tri]
        assert .29<min(shade)-.280<.42 and .71<max(shade)<.73
        platform_surfaces(g,i-1)
    # Measure the mounted meshes rather than demanding a full uniform
    # box as tall as the tallest chimney, which forced a giant arch.
    dispatch=(ROOT/"mods/luanttd_core/rail_dispatch_view.lua").read_text()
    names=set(re.findall(r'mesh="(bl_[a-z_0-9]+)\.obj"',dispatch))
    assert {"bl_rail_kirby_paul_tank","bl_rail_passenger_wagon","bl_rail_chaney_jubilee"}<=names
    envelope={}
    for name in sorted(names):
        for x,z,h in vehicle(name):
            i=round(x/.02)
            envelope[i]=max(envelope.get(i,0),h+.114)
    rays=0
    for i,(dx,dz) in enumerate(DIRECTIONS):
        g=read(f"depot_{i}")
        assert edges(g)==[GAUGE if dir==i else () for dir in range(4)]
        assert "Dressed_stone_arch_voussoirs" in g and "Cast_end-of-track_buffer" in g
        shell={k:v for k,v in g.items() if k in
          {"Masonry_gable","Dressed_stone_arch_voussoirs","Stone_jambs","Masonry_porch_piers","Brick_side_walls","Slate_roof"}}
        whole=[p for gg in shell.values() for tri in gg for p in tri]
        assert 1.21<max(h for _,_,h in whole)<1.32
        for bin_,top in envelope.items():
            x=bin_*.02
            for y in (.122,(top+.122)*.5,top+.022):
                assert not along_portal(shell,dx,dz,x,y,-.635,1.10),(i,x,y)
                rays+=1
        for x in (-.27,0,.27):
            assert along_portal(g,dx,dz,x,.55,-1.1,-.798),(i,x)
    print(f"PASS: nonoverlapping deck faces, recessed platform ends, and exact rail seams in both axes; {rays} locomotive envelope rays clear four depot arches")
if __name__=="__main__":
    main()
