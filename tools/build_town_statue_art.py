#!/usr/bin/env python3
"""Create the original bronze civic statue, cut-stone plinth and palette."""
from argparse import ArgumentParser
from math import cos, sin, atan2, pi, sqrt
from pathlib import Path

from PIL import Image

parser = ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
check = parser.parse_args().check
root = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
palette = [
    (55, 63, 63), (94, 105, 103), (136, 144, 135), (178, 184, 166),
    (42, 65, 61), (59, 88, 76), (83, 115, 93), (125, 142, 106),
    (110, 77, 45), (184, 149, 83), (86, 95, 88), (154, 165, 150),
]
image = Image.new("RGB", (len(palette)*8,16))
for i, rgb in enumerate(palette):
    image.paste(rgb,(i*8,0,(i+1)*8,16))
texture = root / "textures/bl_stock_town_statue.png"
if check:
    assert Image.open(texture).convert("RGB").tobytes() == image.tobytes()
else:
    image.save(texture,optimize=True)

obj = ["# Original cast-bronze civic monument, tools/build_town_statue_art.py"]
obj += [f"vt {(i+.5)/len(palette):.6f} .5" for i in range(len(palette))]
vertices = []
parts = []
def point(x, y, z):
    vertices.append((-.5-x,y-.5,.5+z))
    return len(vertices)

def face(ids, index):
    parts.append("f "+" ".join(f"{i}/{index+1}" for i in ids))

def shape(rings, sides, phase, colors):
    ids = []
    for x,y,z,rx,rz in rings:
        ids.append([point(x+rx*cos(phase+2*pi*i/sides),y,z+rz*sin(phase+2*pi*i/sides)) for i in range(sides)])
    face(ids[0][::-1],colors[0])
    for row,(below,above) in enumerate(zip(ids,ids[1:])):
        for j in range(sides):
            k=(j+1)%sides
            face((below[j],below[k],above[k],above[j]),colors[min(row,len(colors)-1)])
    face(ids[-1],colors[-1])

def octagon(y,w):
    return (0,y,0,w,w)
# Three beveled footings, tapered granite shaft, dark shadow course and cap.
shape([octagon(y,w) for y,w in
       [(0,.91),(.06,.91),(.12,.84),(.17,.79),(.23,.79),(.27,.68),(.29,.62),
        (.70,.58),(.74,.66),(.80,.70),(.86,.66),(.88,.57)]],
      8,pi/8,[0,1,3,2,1,2,2,0,1,3,2])
# Raised bronze plaque on front and back, with three inset lettering bands.
for side in (-1,1):
    for z0,h,x,w,c in [(.553,.51,0,.215,8),(.567,.51,0,.194,9)]:
        z=side*z0
        f=[point(x-w,h-.11,z),point(x+w,h-.11,z),point(x+w,h+.11,z),point(x-w,h+.11,z)]
        face(f if side>0 else f[::-1],c)
    for i,width in enumerate((.108,.138,.082)):
        y=.565-i*.05;z=side*.571
        f=[point(-width,y-.008,z),point(width,y-.008,z),point(width,y+.008,z),point(-width,y+.008,z)]
        face(f if side>0 else f[::-1],0)
parts.append("g bronze_figure")
# Feet, practical railway trousers, waistcoat and jacket. All dimensions
# are measured from the plinth cap, not from a posed character stock mesh.
for x in (-.134,.134):
    shape([(x,.872,-.056,.104,.137),(x,.927,-.083,.105,.149),(x,.973,-.045,.08,.10)],
          8,pi/8,[4,5,6])
    shape([(x,.94,.005,.081,.087),(x*.92,1.205,.012,.102,.102),(x*.83,1.45,.015,.116,.107)],
          9,0,[4,5,6])
shape([(0,1.44,.015,.215,.132),(0,1.57,0,.205,.138),(0,1.78,-.01,.26,.145),
       (0,1.88,.003,.222,.123),(0,1.917,.006,.08,.083)],12,pi/12,[5,6,5,6,4])
# Sleeves and hands with real diagonals at shoulder and elbow rather than a T-pose.
def limb(path,radii):
    n=9; rows=[]
    for (x,y,z),r in zip(path,radii):
        angle=atan2(path[-1][1]-path[0][1],path[-1][0]-path[0][0])
        rows.append([point(x-r*sin(angle)*cos(j*2*pi/n),y+r*cos(angle)*cos(j*2*pi/n),
                           z+r*sin(j*2*pi/n)) for j in range(n)])
    for i in range(len(rows)-1):
        for j in range(n):
            k=(j+1)%n
            face((rows[i][j],rows[i][k],rows[i+1][k],rows[i+1][j]),5+(i%2))
    face(rows[-1],6)
limb([(-.212,1.824,0),(-.302,1.664,-.013),(-.267,1.487,-.034),(-.241,1.431,-.059)],
     [.102,.091,.064,.064])
limb([(.216,1.821,0),(.352,1.746,-.061),(.393,1.845,-.111),(.433,1.935,-.133)],
     [.102,.081,.062,.069])
shape([(0,1.889,.004,.067,.07),(0,1.952,.007,.071,.069),
       (0,1.982,-.019,.093,.08),(0,2.064,-.014,.124,.109),
       (0,2.139,-.01,.121,.111),(0,2.169,-.012,.105,.098)],
      11,0,[4,6,6,7,6,5])
# Brow/nose, jacket lapels, cap peak and alternating lapel metal.
shape([(0,2.038,-.095,.025,.025),(0,2.071,-.113,.027,.038),(0,2.113,-.087,.029,.022)],
      8,0,[5,7,6])
shape([(0,2.141,-.036,.155,.15),(0,2.172,-.023,.156,.132),
       (0,2.205,-.012,.127,.108)],12,pi/12,[4,6,5])
for side in (-1,1):
    verts=[point(side*.072,1.912,-.095),point(side*.149,1.802,-.137),
           point(side*.045,1.622,-.154),point(side*.037,1.817,-.14)]
    face(verts if side>0 else verts[::-1],7)
obj += ["v %.5f %.5f %.5f"%v for v in vertices] + parts
result = "\n".join(obj)+"\n"
path = root / "models/bl_stock_town_statue.obj"
if check:
    assert path.read_text()==result
else:
    path.write_text(result)
print("PASS original granite plinth and bronze civic monument asset")
