#!/usr/bin/env python3
"""Original compact GA taildragger for the fixed-wing hangar's static slot."""
from math import pi,cos,sin
from pathlib import Path
from struct import pack
from zlib import compress,crc32
import sys

mod=Path(__file__).resolve().parents[1]/"mods/luanttd_core"
palette=((244,207,115),(247,228,170),(189,117,61),(48,76,90),(88,121,137),
         (52,61,59),(33,38,38),(145,154,149),(138,73,51),(245,233,200))
verts,faces=[],[]

def face(points,color):
    ids=[]
    for x,y,z in points:
        coord=(-x+.055,y-.491,z+.42)
        q=tuple(round(k,4) for k in coord)
        if q not in verts:verts.append(q)
        ids.append(verts.index(q)+1)
    faces.append("f "+" ".join(f"{i}/{color+1}" for i in ids))
def poly(p,sections,color):
    for i in range(len(sections)-1):
        a,b=sections[i:i+2]
        assert len(a)==len(b)
        for j in range(len(a)):
            k=(j+1)%len(a)
            c=color(p,i,j) if callable(color) else color
            face((a[j],a[k],b[k],b[j]),c)
def radial(y,z,rx,ry,n=8):
    return [(cos(i*2*pi/n)*rx,y+sin(i*2*pi/n)*ry,z) for i in range(n)]
def cuboid(x,y,z,u,v,w,c):
    a=[(x,y,z),(u,y,z),(u,v,z),(x,v,z)]
    b=[(x,y,w),(u,y,w),(u,v,w),(x,v,w)]
    poly("",[a,b],c);face(a,c);face(b[::-1],c)

# Tapered aft body, stout two-seat cabin and separate cowling with spinner.
poly("body",[radial(.107,z,rx,ry) for z,rx,ry in ((-.39,.018,.022),(-.29,.043,.046),
      (-.12,.077,.071),(.07,.083,.070),(.19,.073,.064),(.28,.062,.052),(.315,.044,.039))],
      lambda _,i,j: 0 if j<4 else (2 if j in (4,7) else 1))
poly("spinner",[radial(.108,z,rx,ry) for z,rx,ry in ((.314,.032,.032),(.342,.022,.022),(.352,.001,.001))],7)
# Faceted cabin with window trim and tapered rear quarterlights.
cabin=[(-.063,.154,.132),(.063,.154,.132),(.063,.212,.071),(-.063,.212,.071)]
face(cabin,4)
for s in (-1,1):
    face([(s*.064,.145,.12),(s*.062,.211,.071),(s*.062,.207,-.074),(s*.066,.161,-.104)],9)
    for z,w,c in ((.104,.055,4),(.039,-.058,3)):
        face([(s*.065,.158,z),(s*.064,.199,min(.065,z)),(s*.064,.199,w),(s*.066,.162,w)],c)
face([(-.064,.210,.073),(.064,.210,.073),(.065,.204,-.087),(-.065,.204,-.087)],0)
# Proper tapered high wing with raised tips and contrasting undersides.
for d in (-1,1):
    def wing(x,y,front,back):
        return [(d*x,y,front),(d*x,y+.014,(front+back)/2),(d*x,y,back),(d*x,y-.009,(front+back)/2)]
    poly("wing",[wing(0,.222,.102,-.105),wing(.230,.23,.093,-.086),
          wing(.304,.241,.066,-.049),wing(.323,.241,.05,-.031)],lambda _,i,j:2 if i==2 else (1 if j<2 else 0))
    face(wing(.323,.241,.05,-.031),2)
    # Visible wing struts and flap seam.
    face([(d*.048,.115,.091),(d*.062,.115,.095),(d*.224,.228,.029),(d*.210,.228,.03)],7)
    face([(d*.076,.224,-.073),(d*.232,.233,-.068),(d*.231,.232,-.08),(d*.075,.224,-.087)],2)
    poly("tailplane",[wing(0,.133,-.274,-.391),wing(.117,.135,-.313,-.396)],0)
face([(-.006,.134,-.291),(-.006,.236,-.343),(-.006,.229,-.387),(-.006,.125,-.400)],2)
face([(.006,.134,-.291),(.006,.236,-.343),(.006,.229,-.387),(.006,.125,-.400)],0)
# Treaded mains, hub caps, tailwheel and static two-blade prop.
for x,y,z,r,w in ((-.106,.038,.086,.038,.023),(.106,.038,.086,.038,.023),(0,.019,-.334,.019,.015)):
    def wheel(x,r):return [(x,y+r*sin(i*pi/6),z+r*cos(i*pi/6)) for i in range(12)]
    a,b=wheel(x-w,r),wheel(x+w,r);poly("",[a,b],6);face(a,5);face(b,5)
    face(wheel(x+w+.001,r*.42),7)
    face([(x,.045,z),(x,.046,z-.012),(x*.54,.13,z+.013),(x*.52,.13,z+.025)],7)
face([(-.015,.003,.346),(.009,.007,.346),(.014,.106,.344),(-.011,.12,.344)],5)
face([(-.009,.099,.344),(.013,.113,.344),(.017,.207,.346),(-.007,.214,.346)],5)
face([(-.007,.196,.347),(.015,.194,.347),(.017,.207,.347),(-.006,.214,.347)],8)

# The country asphalt follows the stock taxi stripe; its offset hitch
# pad gives the small aircraft a hardstand instead of parking in grass.
face([(-.329,.012,-.42),(.329,.012,-.42),(.329,.012,.379),(-.329,.012,.379)],5)
for x in (-.309,.309):
    face([(x-.006,.013,-.38),(x+.006,.013,-.38),(x+.006,.013,.34),(x-.006,.013,.34)],7)

def png():
    def c(t,d):return pack(">I",len(d))+t+d+pack(">I",crc32(t+d))
    row=b"\0"+b"".join(bytes(rgb)*8 for rgb in palette)
    return (b"\x89PNG\r\n\x1a\n"+c(b"IHDR",pack(">IIBBBBB",len(palette)*8,8,8,2,0,0,0))
        +c(b"IDAT",compress(row*8))+c(b"IEND",b""))

header=["# Original LuanTTD GA hangar taildragger; tools/build_hangar_ga.py","o hangar_sport_cabin"]
header.extend(f"vt {(i+.5)/len(palette):.3f} .5" for i in range(len(palette)))
header.extend(f"v {x:.4f} {y:.4f} {z:.4f}" for x,y,z in verts)
obj=("\n".join(header+faces)+"\n").encode()
assert len(obj)<15000 and len(faces)<250
for p,data in ((mod/'models'/'bl_hangar_ga.obj',obj),(mod/'textures'/'bl_hangar_ga_atlas.png',png())):
    if "--check" in sys.argv:assert p.read_bytes()==data,p
    else:p.with_suffix(".tmp").write_bytes(data);p.with_suffix(".tmp").replace(p)
print(f"{len(verts)} vertices, {len(faces)} faces, {len(obj)} OBJ bytes")
