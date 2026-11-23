"""Generate the original two-door sightseeing car mesh and flat UV palette."""
from pathlib import Path
from math import cos, pi, sin
from struct import pack
from zlib import crc32, compress

root = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core"
colors = [
    (179, 42, 35), (213, 58, 46), (154, 40, 31), (33, 53, 61),
    (65, 110, 117), (20, 23, 24), (117, 124, 126), (211, 215, 212),
    (255, 226, 153), (145, 24, 23), (46, 55, 60), (65, 72, 71),
]
vertices, polygons = [], []
def face(points, color):
    vertices.extend(points)
    polygons.append((list(range(len(vertices)-len(points)+1, len(vertices)+1)), color))

def loft(rings, upper, lower, ends):
    """Rings consist of a clockwise profile viewed from the nose."""
    face(rings[0][::-1], ends[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(len(a)):
            n = (i+1) % len(a)
            face([a[i], a[n], b[n], b[i]], upper if i in (2, 3, 4) else lower)
    face(rings[-1], ends[1])

def section(z, w, h, bottom=.55, taper=.18):
    return [(-w+taper,bottom,z),(w-taper,bottom,z),(w,bottom+.2,z),
            (w,h-.2,z),(w-taper,h,z),(-w+taper,h,z),(-w,h-.2,z),(-w,bottom+.2,z)]

def prism(xa, xb, ya, yb, za, zb, color):
    v = [(x,y,z) for z in (za,zb) for y in (ya,yb) for x in (xa,xb)]
    for indices in ((1,0,2,3),(4,5,7,6),(0,4,6,2),(5,1,3,7),(2,6,7,3),(5,4,0,1)):
        face([v[i] for i in indices],color)

loft([section(-3.30,1.05,1.53),section(-3.03,1.21,1.72),
      section(-2.03,1.27,1.74),section(1.77,1.26,1.69),
      section(3.18,1.12,1.51),section(3.37,.91,1.3)], 1, 0, (2, 2))
# Roof pillars and sloped windshields, windshield surround, seat backs.
a = [(-1.07,1.72,-1.88),(1.07,1.72,-1.88),(1.08,1.68,1.99),(-1.08,1.68,1.99)]
b = [(-.81,2.82,-1.38),(.81,2.82,-1.38),(.78,2.84,.61),(-.78,2.84,.61)]
face(b[::-1],1)
for i in range(4):
    j=(i+1)%4
    face([a[i],a[j],b[j],b[i]],0)
    def blend(p,q,t): return tuple(x+t*(y-x) for x,y in zip(p,q))
    low_a, low_b = blend(a[i],b[i],.12), blend(a[j],b[j],.12)
    top_a, top_b = blend(a[i],b[i],.88), blend(a[j],b[j],.88)
    pts=[blend(low_a,low_b,.05),blend(low_b,low_a,.05),
         blend(top_b,top_a,.05),blend(top_a,top_b,.05)]
    push=((0,0,-.012),(.016,0,0),(0,0,.02),(-.016,0,0))[i]
    face([tuple(v+d for v,d in zip(p,push)) for p in pts],4 if i==2 else 3)
for x in (-1, 1):
    for z in (-2.13, 2.02):
        f=lambda xa,r,i:(x*xa,.56+r*sin(i*pi/6),z+r*cos(i*pi/6))
        for i in range(12):
            j=(i+1)%12
            quad=[f(1.28,.55,i),f(1.28,.55,j),f(.99,.55,j),f(.99,.55,i)]
            face(quad if x==1 else quad[::-1],5)
            for r1,r2,color in ((.55,.29,5),(.29,.13,6),(.13,0,7)):
                quad=[f(1.283,r1,i),f(1.283,r2,i),f(1.283,r2,j),f(1.283,r1,j)]
                face(quad if x==1 else quad[::-1],color)
    low,high = sorted((x*.56,x*.95))
    prism(low,high,.94,1.22,3.29,3.43,8)
    prism(low,high,.92,1.14,-3.36,-3.29,9)
    low,high = sorted((x*1.215,x*1.285))
    prism(low,high,1.42,1.49,-.83,-.55,7) # handles
    low,high = sorted((x*1.20,x*1.48))
    prism(low,high,1.72,1.88,1.36,1.59,10) # mirrors
prism(-1.02,1.02,.70,.81,3.29,3.43,7)
prism(-1.14,1.14,.68,.82,-3.40,-3.24,7)
prism(-.55,.55,.89,1.12,3.365,3.435,10)
for x in (-.43,-.215,0,.215,.43):
    prism(x-.014,x+.014,.89,1.12,3.432,3.44,6)

obj = ["# Original LuanTTD sightseeing hatchback. +Z nose; 10 OBJ units/node.",
       "o LuanTTD_Sightseeing_Car"]
obj += ["v %.5f %.5f %.5f" % v for v in vertices]
obj += ["vt %.6f .5" % ((i+.5)/16) for i in range(len(colors))]
obj += ["f "+" ".join(f"{i}/{col+1}" for i in indices) for indices,col in polygons]
(root/"models/bl_sightseeing_car.obj").write_text("\n".join(obj)+"\n")
def chunk(kind, data):
    return pack("!I",len(data))+kind+data+pack("!I",crc32(kind+data)&0xffffffff)
pixels=b"".join(bytes(rgb)*8 for rgb in colors+[(0,0,0)]*(16-len(colors)))
png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",pack("!IIBBBBB",128,8,8,2,0,0,0))
png+=chunk(b"IDAT",compress((b"\0"+pixels)*8,9))+chunk(b"IEND",b"")
(root/"textures/bl_sightseeing_car_palette.png").write_bytes(png)
