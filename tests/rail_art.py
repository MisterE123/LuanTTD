#!/usr/bin/env python3
"""Structural regression on the OBJ files that the native client loads."""
from itertools import product
from math import isclose
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
NAMES=("Ballast_shoulder","Compacted_ballast","Creosoted_sleepers",
       "Cast_iron_chairs","Rail_foot","Rail_web","Polished_railhead","Loose_aggregate")
SIDES=((-1,0),(0,1),(1,0),(0,-1))
ENDS=((0,2),(3,1),(0,3),(2,1),(2,3),(0,1))
CROSS=(-.242,-.182,.182,.242)
RAIL_TOP=.114


def readers(filename,vertical_origin=.5):
    vertices=[]
    normals=[]
    groups={}
    uv=[]
    group=None
    seen=set()
    for line in filename.read_text().splitlines():
        k, _, l=line.partition(" ")
        if k=="o":
            group=l
            groups[group]=[]
        if k=="v":
            ox,oy,oz=map(float,l.split())
            # Undo engine OBJ reflection and the even overlay-node origin.
            x,z,h=-ox-.5,oz-.5,oy+vertical_origin
            assert abs(x)<=1.000001 and abs(z)<=1.000001,(filename.name,x,z)
            vertices.append((x,z,h))
        if k=="vn":
            n=tuple(map(float,l.split()))
            assert abs(sum(d*d for d in n)-1)<.00004
            normals.append(n)
        if k=="vt":
            u,v=map(float,l.split())
            assert 0<u<1 and v==.5
            uv.append((u,v))
        if k=="f":
            refs=[tuple(int(x)-1 for x in item.split("/")) for item in l.split()]
            assert len(refs)==3
            for i,tex,n in refs:
                assert 0<=i<len(vertices) and 0<=tex<len(uv) and 0<=n<len(normals)
            assert len({r[1] for r in refs})==1,"flat palette cell must not blend on one triangle"
            pts=tuple(vertices[r[0]] for r in refs)
            key=tuple(sorted(pts))
            assert key not in seen,(filename.name,group,pts)
            seen.add(key)
            groups[group].append(pts)
    optional={'Forged_switch_and_crossing_hardware'}
    assert tuple(group for group in groups if group not in optional)==NAMES
    assert all(len(v)>=2 for v in groups.values())
    assert len(uv)==19
    return groups


def height(x,z,d):
    return (0., (x+1)/2, (1-x)/2, (z+1)/2, (1-z)/2)[d]


def endpoints(groups,d=0):
    result=[]
    polys=groups["Polished_railhead"]
    assert sum(all(isclose(h,RAIL_TOP+height(x,z,d),abs_tol=2e-6) for x,z,h in tri)
               for tri in polys)>0
    for vx,vz in SIDES:
        edge=set()
        for tri in polys:
            for x,z,h in tri:
                if isclose(x*vx+z*vz,1,abs_tol=1e-6):
                    assert isclose(h-height(x,z,d),.099,abs_tol=2e-6) or isclose(
                                   h-height(x,z,d),RAIL_TOP,abs_tol=2e-6)
                    edge.add(round(x if vz else z,6))
        result.append(tuple(sorted(edge)))
    return result


def main():
    dims=struct.unpack(">II", (ROOT/"mods/luanttd_core/textures/bl_rail_atlas.png").read_bytes()[16:24])
    assert dims==(19*8,8)
    meshes={}
    for mask in range(1,64):
        file=MODELS/f"bl_rail_track_{mask}.obj"
        groups=readers(file)
        actual=endpoints(groups)
        expected=[()]*4
        for i,sides in enumerate(ENDS):
            if mask & (1<<i):
                for side in sides:
                    expected[side]=CROSS
        assert actual==expected,(mask,actual,expected)
        meshes[mask]=actual
    joints=0
    for a,b in product(meshes.values(),repeat=2):
        for side,cross in enumerate(a):
            if cross and b[(side+2)%4]:
                assert cross==b[(side+2)%4]
                joints+=1
    for grade,mask in ((1,1),(2,1),(3,2),(4,2)):
        groups=readers(MODELS/f"bl_rail_grade_{grade}.obj",vertical_origin=1.5)
        assert meshes[mask]==endpoints(groups,grade)
        # Every solid sleeper follows grade even on its outer edges.
        up=.071
        assert any(all(isclose(h-height(x,z,grade),up,abs_tol=2e-6)
                       for x,z,h in f) for f in groups["Creosoted_sleepers"])
    print(f"PASS: 63 flat and four rising OBJ meshes; {joints:,} matched running-rail joins at stock edge gauge")


if __name__=="__main__":
    main()
