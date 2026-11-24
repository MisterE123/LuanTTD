#!/usr/bin/env python3
"""Build the native quarter-cell arched interiors; geometry stays inside its own tile."""
from math import sin, cos, pi
from pathlib import Path
from random import Random
from struct import pack
from zlib import compress, crc32

ROOT = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core"
PROFILE = {"road": (.422, .383, .270), "rail": (.487, .593, .308)}


def png(name, sample):
    def chunk(tag, data):
        body = tag + data
        return pack(">I", len(data)) + body + pack(">I", crc32(body))
    rows = b"".join(b"\0" + bytes(value for x in range(64) for value in sample(x,y)) for y in range(64))
    (ROOT/"textures"/(name+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
        chunk(b"IHDR",pack(">IIBBBBB",64,64,8,2,0,0,0))+chunk(b"IDAT",compress(rows,9))+chunk(b"IEND",b""))


class Mesh:
    def __init__(self):
        self.out = ["# Native tunnel geometry: tools/build_tunnel_bores.py"]
        self.count = 0

    def group(self, name):
        # Luanti uses OBJ groups in order as separate node tile slots.
        self.out.append("g "+name)

    def face(self, p, uv, normal):
        a,b,c = p[:3]
        e=[b[i]-a[i] for i in range(3)]
        f=[c[i]-a[i] for i in range(3)]
        cross=(e[1]*f[2]-e[2]*f[1],e[2]*f[0]-e[0]*f[2],e[0]*f[1]-e[1]*f[0])
        if sum(me*want for me,want in zip(cross,normal))<0:
            p=p[::-1]
            uv=uv[::-1]
        # OBJ meshes use the reflected X coordinate. Reverse indices too.
        p=p[::-1]
        uv=uv[::-1]
        n=len(p)
        for x,y,z in p:
            self.out.append(f"v {-x:.7f} {y:.7f} {z:.7f}")
        for u,v in uv:
            self.out.append(f"vt {u:.7f} {1-v:.7f}")
        ids=[self.count+i+1 for i in range(n)]
        for k in range(1,n-1):
            self.out.append("f "+" ".join(f"{i}/{i}" for i in (ids[0],ids[k],ids[k+1])))
        self.count+=n

    def save(self,name):
        (ROOT/"models"/(name+".obj")).write_text("\n".join(self.out)+"\n")


UV = ((0,0),(0,1),(1,1),(1,0))
TOP_UV = ((0,1),(0,0),(1,0),(1,1))


def side_mesh(mode, axis, half, open_top, lamp=False):
    width, spring, rise = PROFILE[mode]
    # Crosswise distance from the physical seam: positive toward the
    # outside of the tile. The ceiling is a true segmental vault.
    sign = -1 if half==0 else 1
    def world(length,y,cross):
        lat=sign*(cross-.5)
        return (length,y,lat) if axis==0 else (lat,y,length)
    def n(length,y,cross):
        return (length,y,sign*cross) if axis==0 else (sign*cross,y,length)
    m=Mesh()
    if not open_top:
        m.group("ground_surface")
        top=[(-.5,.5,-.5),(-.5,.5,.5),(.5,.5,.5),(.5,.5,-.5)]
        m.face(top,TOP_UV,(0,1,0))
    m.group("ground_side")
    m.face([world(a,b,1) for a,b in ((-.5,-.5),(-.5,.5),(.5,.5),(.5,-.5))],UV,n(0,0,1))
    m.group("lining")
    m.face([world(a,b,width) for a,b in ((-.5,-.5),(-.5,spring-.5),(.5,spring-.5),(.5,-.5))],
           ((0,1),(0,1-spring),(1,1-spring),(1,1)),n(0,0,-1))
    steps=10
    for i in range(steps):
        a,b=i*pi/2/steps,(i+1)*pi/2/steps
        u,v=width*cos(a),width*cos(b)
        h,g=spring+rise*sin(a)-.5,spring+rise*sin(b)-.5
        m.face([world(p,y,c) for p,y,c in ((-.5,h,u),(-.5,g,v),(.5,g,v),(.5,h,u))],
               ((0,.65-i*.055),(0,.65-(i+1)*.055),(1,.65-(i+1)*.055),(1,.65-i*.055)),
               n(0,-sin(b),-cos(b)))
    if lamp:
        # Bracketed wall luminaire. The solid enclosure is on the outer
        # edge of the vault; the existing tunnel collision stays unchanged.
        y=spring-.57
        a,b,c,d=-.15,.15,y-.039,y+.039
        inner,outer=width-.031,width+.008
        m.group("lamp_housing")
        m.face([world(p,h,inner) for p,h in ((a,c),(a,d),(b,d),(b,c))],UV,n(0,0,-1))
        for h,direction in ((c,-1),(d,1)):
            m.face([world(p,h,s) for p,s in ((a,inner),(a,outer),(b,outer),(b,inner))],UV,n(0,direction,0))
        for p,direction in ((a,-1),(b,1)):
            m.face([world(p,h,s) for h,s in ((c,inner),(d,inner),(d,outer),(c,outer))],UV,n(direction,0,0))
        m.group("lamp_lens")
        m.face([world(p,h,inner-.001) for p,h in ((a+.026,c+.014),(a+.026,d-.014),
                    (b-.026,d-.014),(b-.026,c+.014))],UV,n(0,0,-1))
    return m


def floor_pixel(mode,axis,side,lit=False):
    def pixel(x,y):
        cross,long=(63-y,x) if axis==0 else (x,63-y)
        distance=(side+1)*64-cross if side==0 else cross+1
        # Two halves share the centreline. Render raised rail profile as
        # a separate mesh slot; this texture is the sleepers and subbase.
        tone=((x*19+y*49+x*y*7)%23)-11
        # Warm pools fade to zero at the longitudinal unit boundaries.
        across=(64-distance) if side==0 else (64+distance)
        glow=sin(pi*(long+.5)/64)**2*max(0,1-across/118)**1.7 if lit else 0
        shade=lambda r,g,b:tuple(max(0,min(255,int(c+tone+glow*light)))
                                for c,light in zip((r,g,b),(80,55,28)))
        if mode=="road":
            if distance<=3 and 13<long<=45:return shade(186,169,115)
            if distance in range(21,24):return shade(146,140,120)
            if distance>24:return shade(62,59,53)
            return shade(76,79,81)
        if distance<26 and long%16 in range(3,9):return shade(100,76,56)
        return shade(84,82,72)
    return pixel


def rail_floor(axis,side):
    m=Mesh()
    m.group("track_bed")
    m.face([(-.5,.50,-.5),(-.5,.50,.5),(.5,.50,.5),(.5,.50,-.5)],TOP_UV,(0,1,0))
    m.group("railhead")
    lat=(-1 if side==0 else 1)*(.211-.5)
    def world(a,b,c):
        return (a,b,c) if axis==0 else (c,b,a)
    for high,wide in ((.552,.025),(.534,.016)):
        m.face([world(a,high,c) for a,c in ((-.5,lat-wide),(-.5,lat+wide),(.5,lat+wide),(.5,lat-wide))],
               UV,(0,1,0))
    for off in (-.025,.025):
        m.face([world(a,b,lat+off) for a,b in ((-.5,.522),(-.5,.552),(.5,.552),(.5,.522))],
               UV, (0,0,off) if axis==0 else (off,0,0))
    return m


def brick(x,y):
    col=(x+(y//8%2)*8)%16
    if y%8==0 or col==0:
        return (62,57,53)
    phase=((x+(y//8%2)*8)//16*29+y//8*19)%27
    grain=((x*19+y*49+x*y)%11)
    return (103+phase+grain,80+phase+grain,64+phase+grain)

def lit_brick(x,y):
    heat=sin(pi*(x+.5)/64)**3*max(0,1-abs(y-46)/32)
    return tuple(min(255,int(c+heat*d)) for c,d in zip(brick(x,y),(86,63,30)))

def lens(x,y):
    if x in (0,1,62,63) or y in (0,1,62,63):
        return (173,131,74)
    if x%8==0:
        return (221,181,105)
    return (255,245-y//6,199-y//3)


if __name__=="__main__":
    png("bl_tunnel_lining_brick", brick)
    png("bl_tunnel_lining_brick_lit", lit_brick)
    png("bl_tunnel_lamp_housing", lambda x,y: (67+y//6,64+y//6,58+y//6))
    png("bl_tunnel_lamp_lens", lens)
    for mode in PROFILE:
        for axis in (0,1):
            for half in (0,1):
                for opened in (False,True):
                    name=f"bl_tunnel_bore_{mode}_{axis}_{half}_{int(opened)}"
                    side_mesh(mode,axis,half,opened).save(name)
                    if half==0:
                        side_mesh(mode,axis,half,opened,True).save(name+"_lamp")
                png(f"bl_tunnel_floor_{mode}_{axis}_{half}",floor_pixel(mode,axis,half))
                png(f"bl_tunnel_floor_{mode}_{axis}_{half}_lit",floor_pixel(mode,axis,half,True))
                if mode=="rail":
                    rail_floor(axis,half).save(f"bl_tunnel_track_{axis}_{half}")
