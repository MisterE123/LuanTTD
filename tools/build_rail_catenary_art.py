#!/usr/bin/env python3
"""Original, tile-centered modular overhead wire meshes for stock rail.

OpenTTD elrail.cpp uses edge control points and roughly alternate
level straight mast positions. This native art is deliberately narrower
than the source visual dispatcher: only single pieces and straight grades.
"""
from math import hypot, pi, sin
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as W
R=W.rail
PAL={
 "Weathered copper contact underside":"6d6753",
 "Glancing contact edge":"828075",
 "Messenger cable charcoal":"586461",
 "Dropper link tempered steel":"758081",
 "Braced period blue-grey steel mast":"586c70",
 "Satin warm galvanized beam edge":"90a29e",
 "Mast steel shadow tension flange":"495a5c",
 "Porcelain warm bleached insulator":"d3cbb0",
 "Porcelain tab shadow":"9c997f",
 "Foundation rough granite":"81817a",
 "Foundation dark mortar edge":"69736a",
 "Raised copper end clamps":"a38a68",
 "Preview base":"777d70",
}
P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
W.P=P
B,D=W.slab,W.circular
WIRE=.898
ATLAS="bl_rail_catenary_atlas"
FLAT=(1,2,4,8,16,32)
GRADE=(1,1,2,2)


def face(m,n,c,vs):
    m.face(n,P[c],vs)


def bar(m,n,c,a,b,w,d=None,edge=None):
    a,b=Vector(a),Vector(b)
    T=(b-a).normalized()
    u=T.cross(Vector((0,0,1) if abs(T.z)<.94 else (0,1,0))).normalized()*w*.5
    v=T.cross(u).normalized()*(d or w)*.5
    p=(u+v,-u+v,-u-v,u-v)
    x,y=([tuple(k+q) for q in p] for k in (a,b))
    face(m,n,c,x[::-1]);face(m,n,c,y)
    for i in range(4):
        j=(i+1)%4
        face(m,n,edge if edge and i in (0,2) else c,(x[i],x[j],y[j],y[i]))


def cable(m,path,name,low,thick,w,mat,edge=None):
    samples=10 if path.is_straight else 22
    t=[j/samples for j in range(samples+1)]
    rows=[]
    for p in t:
        u=path.offset(p,-w/2)
        v=path.offset(p,w/2)
        h=low(p)
        # Railhead slope is applied afterwards by Mesh.face at true X/Z.
        rows.append([(*u,h),(*v,h),(*v,h+thick),(*u,h+thick)])
    for a,b in zip(rows,rows[1:]):
        for i in range(4):
            j=(i+1)%4
            face(m,name,(edge or mat) if i in (1,3) else mat,(a[i],a[j],b[j],b[i]))
    # Open on the end faces: adjoining sections contribute the exact
    # same profile and outward normals without coplanar duplicate caps.


def contact(p):return WIRE


def messenger(p):return .997-.030*sin(pi*p)**2


def wire(m,path):
    cable(m,path,"Continuous shaped contact wire underside aligned to SH30 shoe",
        contact,.009,.013,"Weathered copper contact underside","Glancing contact edge")
    cable(m,path,"Independently suspended messenger catenary cable",
        messenger,.008,.010,"Messenger cable charcoal")
    for t in (.18,.34,.50,.66,.82):
        x,z,*_=path.sample(t)
        bar(m,"Five actual thin separate vertical droppers", "Dropper link tempered steel",
            (x,z,WIRE+.006),(x,z,messenger(t)+.004),.0047)


def mast(m,path):
    t=.5
    x,z,dx,dz=path.sample(t)
    if path.is_straight:
        ux,uz=path.offset(t,.730)
    else:
        # Outer-facing mast on curves, avoiding both running rails and the
        # adjacent footprint. Quarter-circle sign is geometry-derived.
        left=path.offset(t,.730)
        right=path.offset(t,-.730)
        ux,uz=max((left,right),key=lambda p:hypot(p[0]-path.cx,p[1]-path.cz))
    B(m,"Chamfered grounded masonry mast foot", "Foundation dark mortar edge",
      ux,uz,.153,.157,0,.048,.016,"Foundation rough granite")
    B(m,"Heavier casting and four foot bolts around mast", "Mast steel shadow tension flange",
      ux,uz,.103,.094,.046,.099,.011)
    for ox,oz in ((-.038,-.033),(-.038,.033),(.038,-.033),(.038,.033)):
        D(m,"Exposed original foundation set bolts","Raised copper end clamps",
          (ux+ox,uz+oz,0),.006,"h",.090,.107,7)
    bx,bz=ux,uz
    B(m,"Tall genuine H section hot rolled steel mast central web",
      "Braced period blue-grey steel mast",bx,bz,.023,.055,.095,1.195,.006)
    for ox in (-.021,.021):
        B(m,"Two vertical shoulder flanges of H section mast",
          "Satin warm galvanized beam edge",bx+ox,bz,.012,.064,.102,1.188,.005)
    B(m,"Bolted closed square mast top", "Braced period blue-grey steel mast",bx,bz,.056,.068,
      1.186,1.207,.006)
    a=(ux,uz,1.109)
    b=(x,z,1.062)
    bar(m,"Sheltered solid crossarm spanning contact wire",
        "Braced period blue-grey steel mast",a,b,.024,.021,
        "Satin warm galvanized beam edge")
    vv=(.55*ux+.45*x,.55*uz+.45*z,1.081)
    bar(m,"Grounded cantilever triangular lower brace",
        "Mast steel shadow tension flange",(ux,uz,.753),vv,.012,.015,
        "Braced period blue-grey steel mast")
    B(m,"Small wire hanger pressed metal lip",
      "Satin warm galvanized beam edge",x,z,.040,.034,1.052,1.080,.004)
    for lo,rr in ((1.012,.012),(1.028,.015),(1.046,.015)):
        D(m,"Three separate insulator porcelain ridges on drop bar", "Porcelain warm bleached insulator",
          (x,z,0),rr,"h",lo,lo+.009,11)
    D(m,"Through-bolted porcelain hanger with metal eye", "Porcelain tab shadow",
      (x,z,0),.0075,"h",.982,1.058,10)
    thicker=path.offset(.5,.029)
    bar(m,"Triangular small wire registration stay arm",
        "Raised copper end clamps",(*thicker,.999),(x,z,WIRE+.013),.0085)
    # Keeps the copper collector wire at exactly the section's surface, not
    # a second visually overlapping sagging contact wire across the mast.
    bar(m,"Short hard support grab jaw over contact strip", "Glancing contact edge",
        (x-.013,z,WIRE+.010),(x+.013,z,WIRE+.010),.007)


def slot(bits,grade,with_mast):
    i=FLAT.index(bits)
    path=R.TrackPath(i)
    m=R.Mesh(R.terrain_height(grade))
    wire(m,path)
    if with_mast:mast(m,path)
    return m


def asset_names():
    for grade,bits in [(0,b) for b in FLAT]+list(enumerate(GRADE,1)):
        for pole in (0,1):
            suffix=f"grade_{grade}_{pole}" if grade else f"{bits}_{pole}"
            yield f"bl_rail_catenary_{suffix}",bits,grade,pole


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(ATLAS+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
      c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def mats():
    out=R.materials()
    for c,m in zip(P,out):
        m.name=c
        p=m.node_tree.nodes["Principled BSDF"]
        p.inputs["Metallic"].default_value=.52 if "porcelain" not in c.lower() else .03
        p.inputs["Roughness"].default_value=.50
    return out


def author(models):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · modular native overhead line assembly"
    sc.view_settings.view_transform="Standard"
    sc["Provenance"]="Original cable, tension rods, masonry feet and section steel; stock elrail.cpp informs control-point behavior only."
    sc["Mount"]="Flats: b+2. Grades: b+3, on integer 2*x/2*z. Local contact underside is -.602 on flats."
    sc["Contact height"]="Flat vehicle SH30 pantograph world b+1.398, underside of the wire. None of these assets change simulation."
    pal=mats()
    for i,(name,m) in enumerate(models):
        col=bpy.data.collections.new(name.removeprefix("bl_"))
        sc.collection.children.link(col)
        R.to_blender(m,col,pal)
        for o in col.objects:
            o.location=((i%5-2)*2.22,(i//5-1.5)*2.35,0)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.68)
                v.region_3d.view_rotation=Vector((5.4,-7.12,5.1)).to_track_quat("Z","Y")
                v.region_3d.view_distance=13.0
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_catenary.blend"),compress=True)


def main():
    models=[]
    for name,bits,grade,pole in asset_names():
        model=slot(bits,grade,pole)
        p=R.MODELS/(name+".obj")
        R.export_obj(p,model,vertical_origin=2.5 if grade else 1.5)
        data=p.read_text()
        p.write_text("# Original native stock overhead wire art · tools/build_rail_catenary_art.py\n"+data.split("\n",1)[1])
        models.append((name,model))
    atlas()
    author(models)


if __name__=="__main__":
    main()
