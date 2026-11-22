"""Verify the native Bellhaven ferry mesh, shell, and wet/dry cut.

The authored hull is watertight. Its wet/dry color break and visual
submergence from a model origin at Y=0 are independent of game routing.
"""
from collections import Counter, defaultdict
from math import isclose
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
SHELL_GREEN=16
SHELL_BOOT=20
SHELL_DRAFT={18,19}


def read():
    path=ROOT/"mods/luanttd_core/models/bl_harbor_ferry.obj"
    vertices,tex,normals,faces=[],[],[],[]
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        k,*s=line.split()
        if k=="v":
            x,y,z=map(float,s)
            vertices.append((-x/10,y/10,z/10)) # Luanti's OBJ loader reverses X.
        elif k=="vt":
            u,v=map(float,s)
            color=32*u-.5
            index=round(color)
            assert 0<=index<32 and isclose(index,color,abs_tol=.0001) and v==.5
            tex.append(index)
        elif k=="vn":
            normals.append(tuple(map(float,s)))
        elif k=="f":
            assert len(s)==3, "triangulated engine mesh"
            corners=[tuple(map(int,item.split("/"))) for item in s]
            assert all(0<a<=len(vertices) and 0<b<=len(tex) and 0<c<=len(normals) for a,b,c in corners)
            swatches={tex[b-1] for _,b,_ in corners}
            assert len(swatches)==1
            faces.append((next(iter(swatches)),[a-1 for a,b,c in corners]))
        else:
            assert k not in ("usemtl","mtllib"), "one explicit runtime palette"
    assert 10_000<len(faces)<17_000
    assert len(vertices)>5_000
    return vertices,faces


def connected_faces(triangles, seed):
    by_vertex=defaultdict(list)
    for f,(_, corners) in enumerate(triangles):
        for p in corners:
            by_vertex[p].append(f)
    checked_faces=set()
    checked_verts=set()
    queue=[seed]
    for i in queue:
        if i in checked_verts:
            continue
        checked_verts.add(i)
        for f in by_vertex[i]:
            if f in checked_faces:
                continue
            checked_faces.add(f)
            queue.extend(triangles[f][1])
    return [triangles[f] for f in checked_faces]


def slice_at(hull,vertices,level):
    edges=[]
    for _,f in hull:
        poly=[vertices[k] for k in f]
        hits=[]
        for u,v in zip(poly,poly[1:]+poly[:1]):
            if (u[1]<level)!=(v[1]<level) and u[1]!=v[1]:
                t=(level-u[1])/(v[1]-u[1])
                hits.append((round(u[0]+t*(v[0]-u[0]),7),round(u[2]+t*(v[2]-u[2]),7)))
        if hits:
            assert len(hits)==2
            edges.append(hits)
    return edges


def main():
    assert (ROOT/"art/harbor_ferry.blend").stat().st_size>150_000
    img=(ROOT/"mods/luanttd_core/textures/bl_harbor_ferry_palette.png").read_bytes()
    assert img.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">II",img[16:24])==(256,8)
    vertices,faces=read()
    lo,hi=[tuple(fn(axis) for axis in zip(*vertices)) for fn in (min,max)]
    assert .74<hi[0]-lo[0]<.79
    assert 1.79<hi[2]-lo[2]<1.85
    assert -.190<lo[1]<-.175 and .88<hi[1]<.935
    hull=connected_faces(faces, min(range(len(vertices)),key=lambda i:vertices[i][1]))
    assert 350<len(hull)<415 # Connected shell alone, no cabin or propeller.
    edge_use=Counter(tuple(sorted((a,b))) for _,f in hull for a,b in zip(f,f[1:]+f[:1]))
    assert set(edge_use.values())=={2}, "submerged and dry shell must close"
    for colors, min_y, max_y in ((SHELL_DRAFT,-.19,-.007),({SHELL_BOOT},-.009,.009)):
        samples=[vertices[k] for sw,f in hull if sw in colors for k in f]
        assert samples
        assert all(min_y<=v[1]<=max_y for v in samples), "painted waterline height"
        if SHELL_BOOT in colors:
            assert min(v[1] for v in samples)<0<max(v[1] for v in samples)
    sea=slice_at(hull,vertices,0)
    n=Counter(v for edge in sea for v in edge)
    assert len(n)>45 and set(n.values())=={2}, "waterplane cuts a closed perimeter"
    wet_beam=max(k[0] for k in n)-min(k[0] for k in n)
    assert .66<wet_beam<.72 and wet_beam<hi[0]-lo[0]
    assert max(abs(x) for x,z in n if z<-.83)<.08, "tapered running bow is local -Z"
    # Source vessel values were independently verified from 14.1, not art:
    # https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h#L311
    # https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h#L575
    print("Ferry beam/length/draft/wet beam:",*(round(f,4) for f in
          (hi[0]-lo[0],hi[2]-lo[2],-lo[1],wet_beam)))
    print("PASS closed main hull, genuine water-plane cut, boot stripe/draft band, -Z bow, and editable source")


if __name__=="__main__":
    main()
