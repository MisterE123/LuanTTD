#!/usr/bin/env python3
"""Original low-poly travel interiors; +Z vehicle nose, 10 OBJ units/node."""
from math import sqrt
from pathlib import Path
import struct
import zlib

MOD = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
PALETTE = [(217,214,200),(188,191,183),(69,75,76),(160,74,53),
           (100,128,140),(53,83,102),(214,160,100),(224,204,150),
           (244,233,207),(111,76,56),(173,180,184),(52,96,89),
           (55,64,70),(161,194,196),(96,117,124),(244,238,214)]


def palette(dst):
    def chunk(t,s):
        return struct.pack(">I",len(s))+t+s+struct.pack(">I",zlib.crc32(t+s))
    rows=[b"\0"+bytes(v for x in range(32) for v in PALETTE[4*(3-y//2)+x//8])
          for y in range(8)]
    dst.write_bytes(b"\x89PNG\r\n\x1a\n"+
        chunk(b"IHDR",struct.pack(">IIBBBBB",32,8,8,2,0,0,0))+
        chunk(b"IDAT",zlib.compress(b"".join(rows),9))+chunk(b"IEND",b""))


class Room:
    def __init__(self):
        self.vertices={}; self.normals={}; self.faces=[]

    def face(self,points,paint):
        points=[tuple(round(x,6) for x in p) for p in points]
        a,b,c=points[:3]
        u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
        n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        l=sqrt(sum(x*x for x in n))
        n=tuple(round(x/l,7)+0.0 for x in n)
        normal=self.normals.setdefault(n,len(self.normals)+1)
        inds=[self.vertices.setdefault(p,len(self.vertices)+1) for p in points]
        for i in range(1,len(inds)-1):
            self.faces.append(tuple((a,paint+1,normal) for a in (inds[0],inds[i],inds[i+1])))

    def box(self,x0,x1,y0,y1,z0,z1,paint):
        a,b,c,d=(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)
        e,f,g,h=(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)
        for quad in ((a,b,c,d),(e,h,g,f),(a,e,f,b),(d,c,g,h),(a,d,h,e),(b,f,g,c)):
            self.face(quad,paint)

    def bench(self,x0,x1,z,paint,high):
        # Metal rails, separate cushion, back and tapered headrest.
        for x in (x0+.009,x1-.016):
            self.box(x,x+.007,.016,.066,z-.05,z+.030,2)
        self.box(x0,x1,.059,.087,z-.067,z+.061,paint)
        self.box(x0+.005,x1-.005,.082,high,z+.043,z+.065,paint)
        self.box(x0+.012,x1-.012,high-.027,high+.009,z+.034,z+.055,0)
        for x in (x0-.004,x1):
            self.box(x,x+.007,.115,.126,z-.050,z+.060,2)

    def write(self,stem):
        obj=["# Original LuanTTD ride interior. Real open windows, no alpha; +Z nose.",f"o {stem}"]
        obj.extend("v "+" ".join(f"{p*10:.5f}" for p in xyz) for xyz in self.vertices)
        obj.extend(f"vt {(i%4+.5)/4:.5f} {(i//4+.5)/4:.5f}" for i in range(len(PALETTE)))
        obj.extend("vn "+" ".join(f"{p:.7f}" for p in xyz) for xyz in self.normals)
        obj.extend("f "+" ".join("/".join(map(str,v)) for v in face) for face in self.faces)
        (MOD/"models"/f"{stem}.obj").write_text("\n".join(obj)+"\n")
        palette(MOD/"textures"/f"{stem}.png")


def air():
    R=Room(); width=.198; sill=.082; header=.270
    R.box(-width,width,-.010,.014,-.48,.54,12)
    R.box(-.050,.050,.014,.016,-.48,.54,4)
    # Ribbed liner, narrow luggage ledges and diffused overhead light.
    R.box(-.195,.195,.312,.326,-.48,.54,1)
    R.box(-.055,.055,.307,.316,-.47,.53,15)
    for side in (-1,1):
        def strip(inner,outer,y0,y1,z0,z1,c):
            x0,x1=sorted((inner*side,outer*side))
            R.box(x0,x1,y0,y1,z0,z1,c)
        strip(.188,width,.014,sill,-.48,.54,1)
        strip(.181,width,sill-.008,sill+.005,-.48,.54,10)
        strip(.188,width,header,.315,-.48,.54,0)
        strip(.160,.189,.272,.304,-.48,.54,0)
        for z in (-.48,-.27,-.09,.245,.426,.526):
            strip(.188,width,sill,header,z,z+.014,0)
            # Chamfer the two near corners of each window rather than using a flat texture.
            for s in (z-.006,z+.014):
                strip(.188,width,sill,sill+.017,s,s+.010,0)
                strip(.188,width,header-.017,header,s,s+.010,0)
        for z in (-.38,.37):
            for a,b in ((.062,.119),(.125,.177)):
                x0,x1=sorted((a*side,b*side))
                R.bench(x0,x1,z,5,.184)
    R.box(-width,-.055,.016,.314,-.49,-.48,0)
    R.box(.055,width,.016,.314,-.49,-.48,0)
    R.box(-width,-.055,.016,.314,.53,.54,0)
    R.box(.055,width,.016,.314,.53,.54,0)
    R.box(-.053,.053,.065,.312,.535,.542,14)
    R.box(-.025,.025,.231,.245,.529,.535,7)
    return R


def ferry():
    R=Room(); width=.260; sill=.100; header=.285
    R.box(-width,width,-.005,.015,-.50,.68,10)
    for z in (-.46,-.37,-.28,-.19,-.10,-.01,.08,.17,.26,.35,.44,.53,.62):
        R.box(-width,width,.014,.016,z,z+.004,14)
    R.box(-.254,.254,.315,.328,-.43,.42,0)
    R.box(-.047,.047,.309,.319,-.40,.41,15)
    for side in (-1,1):
        def strip(inner,outer,y0,y1,z0,z1,c):
            x0,x1=sorted((inner*side,outer*side))
            R.box(x0,x1,y0,y1,z0,z1,c)
        strip(.246,width,.016,sill,-.50,.43,11)
        strip(.236,width,sill-.005,sill+.009,-.50,.43,9)
        strip(.246,width,header,.319,-.43,.43,0)
        for z in (-.44,-.23,.235,.412):
            strip(.245,width,sill,header,z,z+.018,0)
        for z in (-.36,.37):
            x0,x1=sorted((side*.095,side*.232))
            R.bench(x0,x1,z,4,.148)
        # Exterior bow rail remains visibly separated into bars and posts.
        strip(.243,.254,.127,.140,.43,.68,7)
        strip(.243,.250,.067,.074,.43,.68,10)
        for z in (.43,.55,.667):
            strip(.241,.255,.018,.143,z,z+.010,10)
    for z in (-.43,.418):
        R.box(-width,width,.017,.091,z,z+.013,11)
        R.box(-width,width,.282,.319,z,z+.013,0)
        for x in (-.252,-.080,.079,.241):
            R.box(x,x+.012,.091,.283,z,z+.013,0)
    R.box(-.245,.245,.128,.140,.668,.680,7)
    R.box(-.247,.247,.071,.077,.669,.678,10)
    for x in (-.241,0,.231):
        R.box(x,x+.011,.015,.141,.669,.678,10)
    return R


if __name__=="__main__":
    air().write("bl_ride_airliner_interior")
    ferry().write("bl_ride_ferry_interior")
