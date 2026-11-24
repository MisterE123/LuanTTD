#!/usr/bin/env python3
"""Generate the original field growth meshes; OBJs are directly Blender-importable.
Tile detail is colocated with the 64px ground texture, not a new simulation.
"""
from pathlib import Path
from math import cos, sin, pi
from random import Random
from struct import pack
from zlib import compress, crc32
import sys

MOD=Path(__file__).resolve().parents[1]/'mods/luanttd_core'
PALETTE=((52,91,36),(94,134,48),(121,151,59),(88,114,32),
         (144,151,56),(155,132,50),(186,153,52),(218,180,76),
         (169,123,53),(210,153,68),(118,78,34),(177,137,65))
PHASE={
    2: (.090,0,2), 3: (.175,1,3), 4: (.255,2,3),
    5: (.385,4,3), 6: (.445,5,4), 7: (.074,8,2)
}
def png():
    def chunk(tag,body):
        return pack('>I',len(body))+tag+body+pack('>I',crc32(tag+body))
    pix=b''.join(bytes(c)*8 for c in PALETTE)
    return (b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',pack('>IIBBBBB',len(PALETTE)*8,8,8,2,0,0,0))
            +chunk(b'IDAT',compress((b'\x00'+pix)*8))+chunk(b'IEND',b''))
def mesh(phase,patch=False,lite=False):
    root=-.43 if patch else -.012
    vertices,faces=[],[]
    def face(points,color):
        i=len(vertices)
        vertices.extend(points)
        faces.append('f '+' '.join(f'{i+j+1}/{color+1}' for j in range(len(points))))
    rng=Random(1601)
    if phase==8:
        for x,z in ([(0,0)] if patch else [(-.55,.62),(.55,-.30),(-.16,-.49)]):
            rad,height,length=.135,.19,.29
            yy=height/2
            # Hexagonal bundled straw with banded cylindrical surface.
            u=[(cos(i*pi/3)*rad,sin(i*pi/3)*yy+yy) for i in range(6)]
            for i,(x0,y0) in enumerate(u):
                x1,y1=u[(i+1)%6]
                for a,b,c in (((-.5,.5,7),) if lite else ((-.5,-.32,7),(-.32,-.25,10),(-.25,.25,9),(.25,.32,10),(.32,.5,7))):
                    face([(x+x0,y0,z+a*length),(x+x1,y1,z+a*length),
                          (x+x1,y1,z+b*length),(x+x0,y0,z+b*length)],c if i<3 else min(c+1,11))
            for side in (-.5,.5):
                for i,(x0,y0) in enumerate(u):
                    x1,y1=u[(i+1)%6]
                    face([(x,yy,z+side*length),(x+x0,y0,z+side*length),(x+x1,y1,z+side*length)],8+i%2)
    elif lite:
        # Three faceted strips at most per diagonal row. Preserve foliage
        # height and shadowed gaps without drawing individual leaf/stem faces.
        h,c,_=PHASE[phase]
        e=.37 if patch else .85
        offsets=(-.26,.00,.26) if patch else (-.64,-.38,-.13,.13,.38,.64)
        for i,k in enumerate(offsets):
            a,b=-e+abs(k),e-abs(k)
            if phase in (2,7): a,b=a*.85,b*.85
            w=.057 if phase in (2,7) else .090
            def at(t,y,off):
                return (t-k+off,y,t+k-off)
            mid=(a+b)*.5
            for j,(lo,hi) in enumerate(((a,mid),(mid,b))):
                ridge=h*(.89+((i*3+j)%4)*.04)
                v0,v1=at(lo,ridge,0),at(hi,ridge,0)
                face([at(lo,root,-w),at(hi,root,-w),v1,v0],c)
                face([v0,v1,at(hi,root,w),at(lo,root,w)],min(11,c+1))
                if phase in (5,6):
                    # A narrow band catches the golden top at survey height.
                    face([at(lo,ridge*.94,-.025),at(hi,ridge*.94,-.025),
                          v1,v0],6+(i+j)%2)
    else:
        height,index,count=PHASE[phase]
        extent=.4 if patch else .88
        candidates=[(x/16,z/16) for x in range(-14,15,2) for z in range(-14,15,2)
                    if max(abs(x),abs(z))<=extent*16 and (z-x)%6==0]
        # Thick diagonal rows; retain clear walking aisles between them.
        for i,(x,z) in enumerate(candidates):
            if i%3==0 or (phase in (2,7) and i%2==0):
                continue
            x+=rng.uniform(-.017,.017);z+=rng.uniform(-.017,.017)
            h=height*rng.uniform(.80,1.10)
            w=(.038 if phase>=3 and phase!=7 else .024)*rng.uniform(.86,1.13)
            for j in range(count):
                direction=2*pi*j/count+i*.52
                dx,dz=cos(direction)*w,sin(direction)*w
                color=min(index+(j+i)%2,11)
                # Rampant broad leaves below the head; the ripe plant
                # tapers into a thin straw stem, not a solid spike.
                leaf=.57 if phase in (5,6) else 1
                face([(x-dx*.17,root,z-dz*.17),(x+dx*.20,root,z+dz*.20),
                      (x+dx,h*leaf*.54,z+dz),(x+dx*1.35,h*leaf,z+dz*1.35),
                      (x-dx*.38,h*leaf*.61,z-dz*.38)],color)
                if phase in (5,6) and j<2:
                    vx,vz=dx*.08,dz*.08
                    face([(x-vx,root,z-vz),(x+vx,root,z+vz),
                          (x+vx,h*.89,z+vz),(x-vx,h*.89,z-vz)],color)
                    # Folded grain ear with an angular kernel cluster;
                    # doubled leaf normals keep its volume at glancing angles.
                    face([(x,h*.72,z),(x+dx*.37,h*.82,z+dz*.37),
                          (x+dx*.31,h*.94,z+dz*.31),(x,h*1.02,z),
                          (x-dx*.31,h*.94,z-dz*.31),(x-dx*.37,h*.82,z-dz*.37)],6+(i+j)%2)
    header=['# Original LuanTTD farm art; tools/build_crop_growth_art.py',f'o stock_growth_{phase}']
    header.extend(f'vt {(i+.5)/len(PALETTE):.5f} .5' for i in range(len(PALETTE)))
    # Luanti entity meshes use 10 model units per node. Source OBJ X is mirrored.
    header.extend(f'v {-x*10:.3f} {y*10:.3f} {z*10:.3f}' for x,y,z in vertices)
    return ('\n'.join(header+faces)+'\n').encode()
def outputs():
    yield MOD/'textures'/'bl_crop_growth_atlas.png',png()
    for i in (*PHASE,8):
        for patch in (False,True):
            for lite in (False,True):
                suffix=("_patch" if patch else "")+("_lite" if lite else "")
                yield MOD/'models'/f'bl_crop_growth_{i}{suffix}.obj',mesh(i,patch,lite)
def main():
    items=list(outputs())
    assert sum(len(data) for _,data in items)<250*1024
    for p,data in items:
        if '--check' in sys.argv:
            assert p.read_bytes()==data,p
        elif not p.exists() or p.read_bytes()!=data:
            temp=p.with_suffix('.tmp')
            temp.write_bytes(data)
            temp.replace(p)
    print(sum(len(data) for _,data in items),'bytes original growth art; 7 phases × 2 footprints × 2 detail levels')
if __name__=='__main__':main()
