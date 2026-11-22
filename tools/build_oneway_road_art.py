#!/usr/bin/env python3
"""Original enamel roadside signs and one-way grade-conforming road markings.

blender -b -t 4 --python-exit-code 1 --python tools/build_oneway_road_art.py

Directions: 0 = -X, 1 = +Z, 2 = +X, 3 = -Z. Native static overlay origin
is the north-west even cell at effective road base +2 (above the terrain
mesh). Use paint-only within one-way segments and the complete design at
an entry. No road texture replacement and no upstream sprites.
"""
from math import cos,pi,sin
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_ship_facility_art as H
R=H.rail
PALETTE={
    "Paint cream":"ecdcb1","Paint edge aged":"b5a280","Closed road chalk":"e4c999",
    "Paint faint outer tone":"9e8e71","Foot rock":"80796b","Foot top":"a4a38d",
    "Foundry iron":"465c58","Base iron":"344844","Repair iron":"647670","Post green":"52716a",
    "Rust shadow":"65564b","Pale porcelain":"f5e3bb","Porcelain shade":"cebb95",
    "Sign green black":"284746","Sign green shadow":"223738","Enamel arrow":"f8e5b9",
    "Metal rim":"9b9b8c","Back steel":"5b6863","Clamp":"74817c","Bolt bronze":"a89672",
    "Ruby enamel":"a84a3d","Raised ruby enamel":"c75244","Warm rim":"ddd2b1",
    "Reflector strip":"d7b17d","Opaque eyelet":"424f49","Grass lot":"57814c",
    "Highway outer gravel":"9a937e","Highway asphalt":"4f5255",
}
P={n:i for i,n in enumerate(PALETTE)}
H.P=P
R.COLORS[:]=PALETTE.values()
B,T=H.box,H.tube
RIGHT=.155
EPS=.006
# Quarter-turns are clockwise in authoring X/Z. Sign geometry's seed faces
# -Z, so travelers advancing along +Z see its face.
QUARTERS=(1,0,3,2)
COMPATIBLE=((0,3,12),(0,6,9))
FONT={
    "A":("01110","11011","11011","11111","11011","11011","11011"),
    "E":("11111","11000","11000","11110","11000","11000","11111"),
    "N":("11001","11001","11101","11111","11011","11001","11001"),
    "O":("01110","11011","11011","11011","11011","11011","01110"),
    "R":("11110","11011","11011","11110","11010","11011","11011"),
    "T":("11111","00100","00100","00100","00100","00100","00100"),
    "W":("10001","10001","10001","10101","10101","11011","01010"),
    "Y":("11011","11011","01110","00100","00100","00100","00100"),
    " ":("00000",)*7,
}

def foot_height(x,z,s):
    if s==3:return (x+1)/2
    if s==12:return (1-x)/2
    if s==6:return (z+1)/2
    if s==9:return (1-z)/2
    if s==0:return 0.
    raise ValueError(s)

def rot(x,z,q):
    return ((x,z),(-z,x),(-x,-z),(z,-x))[q%4]

def mesh():
    return R.Mesh(R.terrain_height(0))

def add(m,n,c,pts):
    m.face(n,P[c],pts)

def paint(m,n,c,points):
    if R.signed_area(points)<0:points=points[::-1]
    add(m,n,c,[(x,z,EPS) for x,z in points])

def arrows():
    m=mesh()
    for x in (-RIGHT,RIGHT):
        # Separated head and shank, with a realistic shallow worn threshold.
        # Width .151; leaves 0.08 nodes between each chevron and centerline.
        shank=[(x-.021,-.233),(x+.021,-.225),(x+.021,.079),(x-.021,.079)]
        head=[(x-.076,.079),(x+.076,.079),(x,.254)]
        paint(m,"Raised original tapered one-way arrow heads","Paint cream",head)
        paint(m,"Original one-way stripe shanks","Paint cream",shank)
        paint(m,"Tapered worn arrow feather","Paint edge aged",
              [(x-.021,-.245),(x+.021,-.245),(x+.021,-.225),(x-.021,-.233)])
    return m

def closure_marks(axis):
    m=mesh()
    for side in (-1,1):
        # Three reflective bars per lane at each closed entrance, no
        # fabricated barrier across a normal one-way path.
        for z in (.48,.59,.70):
            z*=side
            for x in (-RIGHT,RIGHT):
                paint(m,"Painted closed approach triplet","Closed road chalk",
                    [(x-.09,z-.021),(x+.09,z-.021),(x+.09,z+.021),(x-.09,z+.021)])
    return planar(m,1 if axis==0 else 0,0)

def flat_plate(m,n,c,x,h,w,t,z0,z1,bevel=.008):
    d=max(.001,min(w/3,t/3,bevel))
    a,b=x-w/2,x+w/2
    c0,d0=h-t/2,h+t/2
    pts=[(a+d,c0),(b-d,c0),(b,c0+d),(b,d0-d),(b-d,d0),(a+d,d0),(a,d0-d),(a,c0+d)]
    panel(m,n,c,pts,z0,z1)

def panel(m,n,c,pts,z0,z1):
    if R.signed_area(pts)<0:pts=pts[::-1]
    ft=[(x,z0,h) for x,h in pts]
    back=[(x,z1,h) for x,h in pts]
    add(m,n,c,ft);add(m,n,c,back[::-1])
    for i in range(len(pts)):
        j=(i+1)%len(pts)
        add(m,n,c,[ft[j],ft[i],back[i],back[j]])

def letters(m,name,s,x,z,h,scale,c):
    for i,k in enumerate(s):
        for j,row in enumerate(FONT[k]):
            a=(i*6-(len(s)*6-1)/2)*scale
            y=(3.5-j)*scale+h
            for p,q in enumerate(row):
                if q!="1":continue
                lo=x+a+p*scale
                hi=lo+scale
                add(m,name,c,[(lo,z,y-scale),(hi,z,y-scale),(hi,z,y),(lo,z,y)])

# Clear about 0.10 nodes between every sign part and the outer asphalt
# edge, so chamfer, diagonal viewing and oversize vehicle poses are safe.
SIGN_X,SIGN_Z=.575,-.692

def footing(m):
    x,z=SIGN_X,SIGN_Z
    B(m,"Dressed cast concrete ground plinth","Foot rock",x,z,.127,.141,-.016,.045,.012,top="Foot top")
    B(m,"Warm iron edge plate","Base iron",x,z,.084,.094,.041,.074,.009)
    T(m,"Period galvanized upright sign stanchion","Post green",(x,z,.068),(x,z,.618),.019,.014,12)
    for y in (.096,.345,.512):
        T(m,"Formed saddle post collars","Clamp",
          (x,z,y-.012),(x,z,y+.014),.024,.021,12)
    for a in (-.033,.033):
        for b in (-.037,.037):
            T(m,"Four slotted ground studs","Bolt bronze",(x+a,z+b,.069),(x+a,z+b,.081),.006,.006,7)
    T(m,"Riveted stanchion mushroom cap","Clamp",(x,z,.607),(x,z,.629),.022,.013,10)
    # Tall retroreflective sleeve is narrower than the actual post.
    flat_plate(m,"Reflector jacket lower curbside","Reflector strip",x,.229,.023,.070,z-.0195,z-.017,.003)

def sign(forbidden):
    m=mesh()
    footing(m)
    x,z=SIGN_X,SIGN_Z
    if not forbidden:
        h=.482
        # Etched porcelain sign made as separate round-edged laminated pieces.
        flat_plate(m,"Pressed one-way plate metal rim","Metal rim",x,h,.320,.209,z-.030,z-.007,.020)
        flat_plate(m,"One-way outer ivory porcelain keyline","Pale porcelain",x,h,.307,.197,z-.033,z-.028,.019)
        flat_plate(m,"One-way inset forest green enamel plate","Sign green black",x,h,.281,.172,z-.035,z-.032,.015)
        stem=[(x-.009,h+.000),(x+.009,h+.000),(x+.009,h+.030),(x-.009,h+.030)]
        head=[(x-.030,h+.030),(x+.030,h+.030),(x,h+.066)]
        for g in (stem,head):
            panel(m,"Raised up-road enamel pointer","Enamel arrow",g,z-.038,z-.035)
        letters(m,"Raised ONE WAY porcelain glyphs","ONE WAY",x,z-.0365,h-.036,.006,"Pale porcelain")
        for dx in (-.14,.14):
            T(m,"One-way enamel face screw","Bolt bronze",(x+dx,z-.035,h),(x+dx,z-.041,h),.006,.005,9)
        for y in (.409,.537):
            flat_plate(m,"Pressed back bracket and bolts","Back steel",x,y,.081,.028,z-.005,z+.017,.006)
    else:
        h=.489
        # A concave backing is unnecessary; three independent circular
        # layers capture the curved enamel lip and dimensional white band.
        for n,c,a,b,r0,r1 in (
            ("No-entry zinc disk reverse","Back steel",-.006,-.024,.129,.131),
            ("No-entry continuous raised pale metal rim","Warm rim",-.024,-.032,.131,.128),
            ("No-entry red pressed round enamel disk","Ruby enamel",-.032,-.036,.118,.115),
            ("No-entry inner slight convex gloss face","Raised ruby enamel",-.036,-.039,.111,.106)):
            T(m,n,c,(x,z+a,h),(x,z+b,h),r0,r1,32)
        flat_plate(m,"White no-entry inset porcelain horizontal bar","Pale porcelain",x,h,.165,.035,z-.0415,z-.0393,.008)
        flat_plate(m,"Black rear jaw clamp and visible bolts","Base iron",x,h,.076,.101,z-.012,z+.009,.010)
        # A tiny inset stencil makes it identifiable already from the physical icon.
        letters(m,"Subtle NO ENTRY stencil","NO ENTRY",x,z-.0402,h-.061,.004,"Pale porcelain")
        for dir in (-1,1):
            T(m,"No-entry sign rear rivets","Metal rim",(x+.045*dir,z-.009,h),(x+.045*dir,z+.003,h),.005,.004,8)
    return m

def merge(*pieces):
    m=mesh()
    for p in pieces:
        for n,faces in p.parts.items():
            vs=p.vertices[n]
            for ids,color in faces:m.face(n,color,[vs[i] for i in ids])
    return m

def planar(source,q,shape):
    # Compose plan heading first. Project all vertices to the exact host
    # slope. This mode is for road paint only (signs stay plumb).
    out=mesh()
    for n,faces in source.parts.items():
        vs=source.vertices[n]
        for ids,c in faces:
            pp=[]
            for i in ids:
                x,z,h=vs[i]
                x,z=rot(x,z,q)
                pp.append((x,z,h+foot_height(x,z,shape)))
            out.face(n,c,pp)
    return out

def upright(source,q,shape):
    # All mast and plate vertices share the vertical foot translation.
    # For the ground plinth only, shape the entire underside to the road
    # verge's true terrain plane so there is no daylight under the pad.
    out=mesh()
    cx,cz=rot(SIGN_X,SIGN_Z,q)
    dh=foot_height(cx,cz,shape)
    for n,faces in source.parts.items():
        vs=source.vertices[n]
        for ids,c in faces:
            pp=[]
            for i in ids:
                x,z,h=vs[i]
                x,z=rot(x,z,q)
                lift=foot_height(x,z,shape) if n=="Dressed cast concrete ground plinth" and h<0 else dh
                pp.append((x,z,h+lift))
            out.face(n,c,pp)
    return out

def output(name,m):
    p=R.MODELS/(name+".obj")
    # Mesh rides above (not instead of) existing road-grade note at base+1.
    R.export_obj(p,m,vertical_origin=1.5)
    data=p.read_text()
    p.write_text(data.replace(data.splitlines()[0],
        "# Original one-way marker, NW overlay at effective road base+2. tools/build_oneway_road_art.py",1))

def atlas():
    def chunk(t,data):
        return struct.pack(">I",len(data))+t+data+struct.pack(">I",zlib.crc32(t+data))
    rows=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    p=R.TEXTURES/"bl_oneway_atlas.png"
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
                  +chunk(b"IDAT",zlib.compress((b"\0"+rows)*8,9))+chunk(b"IEND",b""))

def view_collection(scene,m,mats,label):
    c=bpy.data.collections.new(label)
    scene.collection.children.link(c)
    R.to_blender(m,c,mats)
    return c

def close_overlay(mark,entry,axis,g):
    return merge(planar(mark,0,g),upright(entry,axis,g),upright(entry,axis+2,g))

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    arrows_m,yes,no=arrows(),sign(False),sign(True)
    for d,q in enumerate(QUARTERS):
        axis=d%2
        output(f"bl_oneway_sign_{d}",upright(yes,q,0))
        output(f"bl_noentry_sign_{d}",upright(no,q,0))
        for g in COMPATIBLE[axis]:
            basic=planar(arrows_m,q,g)
            output(f"bl_oneway_paint_{d}_g{g}",basic)
            output(f"bl_oneway_{d}_g{g}",merge(basic,upright(yes,q,g),upright(no,q+2,g)))
    for axis in (0,1):
        for g in COMPATIBLE[axis]:
            output(f"bl_oneway_both_{axis}_g{g}",close_overlay(closure_marks(axis),no,1-axis,g))
    atlas()
    a=bpy.context.scene
    a.name="Original one-way signs and layout"
    b=bpy.data.scenes.new("Planar paint on existing ported road grade")
    c=bpy.data.scenes.new("Both approaches closed (stock DRD_BOTH)")
    mats=R.materials()
    for name,i in P.items():mats[i].name=name
    for scene,typ,g in ((a,"normal",0),(b,"sloped",9),(c,"closed",0)):
        if typ!="closed":
            art=merge(planar(arrows_m,0,g),upright(yes,0,g),upright(no,2,g))
        else:art=close_overlay(closure_marks(1),no,0,g)
        view_collection(scene,art,mats,"Editable original signs and markings")
        scene["Native overlay anchor"]="NW base+2; centered X/Z extents -1..+1. Roads and terrain use their original separate nodes."
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                e=area.spaces.active
                e.shading.color_type="MATERIAL"
                e.region_3d.view_location=(0,0,.28)
                e.region_3d.view_distance=2.9
                e.region_3d.view_rotation=(Vector((0,0,.1))-Vector((2,-3,2.7))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/oneway_road.blend"),compress=True)

if __name__=="__main__":main()
