"""Verify the authentic early-passenger art's native export and axle datum."""

from collections import Counter, defaultdict
from math import hypot, isclose
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
WOOD_PROPELLER={20,21,22}
PORT_LIGHT=25
STARBOARD_LIGHT=26


def model():
    p=ROOT/"mods/bayline/models/bl_bayshore_trimotor.obj"
    verts, tex, normal, faces = [], [], [], []
    for line in p.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        k,*v=line.split()
        if k=="v":
            x,y,z=map(float,v)
            # Native mesh objects take 10 OBJ units per Luanti node,
            # and the Irrlicht OBJ importer mirrors X.
            verts.append((-x/10,y/10,z/10))
        elif k=="vt":
            u,v=map(float,v)
            swatch=32*u-.5
            assert v==.5 and 0<=round(swatch)<32 and isclose(swatch,round(swatch),abs_tol=.0001)
            tex.append(round(swatch))
        elif k=="vn":
            normal.append(tuple(map(float,v)))
        elif k=="f":
            assert len(v)==3, "export Linux-native triangulated mesh"
            inds=[tuple(map(int,n.split("/"))) for n in v]
            assert all(0<i<=len(verts) and 0<j<=len(tex) and 0<h<=len(normal) for i,j,h in inds)
            colors={tex[j-1] for _,j,_ in inds}
            assert len(colors)==1, "one color swatch per face"
            faces.append((next(iter(colors)),tuple(i-1 for i,j,h in inds)))
        else:
            assert k not in ("usemtl","mtllib"), "no third-party or split materials"
    assert len(verts)>8000 and 12_000<len(faces)<16_000
    return verts,faces


def groups(faces):
    incident=defaultdict(list)
    for i,(_,fs) in enumerate(faces):
        for j in fs:
            incident[j].append(i)
    seen=set()
    for i,(_,face) in enumerate(faces):
        if i in seen:
            continue
        queue=[i]
        seen.add(i)
        output=[]
        points=set()
        for f in queue:
            output.append(faces[f][1])
            for k in faces[f][1]:
                if k not in points:
                    points.add(k)
                    for f2 in incident[k]:
                        if f2 not in seen:
                            seen.add(f2)
                            queue.append(f2)
        yield points,output


def bounded_rotating():
    verts,faces=model()
    lo,hi=[tuple(fn(axis) for axis in zip(*verts)) for fn in (min,max)]
    assert 1.95<hi[0]-lo[0]<1.98 and isclose(lo[0],-hi[0],abs_tol=.00001)
    assert 1.76<hi[2]-lo[2]<1.80 and abs(.5*(lo[2]+hi[2]))<.004
    assert isclose(lo[1],0) and .65<hi[1]<.69
    swept=max(hypot(x,z) for x,y,z in verts)
    assert swept<.99, "spinning on its spot should stay inside a centered two-node apron square"

    # Both main wheels and the smaller tail wheel contact runway y=0.
    patch=[(x,z) for x,y,z in verts if y<=.00001]
    assert patch
    positive=[(x,z) for x,z in patch if x>.32]
    negative=[(x,z) for x,z in patch if x<-.32]
    tail=[(x,z) for x,z in patch if abs(x)<.025]
    for foot in (positive,negative):
        assert len(foot)>1 and all(-.120<z<-.115 for _,z in foot)
    assert len(tail)>1 and all(.746<z<.751 for _,z in tail)
    assert len(positive)+len(negative)+len(tail)==len(patch)

    # Three independently authored wood propellers, six connected blade meshes.
    blades=list(groups([f for f in faces if f[0] in WOOD_PROPELLER]))
    assert len(blades)==6 and all(len(points)==24 for points,_ in blades)
    n=Counter()
    for pts,blade in blades:
        assert len(blade)>35 and all(verts[i][1]>.14 for i in pts)
        xc=sum(verts[i][0] for i in pts)/len(pts)
        zc=sum(verts[i][2] for i in pts)/len(pts)
        kind=round((xc+.43)/.43)
        assert kind in (0,1,2)
        if kind==1:
            assert -.884<zc<-.835, "center engine and its propeller face local -Z"
        else:
            assert -.54<zc<-.47
        n[kind]+=1
    assert sorted(n.values())==[2,2,2]

    # Both main wing surfaces are watertight shells, not a painted flat plane.
    wings=[]
    for pts,fs in groups(faces):
        xs,ys,zs=zip(*(verts[i] for i in pts))
        if max(xs)-min(xs)>.90 and (max(xs)>.96 or min(xs)<-.96) and len(fs)>140:
            count=Counter(tuple(sorted((a,b))) for f in fs for a,b in zip(f,f[1:]+f[:1]))
            assert set(count.values())=={2}
            assert max(ys)-min(ys)>.065 and max(zs)-min(zs)>.72
            wings.append(.5*(max(xs)+min(xs)))
    assert len(wings)==2 and min(wings)<-.49 and max(wings)>.49

    for swatch, sign in ((PORT_LIGHT,1),(STARBOARD_LIGHT,-1)):
        lamps=[verts[i] for color,tri in faces for i in tri if color==swatch]
        assert lamps and all(sign*x>.94 for x,_,_ in lamps)
    print("Trimotor wingspan/length/height/yaw radius:",
          *(round(n,4) for n in (hi[0]-lo[0],hi[2]-lo[2],hi[1],swept)))
    print("PASS centered on taxi tile, all three wheels grounded, three paired -Z props, closed splayed wings, port and starboard lights")


if __name__=="__main__":
    # Reference data (not artwork): 14.1 src/table/engines.h rows 320/610:
    # https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h#L320
    # https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h#L610
    assert (ROOT/"art/bayshore_trimotor.blend").stat().st_size>150_000
    a=(ROOT/"mods/bayline/textures/bl_bayshore_trimotor_palette.png").read_bytes()
    assert a.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">II",a[16:24])==(256,8)
    bounded_rotating()
