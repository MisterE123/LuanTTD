#!/usr/bin/env python3
"""Original stock OpenTTD #30 low steel rail oil tanker.

blender -b -t 3 --python-exit-code 1 --python tools/build_rail_oil_tanker_art.py
Set RAIL_OIL_TANKER_REVIEW for an optional studio PNG.
"""
from math import cos, pi, sin, tau
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_chaney_jubilee_art as J
import build_balogh_goods_truck_art as G
R,W=J.R,J.W
B,D,L=J.B,J.Disk,J.Lathe
Pipe=J.Pipe
ROOT=R.ROOT
NAME="bl_rail_oil_tanker"
PAL={
 "Tank underbody shadow":"727465","Steel shaded grey":"888c82",
 "Cool brushed steel":"a6afaa","Silver high wall":"bbc4bd","Roof diffuse steel":"c7cdc3",
 "Tank glancing sun":"d9dcd0","Old welded ring":"768880","Weld flash highlight":"b3bfb6",
 "Airframe rail blue":"355b6a","Blue company shadow":"284754","Blue company edge":"597d87",
 "Transfer plate ochre":"b9a16a","Oil cream lettering":"eee0ac","Ladder ridged nickel":"98a99e",
 "Ladder shaded steel":"577577","Cradle warm steel":"727968","Cradle angle graphite":"525a52",
 "Running black iron":"383f3d","Sill rusty red oxide":"754844","Edge red oxide":"9b6252",
 "Dirty light red":"a07159","Axle steel":"535b56","Tire face":"626e65","Tire polished edge":"8e9d93",
 "Dark rail flange":"414a43","Greased wheel hub":"7f8d80","Sunward bolt":"aeb9a8",
 "Buffer burnished":"8b9991","Valve warm red":"984e3c","Valve rubbed brass":"9b845b",
 "Rubber brake hose":"3a4139","Inspection grate shade":"525e57","Inspection grate top":"839389",
 "Review ballast":"827d71",
}
P={k:i for i,k in enumerate(PAL)}
AXLES=(-.235,.235)
WHEEL=.067
RX,RH,Y0=.204,.140,.363
N=40
# Formed shallow dished ends, 2 independent inset end collars, then rear.
PROFILE=((-.394,.36),(-.389,.59),(-.376,.80),(-.355,.94),(-.329,1),
         (.329,1),(.355,.94),(.376,.80),(.389,.59),(.394,.36))
TEXT={
 "O":("0110","1001","1001","1001","0110"),
 "I":("111","010","010","010","111"),
 "L":("1000","1000","1000","1000","1111"),
 "3":("111","001","011","001","111"),
 "0":("111","101","101","101","111"),
 " ":("00","00","00","00","00"),
}


def setup():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=P


def mesh():
    return R.Mesh(R.terrain_height(0))


def F(m,n,c,v):
    m.face(n,P[c],v)


def ellipse(t,z,r=1,d=0):
    return ((RX*r+d)*cos(t),z,Y0+(RH*r+d)*sin(t))


def rounds(z,f=1,expansion=0):
    return [ellipse(i*tau/N,z,f,expansion) for i in range(N)]


def body(m):
    names=[rounds(z,f) for z,f in PROFILE]
    for i,(a,b) in enumerate(zip(names,names[1:])):
        for j in range(N):
            k=(j+1)%N
            s=sin((j+.5)*tau/N)
            if -.25<s<.25 and i in (2,3,4,5,6):
                c="Airframe rail blue" if s>0 else "Blue company shadow"
            elif s>.89:c="Tank glancing sun"
            elif s>.60:c="Roof diffuse steel"
            elif s>.25:c="Silver high wall"
            elif s>-.60:c="Cool brushed steel"
            elif s>-.81:c="Steel shaded grey"
            else:c="Tank underbody shadow"
            F(m,"Long cylindrical tank shell with dished shoulders",c,(a[j],b[j],b[k],a[k]))
    F(m,"Sealed front dished end","Silver high wall",names[0])
    F(m,"Sealed rear dished end","Cool brushed steel",names[-1][::-1])
    for z in (-.252,.252):
        circles=[rounds(z-.014,expansion=.0018),rounds(z-.010,expansion=.0058),
                 rounds(z+.010,expansion=.0058),rounds(z+.014,expansion=.0018)]
        for a,b,c in zip(circles,circles[1:],("Weld flash highlight","Old welded ring","Weld flash highlight")):
            for j in range(N):
                k=(j+1)%N
                F(m,"Full circular bolted tank bands and bright weld lips",c,(a[j],b[j],b[k],a[k]))
        B(m,"Load-bearing transverse saddles bolted into sill","Cradle angle graphite",0,z,.387,.068,.191,.237,.006)
        for s in (-1,1):
            pts=[(s*x,z,h) for x,h in ((.070,.230),(.122,.247),(.166,.276),(.180,.304))]
            for a,b in zip(pts,pts[1:]):
                G.bar(m,"Deep shaped curved saddle knees","Cradle warm steel",a,b,.041,.022)
            B(m,"Bolted saddle foot plates","Cradle warm steel",
              s*.158,z,.081,.081,.223,.242,.004)
            for k in (-1,1):
                D(m,"Six-sided insulator and cast band nut","Sunward bolt",
                  (s*.172,z+k*.026,0),.0095,"h",.240,.249,6)
    for s in (-1,1):
        for z in (-.325,.325):
            Pipe(m,"Diagonal frame to tank sway braces","Ladder ridged nickel",
                 (s*.199,z,.356),(s*.224,z*.28,.221),.0049,8)
            B(m,"Tank brace welded and pinned ends","Cradle angle graphite",
              s*.196,z,.026,.030,.347,.378,.004)
    # Raised inspection dome, separately bolted top valve and tread plates.
    D(m,"Welded tank-top inspection neck","Old welded ring",(0,.044,0),.073,"h",.485,.519,24)
    D(m,"Independent sealed inspection plate","Cradle angle graphite",(0,.044,0),.062,"h",.515,.528,24)
    D(m,"Crowned access lid grey face","Silver high wall",(0,.044,0),.047,"h",.527,.533,24)
    for j in range(8):
        t=j*tau/8
        D(m,"Inspection lid bolts","Sunward bolt",(.056*cos(t),.044+.056*sin(t),0),.0042,"h",.526,.534,6)
    Pipe(m,"Pressed two-part black latch on inspection lid","Rubber brake hose",
         (.012,.034,.533),(.032,.081,.537),.0039,8)
    D(m,"Separate tank roof breather and weather hood","Valve rubbed brass",(-.062,-.106,0),
      .012,"h",.493,.520,12)
    D(m,"Cast roof breather protective lip","Cradle angle graphite",(-.062,-.106,0),.017,"h",.518,.525,12)
    for s in (-1,1):
        B(m,"Two narrow tank-top raised access treadways","Inspection grate shade",
          s*.096,.010,.044,.310,.478,.493,.004)
        for z in (-.127,-.069,-.011,.047,.105,.143):
            B(m,"Individual treadway anchor tab","Old welded ring",s*.097,z,.053,.018,.469,.490,.003)
        for j in range(20):
            B(m,"Genuine raised anti-slip perforations and bridges","Inspection grate top",
              s*.096,-.128+.014*j,.035,.005,.491,.497,.0008)


def label(m):
    for s in (-1,1):
        for word,w0,size,tilt in (("OIL",-.132,.012,-.117),("30",.124,.011,-.104)):
            count=sum(len(TEXT[k][0])+1 for k in word)-1
            x=0
            for c in word:
                for j,row in enumerate(TEXT[c]):
                    for i,a in enumerate(row):
                        if a!='1':continue
                        z=w0+s*size*(x+i-count/2)
                        t=tilt+(4-j)*.066
                        pts=[ellipse(v if s>0 else pi-v,u,1,.0030)
                              for v,u in ((t,z),(t,z+s*size*.92),(t+.063,z+s*size*.92),(t+.063,z))]
                        F(m,"Curved original oil and car number stencils","Oil cream lettering",pts)
                x+=len(TEXT[c][0])+1


def services(m):
    for s in (-1,1):
        # Thin upright curved ladders on opposite sides, kept inside the
        # plated loading gauge and tied into the tank-top treadway.
        z=-s*.015
        def ladder(a,at):
            return ellipse(a if s>0 else pi-a,at,1,.019)
        arcs=[-.89,-.68,-.47,-.26,-.05,.17,.39,.61,.82,1.02]
        for end in (-1,1):
            at=z+end*.034
            pts=[(s*.158,at,.216),*(ladder(a,at) for a in arcs)]
            for a,b in zip(pts,pts[1:]):
                Pipe(m,"Shaped ladder stringers separate from closed tank","Ladder shaded steel",
                     a,b,.0062,8)
        for k,a in enumerate(arcs[1:]):
            Pipe(m,"Visible independent non-filling rung spans","Ladder ridged nickel",
                 ladder(a,z-.034),ladder(a,z+.034),.0047,8)
        for a in (-.68,.17,.82):
            for dz in (-.034,.034):
                p=ladder(a,z+dz)
                q=ellipse(a if s>0 else pi-a,z+dz,1,.0005)
                Pipe(m,"Pinned bracket between ladder rails and tank","Old welded ring",
                     p,q,.0044,8)
        B(m,"Dropped four-wheel wagon step under access ladder","Cradle angle graphite",
          s*.190,z,.067,.067,.136,.165,.008)
        B(m,"Rough nickel open lower stirrup tread","Ladder ridged nickel",
          s*.190,z,.065,.058,.126,.139,.005)

    # Passenger-facing profile retains the true under-tank gap away from
    # the service valve. This stylized discharge assembly is aesthetic only.
    D(m,"Vessel outlet boss beneath tank crown","Cradle angle graphite",(0,.074,0),.028,"h",.202,.238,16)
    path=((0,.074,.219),(0,.074,.191),(.056,.074,.180),(.153,.074,.180),(.203,.074,.174))
    for a,b in zip(path,path[1:]):
        Pipe(m,"Low fitted oil discharge manifold","Axle steel",a,b,.013,10)
    D(m,"Closed discharge end cap","Valve rubbed brass",(.201,.074,.174),.022,"x",-.002,.015,12)
    D(m,"Red pressed release handle and nipple","Valve warm red",(.171,.074,0),.020,"h",.191,.201,12)
    B(m,"Capped manifold protection bracket","Cradle angle graphite",.134,.074,.032,.053,.149,.198,.006)


def frame(m):
    J.shaped(m,"Riveted perimeter wagon underframe","Sill rusty red oxide",[
      (-.136,-.407),(.136,-.407),(.193,-.335),(.201,-.254),(.201,.254),
      (.193,.335),(.136,.407),(-.136,.407),(-.193,.335),(-.201,.254),
      (-.201,-.254),(-.193,-.335)],.144,.217,"Edge red oxide")
    for s in (-1,1):
        B(m,"Rolled visible longitudinal sill section","Sill rusty red oxide",s*.194,0,.023,.738,.157,.218,.004)
        B(m,"Continuous sill lip in rubbed light oxide","Edge red oxide",s*.207,0,.012,.697,.201,.217,.002)
        for z in (-.329,-.232,-.159,-.071,.072,.16,.231,.329):
            D(m,"Individual cold rivet heads along frame","Dirty light red",
              (s*.209,z,.179),.0042,"x",-.002,.003,6)
        G.bar(m,"Long diagonal formed mechanical brake lever","Running black iron",
              (s*.207,-.176,.138),(s*.234,.179,.187),.015,.011)
        B(m,"Aft brake-lever toothed clip","Cradle angle graphite",s*.235,.166,.020,.018,.149,.183,.005)
        # Taper end beams enough for radius-one turns with any stock head.
        B(m,"Two tapered cast red wagon buffer beams","Sill rusty red oxide",
          0,s*.403,.247,.032,.127,.211,.007,"Edge red oxide")
        B(m,"Centered dark coupler pocket behind buffer beam","Running black iron",
          0,s*.436,.050,.056,.128,.186,.004)
        B(m,"Stamped load-bearing drawbar shaft","Cradle angle graphite",
          0,s*.479,.021,.025,.143,.171,.004)
        B(m,"Coupler knuckles","Buffer burnished",
          0,s*.494,.0105,.010,.146,.168,.002)
        for u in (-1,1):
            D(m,"Close-fit buffer sleeves with pressed base","Running black iron",
              (u*.087,s*.417,.166),.019,"z",-.013,.013,18)
            D(m,"Round buffer contact pads in burnished steel","Buffer burnished",
              (u*.087,s*.432,.166),.021,"z",-.004,.004,18)
        Pipe(m,"Independent dipped flexible brake pipe","Rubber brake hose",
             (-.051,s*.420,.146),(-.055,s*.445,.116),.0051,8)
        Pipe(m,"Independent dipped flexible brake pipe","Rubber brake hose",
             (-.055,s*.445,.116),(-.069,s*.439,.101),.0051,8)


def suspension(m,z):
    for s in (-1,1):
        B(m,"Raised journal guide with overhanging leaf seat","Running black iron",
          s*.206,z,.046,.059,.092,.150,.005)
        for y in (-.049,.051):
            G.bar(m,"Cast two-piece wheelset W iron guide","Cradle angle graphite",
                  (s*.192,z+y,.168),(s*.204,z+.42*y,.080),.016,.014)
        for t in range(4):
            B(m,"Bend of individually laminated springs","Axle steel",
              s*.204,z,.031,.114-.016*t,.135-.006*t,.140-.006*t,.004)
        for dz in (-.047,.047):
            D(m,"Steel wedge spring hanger pins","Sunward bolt",
              (s*.218,z+dz,.140),.008,"x",-.003,.003,8)


def rolling(m,z):
    D(m,"Full width axle bridging the 0.424 gauge","Running black iron",
      (0,z,WHEEL),.0135,"x",-.221,.221,14)
    for s,side in ((-1,"L"),(1,"R")):
        x=s*.212
        lo,hi=sorted((-s*.031,s*.043))
        L(m,"Rolling tread oil "+side,[(lo,WHEEL*.72),(lo,WHEEL),(-.004,WHEEL),
                (.004,WHEEL),(hi,WHEEL),(hi,WHEEL*.72),(lo,WHEEL*.72)],"x",(x,z,WHEEL),
                ("Axle steel","Tire face","Tire polished edge","Tire face","Axle steel","Axle steel"),24,False,False)
        a,b=sorted((-s*.042,-s*.035))
        L(m,"True native inward wheel guide flange",[(a,WHEEL*.70),(a,WHEEL+.009),
          (b,WHEEL+.009),(b,WHEEL*.70),(a,WHEEL*.70)],"x",(x,z,WHEEL),("Dark rail flange",),24,False,False)
        D(m,"Deep recessed wheel disk behind the rim","Running black iron",(x+s*.023,z,WHEEL),
          .054,"x",-.012,.014,24)
        D(m,"Cast circular wheel spoke plate","Axle steel",(x+s*.033,z,WHEEL),.043,"x",-.006,.006,20)
        D(m,"Independent grease cap","Greased wheel hub",(x+s*.041,z,WHEEL),
          .019,"x",-.004,.005,16)
        for j in range(5):
            a=j*tau/5
            D(m,"Cast wheel locking pin","Sunward bolt",(x+s*.040,z+.036*cos(a),WHEEL+.036*sin(a)),
               .0035,"x",-.002,.003,7)


def parts(m):
    body(m)
    label(m)
    services(m)
    frame(m)
    for z in AXLES:
        suspension(m,z)
        rolling(m,z)


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):
        return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(NAME+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
      c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    m=R.materials()
    for mat,label in zip(m,P):
        mat.name=label
        n=mat.node_tree.nodes.get("Principled BSDF")
        n.inputs["Metallic"].default_value=.45 if any(t in label.lower() for t in ("steel","nickel","weld","tank")) else .08
        n.inputs["Roughness"].default_value=.57 if "steel" in label.lower() else .74
    return m


def save(m,path=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · 30 000 L Oil Tanker #30"
    sc.view_settings.view_transform="Standard"
    sc["Catalog"]="OpenTTD 14.1 standard gauge #30, image 36, base 2745, capacity 30, full-adder 0"
    sc["Mount"]="0.424 rail centers, +.614 above flat base-0 rail, ideal coupler center Y=.157. Local -Z"
    sc["References"]="Original fictional rail livery. CC BY 3.0 reference photo of preserved British tank car (art/rail_oil_tanker.md)"
    sc.frame_start,sc.frame_end=1,49
    mats=colors()
    for name,f in (
        ("Riveted sealed tank, mounts and original fleet lettering",lambda m:(body(m),label(m))),
        ("Separate ladders, valves and manifold",services),
        ("Dished red oxide frame and fitted suspension",lambda m:(frame(m),*[suspension(m,z) for z in AXLES])),
    ):
        q=mesh()
        f(q)
        J.geometry(sc,name,q,mats)
    for i,z in enumerate(AXLES,1):
        q=mesh()
        rolling(q,z)
        group=J.geometry(sc,f"Editable oil wagon axle {i}",q,mats)
        p=bpy.data.objects.new(f"Axle {i} transverse pivot",None)
        group.objects.link(p)
        p.empty_display_type="CIRCLE"
        p.empty_display_size=WHEEL
        p.location=(0,z,WHEEL)
        for ob in tuple(group.objects):
            if ob!=p:
                ob.parent=p
                ob.location=(0,-z,-WHEEL)
        for frame_nr,v in ((1,0),(49,2*tau)):
            p.rotation_euler.x=v
            p.keyframe_insert(data_path="rotation_euler",index=0,frame=frame_nr)
        J.linear(p.animation_data.action.fcurves)
    sc.frame_set(1)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.239)
                v.region_3d.view_distance=1.69
                v.region_3d.view_rotation=Vector((1.01,-.78,.47)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/rail_oil_tanker.blend"),compress=True)
    if path:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),"Original rail Oil Tanker review"),path)


def main():
    setup()
    m=mesh()
    parts(m)
    p=R.MODELS/(NAME+".obj")
    R.export_obj(p,W.local_obj(m))
    f=p.read_text()
    p.write_text("# Original standard rail Oil Tanker #30 · tools/build_rail_oil_tanker_art.py\n"+f.split("\n",1)[1])
    atlas()
    save(m,os.getenv("RAIL_OIL_TANKER_REVIEW"))


if __name__=="__main__":
    main()
