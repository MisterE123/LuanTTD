#!/usr/bin/env python3
"""Original stock rail Goods Van #32. Set RAIL_GOODS_VAN_REVIEW for a PNG."""
from math import cos, pi, sin
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_oil_tanker_art as O
R,W,J,G=O.R,O.W,O.J,O.G
B,D,Pipe=O.B,O.D,O.Pipe
NAME="bl_rail_goods_van"
PAL={
 "Deep panel blue":"31647f","Weathered company blue":"447d9e",
 "Glancing blue paint":"6397b0","Milled board edge":"365d70","Raw deep grain":"2d536c",
 "Outer brace blue":"4a7c93","Bright milled brace edge":"6795a8",
 "Dark door seam":"304553","Steel end dark blue":"3b5c70","Blue recessed light":"52768a",
 "Cured roofing dark":"424a4d","Cured roof edge":"4b585b","Roof cool diffuse":"657173",
 "Rubbed chalk roof seams":"7d8882","Roof shade mottling":"586365",
 "Dry metal door hinge":"74807a","Greased cast hinge joint":"4d5958",
 "Panel worn ochre":"ae9560","Ivory freight stencil":"e9d7a7",
 "Riveted warm brake beam":"775750","Blue-dark vestibule trim":"344b57",
 "Review ballast":"827d71",
 **{k:O.PAL[k] for k in (
     "Running black iron","Cradle angle graphite","Axle steel","Sunward bolt",
     "Tire face","Tire polished edge","Dark rail flange","Greased wheel hub","Buffer burnished",
     "Sill rusty red oxide","Edge red oxide","Rubber brake hose")},
}
P={k:i for i,k in enumerate(PAL)}
AXLES=O.AXLES
EAVES=.509
CROWN=.572


def palette():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=O.P=P


def mesh():
    return R.Mesh(R.terrain_height(0))


def face(m,n,c,v):
    m.face(n,P[c],v)


def surround(m):
    # Each side has its own actual boards and diagonal steel strap. The
    # central loading aperture is bounded by a genuine trim and occupied
    # only by the separate, closed double-door collection.
    for s in (-1,1):
        for a,b in ((-.391,-.126),(.126,.391)):
            for j in range(10):
                lo=.222+j*(EAVES-.222)/10
                hi=lo+(EAVES-.222)/10-.0009
                color=("Weathered company blue","Deep panel blue","Weathered company blue",
                       "Glancing blue paint","Weathered company blue")[(j+(a>0)*2)%5]
                B(m,"Individual painted sealed horizontal side planks",color,s*.188,(a+b)/2,
                  .040,b-a,lo,hi,.0021,"Milled board edge")
            B(m,"Steel reinforced floor board behind wood", "Deep panel blue",s*.179,(a+b)/2,
              .020,b-a,.218,EAVES-.001,.004)
        B(m,"Cabin rear and front stamped angled outer corner posts","Outer brace blue",
          s*.202,-.381,.029,.043,.222,EAVES,.004)
        B(m,"Cabin rear and front stamped angled outer corner posts","Outer brace blue",
          s*.202,.381,.029,.043,.222,EAVES,.004)
        for z in (-.312,-.231,-.127,.127,.231,.312):
            B(m,"Articulated vertical visible company-painted door stile braces","Outer brace blue",
              s*.211,z,.023,.020,.225,EAVES-.004,.0027,"Bright milled brace edge")
            for d in (.252,.321,.399,.476):
                D(m,"Row of individual punched side rivets","Sunward bolt",
                  (s*.223,z,d),.0032,"x",-.0017,.0017,7)
        for q in (-1,1):
            # Diagonal braces follow the prototype; the stock silhouette's
            # comparatively heavy vertical supports are retained too.
            a=(s*.216,q*.357,.492);b=(s*.216,q*.142,.230)
            G.bar(m,"Original continuous diagonal outside Vanfit pressed strap","Outer brace blue",a,b,.017,.010)
            Pipe(m,"Continuous raised patinated strap embossment","Bright milled brace edge",
                 (s*.222,a[1],a[2]),(s*.222,b[1],b[2]),.0014,6)
        B(m,"Painted lower rub rail beneath timber planks","Deep panel blue",s*.201,0,.031,.787,.219,.237,.004)
        B(m,"Deep continuous top eaves lower board","Dark door seam",s*.205,0,.028,.791,.488,EAVES,.003)
    B(m,"Solid lower walk-in van floor panel","Deep panel blue",0,0,.392,.779,.204,.226,.009)

    # Steel ends have cast, physically machined corrugations, with a
    # dark shrouded ventilator just under the roof crown.
    for end in (-1,1):
        B(m,"Machined covered van end solid pressure sheet", "Steel end dark blue",
          0,end*.385,.391,.029,.220,.511,.008)
        for j in range(12):
            h=.239+j*.0206
            pts=((-.186,end*.397,h),(-.175,end*.405,h+.004),(.175,end*.405,h+.004),
                 (.186,end*.397,h))
            J.shaped(m,"Horizontal formed steel end corrugation channels",
               "Blue recessed light" if j%3==0 else "Steel end dark blue",
               [(x,z) for x,z,e in pts]+[(.186,end*.394),(-.186,end*.394)],h,h+.008)
        B(m,"Shrouded high steel end vent hood fitted separately","Outer brace blue",
          0,end*.398,.148,.016,.456,.516,.006)
        B(m,"Deep dark protected end ventilator aperture","Dark door seam",
          0,end*.407,.121,.008,.465,.498,.002)
        for j in range(3):
            B(m,"Visible tiny ventilation slats within hood","Dry metal door hinge",
              0,end*.413,.109,.006,.467+j*.009,.470+j*.009,.0007)
        for x in (-.175,.175):
            for j in range(7):
                D(m,"Steel end punched fastening bolt heads","Sunward bolt",
                  (x,end*.404,.248+j*.036),.0034,"z",-.002,.002,7)


def doors(m):
    for s in (-1,1):
        for leaf in (-1,1):
            z0,z1=(.002,.123) if leaf>0 else (-.123,-.002)
            zc=(z0+z1)/2
            B(m,"Deep vertical recess behind independent double door","Dark door seam",
              s*.194,zc,.027,z1-z0-.002,.226,.497,.006)
            for j in range(7):
                z=z0+(j+.5)*(z1-z0)/7
                B(m,"Actual separately milled vertical timber loading door boards",
                  ("Weathered company blue","Deep panel blue","Glancing blue paint")[(j+leaf)%3],
                  s*.216,z,.027,(z1-z0)/7-.00075,.234,.489,.0022)
            for dz in (z0+.007,z1-.007):
                B(m,"Visible cold-rolled door border frame and tie bracket","Outer brace blue",
                  s*.229,dz,.019,.011,.230,.496,.0016)
            for h in (.241,.467):
                B(m,"Recessed heavy horizontal strap hinge","Dry metal door hinge",
                  s*.231,zc,.018,.079,h,h+.010,.002)
                D(m,"Round revolute pin head on functioning hinge leaf","Greased cast hinge joint",
                  (s*.235,leaf*.114,0),.0079,"h",h-.005,h+.017,12)
                for z in (zc-.023,zc+.021):
                    D(m,"Hinge leaf rolled bolt","Sunward bolt",
                    (s*.241,z,h+.005),.0031,"x",-.001,.002,7)
        Pipe(m,"Deep proud handle and independent door draw-latch shaft","Dry metal door hinge",
             (s*.233,-.005,.274),(s*.233,-.005,.452),.0034,9)
        B(m,"Original small cast rectangular door lock housing","Greased cast hinge joint",
          s*.237,.008,.020,.030,.318,.347,.003)
        D(m,"Individual round brass locking barrel","Panel worn ochre",
          (s*.249,.013,.333),.0058,"x",-.0018,.0030,12)


def roof(m):
    def ring(z,xy,h0):
        return [(xy*cos(pi-i*pi/18),z,h0+(CROWN-EAVES)*sin(pi-i*pi/18)) for i in range(19)]
    loc=[(-.414,.195,EAVES-.003),(-.383,.217,EAVES),(-.283,.221,EAVES),
         (-.092,.222,EAVES),(.092,.222,EAVES),(.283,.221,EAVES),
         (.383,.217,EAVES),(.414,.195,EAVES-.003)]
    sections=[ring(z,w,h) for z,w,h in loc]
    for j,(a,b) in enumerate(zip(sections,sections[1:])):
        for i in range(len(a)-1):
            col=("Roof cool diffuse" if 5<=i<=13 else "Cured roofing dark" if i in (0,17)
                 else "Roof shade mottling" if (i+j)%4==0 else "Cured roof edge")
            face(m,"Continuous physically arched cured-cloth roof",col,(a[i],a[i+1],b[i+1],b[i]))
            v=[(x,z,h-.012) for x,z,h in (a[i],b[i],b[i+1],a[i+1])]
            face(m,"True shaded underside of bowed roof boards","Cured roofing dark",v)
        for i in (0,-1):
            Pipe(m,"Continuous separately rolled thin eaves gutter","Roof shade mottling",a[i],b[i],.0028,7)
    for idx,pts in enumerate(sections):
        if idx in (2,4,5):
            for a,b in zip(pts,pts[1:]):
                Pipe(m,"Fine pale standing roof cloth seams","Roof shade mottling",
                     (a[0],a[1],a[2]+.0015),(b[0],b[1],b[2]+.0015),.0013,6)
        if idx not in (0,len(sections)-1):continue
        # The timber end closes under the roof arch; dark outer lip joins
        # actual thickness to the arch without protruding from the wagon.
        face(m,"Shaped end infill closing under the curved roofline","Steel end dark blue",
             pts if idx==0 else pts[::-1])
        for a,b in zip(pts,pts[1:]):
            Pipe(m,"Proud narrow cured lip rounding over van ends","Cured roofing dark",a,b,.0033,7)


def stencil(m):
    letters={"G":("011","100","101","101","011"),"O":("010","101","101","101","010"),
             "D":("110","101","101","101","110"),"S":("111","100","111","001","111"),
             "3":("111","001","011","001","111"),"2":("110","001","010","100","111"),
             " ":("000","000","000","000","000")}
    for s in (-1,1):
        B(m,"Original outboard Goods 32 identification plate","Dark door seam",
          s*.214,.292,.010,.076,.278,.323,.003)
        for word,zc,h,size,x in (("GOODS",-.282,.289,.0054,.222),("32",.292,.292,.0061,.222)):
            if word=="GOODS":
                B(m,"Original sign strip framed below diagonal Vanfit brace","Dark door seam",
                  s*.214,zc,.010,.117,.281,.324,.003)
            for i,ch in enumerate(word):
                for j,row in enumerate(letters[ch]):
                    for k,a in enumerate(row):
                        if a=="1":
                            z=zc+s*(i*4+k-2*len(word)+.5)*size
                            y=h+(4-j)*size
                            B(m,"Original raised tiny painted Goods Van lettering","Ivory freight stencil",
                              s*x,z,.0026,size*.88,y,y+size*.89,.00018)


def frame(m):
    J.shaped(m,"Tapered broad riveted dark brake-sill frame","Running black iron",[
      (-.123,-.402),(.123,-.402),(.191,-.354),(.202,-.250),(.202,.250),
      (.191,.354),(.123,.402),(-.123,.402),(-.191,.354),(-.202,.250),
      (-.202,-.250),(-.191,-.354)],.143,.217,"Cradle angle graphite")
    for s in (-1,1):
        B(m,"Low continuous dirty steel wagon frame I beam","Axle steel",s*.204,0,.022,.721,.149,.211,.004)
        B(m,"Visible dark recessed frame beam girder","Running black iron",s*.217,0,.006,.678,.161,.199,.001)
        for z in (-.331,-.239,-.116,.116,.239,.331):
            D(m,"Early frame join rounded stud","Sunward bolt",
              (s*.219,z,.185),.0032,"x",-.002,.002,7)
        G.bar(m,"Dedicated wagon long manual brake release bar","Cradle angle graphite",
              (s*.210,-.190,.126),(s*.231,.172,.186),.012,.011)
        B(m,"Handbrake actuating rod latch above hanger","Dry metal door hinge",
          s*.231,.176,.022,.034,.176,.194,.003)
        B(m,"Inboard dark slightly tapered brake buffer end beam","Riveted warm brake beam",
          0,s*.407,.229,.027,.132,.210,.007)
        B(m,"Central dark steel draw guide","Running black iron",0,s*.438,.054,.055,.133,.184,.005)
        B(m,"Dark turned drawarm neck ahead of guide","Axle steel",0,s*.480,.025,.024,.143,.171,.005)
        B(m,"Coupler knuckles","Buffer burnished",0,s*.494,.0105,.010,.146,.168,.002)
        for x in (-.081,.081):
            D(m,"Separate tight turn buffer sleeves cast into beam","Running black iron",
               (x,s*.420,.162),.020,"z",-.010,.010,16)
            D(m,"Two round tail buffer faces burnished steel","Buffer burnished",
               (x,s*.432,.162),.021,"z",-.004,.004,18)
        Pipe(m,"Single flexible rail goods brake hose inboard","Rubber brake hose",
             (-.046,s*.422,.152),(-.052,s*.444,.113),.0049,8)
    for z in AXLES: O.suspension(m,z)


def assemble(m):
    frame(m);surround(m);doors(m);roof(m);stencil(m)


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):
        return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(NAME+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
        c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
        c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    out=R.materials()
    for color,mat in zip(P,out):
        mat.name=color
        nodes=mat.node_tree.nodes["Principled BSDF"]
        nodes.inputs["Metallic"].default_value=.4 if any(r in color.lower() for r in ("iron","steel","nickel")) else .04
        nodes.inputs["Roughness"].default_value=.71
    return out


def save(m):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.view_settings.view_transform="Standard"
    sc.name="LuanTTD · Goods Van #32 full standard rail wagon"
    sc["Stock"]="OpenTTD 14.1 ID32, image38, 21t tare, 25 crates, closed same appearance at every fill."
    sc["Native mount"]="Unit scale, +.614 at flat track base0, Y0 tire, .424 rail gauge, -Z."
    sc["Art provenance"]="Original own geometry from historical Vanfit references, no source pixel reuse."
    mats=colors()
    for title,generator in (("Ventilated plank walls and pressed van ends",surround),
          ("Separate painted wood door leaves and hinge hardware",doors),
          ("Solid curved dark roof and original identification",lambda p:(roof(p),stencil(p))),
          ("Rail wagon brake rig and adjustable suspension",frame)):
        p=mesh();generator(p);J.geometry(sc,title,p,mats)
    for i,z in enumerate(AXLES,1):
        q=mesh();O.rolling(q,z)
        group=J.geometry(sc,f"Goods Van wheelset {i}",q,mats)
        pivot=bpy.data.objects.new(f"Editable transverse axle {i}",None)
        pivot.empty_display_type="CIRCLE";pivot.empty_display_size=O.WHEEL
        group.objects.link(pivot)
        pivot.location=(0,z,O.WHEEL)
        for ob in list(group.objects):
            if ob!=pivot:ob.parent=pivot;ob.location=(0,-z,-O.WHEEL)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                q=a.spaces.active
                q.shading.color_type="MATERIAL"
                q.region_3d.view_location=(0,0,.265)
                q.region_3d.view_rotation=Vector((.98,-.88,.47)).to_track_quat("Z","Y")
                q.region_3d.view_distance=1.70
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_goods_van.blend"),compress=True)
    if path:=os.getenv("RAIL_GOODS_VAN_REVIEW"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),"Original Goods Van #32"),path)


def main():
    palette()
    m=mesh();assemble(m)
    for z in AXLES:O.rolling(m,z)
    p=R.MODELS/(NAME+".obj")
    R.export_obj(p,W.local_obj(m))
    data=p.read_text()
    p.write_text("# Original covered Goods Van #32 · tools/build_rail_goods_van_art.py\n"+data.split("\n",1)[1])
    atlas();save(m)


if __name__=="__main__":
    main()
