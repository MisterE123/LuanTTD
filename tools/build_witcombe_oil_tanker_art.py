#!/usr/bin/env python3
"""Original closed Witcombe Oil Tanker #132; export from Blender 4.x.

blender -b -t 3 --python-exit-code 1 --python tools/build_witcombe_oil_tanker_art.py
Set WITCOMBE_OIL_REVIEW=/path/preview.png for a three-quarter studio view.
Luanti visual_size .42, native nose -Z and tire datum Y=0.
"""
from math import cos, pi, sin, tau
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm_road_trucks_art as F

G, R, S = F.G, F.R, F.S
ROOT = R.ROOT
NAME = "witcombe_oil_tanker"
PAL = {**F.PALETTE,
    "Company blue": "477994", "Blue highlight": "5d90a5",
    "Deep blue": "2f4d5e", "Darker door": "3a5e70",
    "Tank warm ivory": "d3c399", "Upper sun ivory": "e4d5b1",
    "Tank cream shoulder": "d9cba3", "Tank low warm steel": "a89471",
    "Tank dusty underside": "7d7967", "Blue band enamel": "36637b",
    "Band seam dark": "345667", "Band seam bright": "68848c",
    "Bolted keeper iron": "555b55", "Dry welding line": "b9a583",
    "Painted bolt bright": "a1a697", "Valve worn red": "8f4d36",
    "Bronze cap casting": "a68658", "Worn reel rubber": "3b3c38",
    "Discharge pipe gray": "707f7c", "Pressed bridge grip": "757b6b",
    "Emboss cream lettering": "e7dbb9", "Warning diamond amber": "d29c4f",
    "Deep tar cap": "454842", "Warm reflected ivory": "cdb791",
}
P = {k:i for i,k in enumerate(PAL)}
B, T, C, bar, face = F.B, F.T, F.C, F.bar, G.face
RADIUS_X, RADIUS_H, CENTRE_H = .221, .187, .424
N = 40
RINGS = ((-.172,.33),(-.159,.57),(-.137,.80),(-.111,.94),(-.081,1),
         (.662,1),(.691,.986),(.716,.915),(.739,.785),(.754,.580),(.762,.33))


def use_palette():
    R.COLORS[:] = PAL.values()
    # Shared farm coachwork helper remapped to this single independent atlas.
    G.P = S.P = F.P = P


def loop(z, factor=1, delta=0):
    return [(cos(i*tau/N)*(RADIUS_X*factor+delta),z,
             CENTRE_H+sin(i*tau/N)*(RADIUS_H*factor+delta)) for i in range(N)]


def ellipsis_angle(theta, z, delta=0):
    return (cos(theta)*(RADIUS_X+delta), z,
            CENTRE_H+sin(theta)*(RADIUS_H+delta))


def cistern():
    """True oval body and dished ends, separately bolted chassis support."""
    m = F.mesh()
    circles = [loop(z, f) for z, f in RINGS]
    for i, (a,b) in enumerate(zip(circles,circles[1:])):
        for j in range(N):
            k=(j+1)%N
            h=sin((j+.5)*tau/N)
            # The glazing, apron and tank use different color ramps.
            if -.155 <= h <= .155:
                col="Blue band enamel" if i in (3,4,5,6) else "Tank warm ivory"
            elif h>.90: col="Upper sun ivory"
            elif h>.43: col="Tank cream shoulder"
            elif h>.04: col="Tank warm ivory"
            elif h>-.79: col="Warm reflected ivory" if h>-.41 else "Tank low warm steel"
            else: col="Tank dusty underside"
            face(m,"Oval longitudinal cistern and dished bulkheads",col,(a[j],b[j],b[k],a[k]))
    face(m,"Front dished cistern face","Tank warm ivory",circles[0])
    face(m,"Rear dished cistern face","Tank cream shoulder",circles[-1][::-1])

    for z in (-.048,.630):
        # Clamped steel hoop follows the entire outside tank perimeter.
        # Tapered dark cast profiles and a thin worn rim make it readable.
        hoops=[loop(z-.019,1,.0016),loop(z-.014,1,.007),
               loop(z+.014,1,.007),loop(z+.019,1,.0016)]
        for a,b,col in zip(hoops,hoops[1:],("Band seam bright","Band seam dark","Band seam bright")):
            for j in range(N):
                k=(j+1)%N
                face(m,"Two bolted cast band clamps","Band seam bright" if a[j][2]>.55 else col,
                     (a[j],b[j],b[k],a[k]))
        # Heavy transverse bridge and lower curved saddle head (not a slab
        # or outer surrogate drawn in place of a real cylindrical vessel).
        B(m,"Frame crossmember holding the bolted saddle","Bolted keeper iron",
          0,z,.464,.078,.172,.231,.007)
        for side in (-1,1):
            seg=[(side*x,z,h) for x,h in ((.043,.225),(.102,.240),(.162,.267),(.200,.316))]
            for a,b in zip(seg,seg[1:]):
                bar(m,"Curved under-tank saddle bearing on the crossmember","Bolted keeper iron",a,b,.055,.022)
            B(m,"Clamp tang seats under the working oval tank","Band seam dark",
              side*.212,z,.037,.039,.272,.316,.008)
            T(m,"Exposed clamp saddle hex-head bolt","Painted bolt bright",
              (side*.224,z,.293),.012,"x",-.004,.010,6)
            C(m,"Tapered frame gusset strut","Bolted keeper iron",
              (side*.166,z,.187),(side*.205,z,.278),.012,.014,7)

    # Two raised real manlids elsewhere than the welded saddle bands.
    for z in (.089,.418):
        T(m,"Welded hatch neck at curved tank crown","Dry welding line",(0,z,0),
          .065,"h",.598,.626,24)
        T(m,"Raised manlid clamped to tank neck","Bolted keeper iron",(0,z,0),
          .052,"h",.617,.638,24)
        T(m,"Welded manlid pressed alloy top","Tank dusty underside",(0,z,0),
          .046,"h",.636,.644,24)
        for j in range(6):
            a=j*tau/6
            T(m,"Inspection lid bolts on machined flange","Painted bolt bright",
              (.056*cos(a),z+.056*sin(a),0),.0055,"h",.624,.630,6)
        C(m,"Independent cast manlid latch lever","Bronze cap casting",
          (.012,z-.017,.642),(.038,z+.039,.653),.007,.005,8)
        T(m,"Manlid pressure equalizer crown","Band seam dark",(-.023,z+.008,0),
          .010,"h",.639,.654,12)
    for x in (-.086,.086):
        B(m,"Narrow perforated top walking board","Pressed bridge grip",x,.287,.042,.687,.595,.609,.004)
        for j in range(16):
            B(m,"Tread raised perforation stamp","Painted bolt bright",x,.003+j*.038,
              .027,.008,.608,.612,.001)
    return m


def pipe(m, name, color, points, radius, steps=10):
    for a,b in zip(points,points[1:]):
        C(m,name,color,a,b,radius,None,steps)


def service():
    m=F.mesh()
    for s in (-1,1):
        z=(.686 if s==1 else .673)
        B(m,"Rear valance bracket for running lamps","Bolted keeper iron",s*.204,z,.079,.078,.151,.235,.008)
        T(m,"Rear ruby lamp individual lens","Red lens",(s*.213,.732,.219),.026,"z",.002,.017,16)
        T(m,"Aft amber reflective lens","Orange lens",(s*.177,.731,.186),.014,"z",-.002,.010,12)
        B(m,"Rear mitered chassis bumper","Faded alloy",s*.143,.750,.173,.063,.114,.156,.011)
    # Independent rear discharge reel bearing caps, visible wound hose and
    # forged elbows/manifold. These are visual abstractions, not engineering.
    T(m,"Hose reel steel spool core","Bolted keeper iron",
      (-.044,.667,.212),.036,"x",-.108,.115,16)
    for x in (-.159,.062):
        T(m,"Cut circular rotating hose reel discs","Road hub",(x,.667,.212),
          .066,"x",-.007,.007,20)
        T(m,"Exposed reel spun hub","Painted bolt bright",(x-.006,.667,.212),
          .023,"x",-.008,.007,12)
    for i in range(8):
        x=-.141+i*.025
        pts=[]
        for j in range(17):
            a=j*tau/16
            pts.append((x,.667+.045*cos(a),.212+.045*sin(a)))
        pipe(m,"Wound and individually spaced rubber hose wraps","Worn reel rubber",pts,.011,6)
    pipe(m,"Tank discharge pipe with cast elbows","Discharge pipe gray",
         [(.052,.573,.251),(.096,.599,.238),(.150,.625,.212),(.166,.665,.199),(.166,.699,.199)],.018,12)
    T(m,"Machined discharge union","Bronze cap casting",(.166,.699,.199),.028,"z",-.007,.015,12)
    T(m,"Capped transfer port","Valve worn red",(.166,.716,.199),.021,"z",-.003,.009,12)
    T(m,"Valve rising stem","Discharge pipe gray",(.157,.645,0),.008,"h",.211,.257,10)
    T(m,"Round red butterfly valve handle","Valve worn red",(.157,.645,0),.028,"h",.251,.259,12)

    for x in (-.112,-.060):
        pipe(m,"Rear service ladder steel side tubes","Discharge pipe gray",
          [(x,.757,.284),(x,.779,.349),(x,.781,.483),(x,.746,.575),
           (x,.705,.618),(x,.669,.654),(x,.619,.654),(x,.589,.607)],.0075,9)
    for z,h in ((.775,.322),(.781,.380),(.782,.432),(.778,.486),(.761,.538),(.724,.593)):
        C(m,"Service ladder knurled step rungs","Faded alloy",(-.113,z,h),(-.060,z,h),.006,.006,8)
    for h,z in ((.327,.751),(.493,.744)):
        for x in (-.112,-.060):
            C(m,"Bolted tank ladder stand-off","Bolted keeper iron",(x,z,h),(x,z+.022,h),.0055,.0055,6)
    # An original, unbranded, small diamond below the fleet identity.
    cx,zh=.095,.420
    face(m,"Rear cut amber warning enamel diamond","Warning diamond amber",(
        (cx-.024,.757,zh),(cx,.761,zh+.029),(cx+.024,.756,zh),(cx,.762,zh-.029)))
    B(m,"Rear horizontal road plate","Black plate",0,.783,.113,.011,.143,.168,.003)
    return m


def label(m):
    # Hand-laid custom bitmap letter geometry, mapped to physical oval
    # cylinder tangent rather than a decal quad floating past the shoulders.
    glyph={
      "O":("0110","1001","1001","1001","0110"),
      "I":("111","010","010","010","111"),
      "L":("1000","1000","1000","1000","1111"),
      "W":("10001","10001","10101","10101","01010"),
      "1":("010","110","010","010","111"),
      "3":("111","001","110","001","111"),
      "2":("110","001","010","100","111"),
      " ":("00","00","00","00","00"),
    }
    for s in (-1,1):
        for word, zc, step in (("OIL",.292,.028),("W 132",.278,.012)):
            n=sum(len(glyph[ch][0])+1 for ch in word)
            pos=0
            # Fleet lettering centered on the blue equatorial line. A small
            # company number is repeated lower, on the shaded cream panel.
            tilt0= -.094 if word=="OIL" else -.36
            size=.045 if word=="OIL" else .032
            for ch in word:
                for j,row in enumerate(glyph[ch]):
                    for i,pixel in enumerate(row):
                        if pixel!="1":continue
                        z=zc+s*(pos+i-n/2)*step
                        a=tilt0+(4-j)*size
                        points=[ellipsis_angle(t if s>0 else pi-t, yy,.002)
                                for t,yy in ((a,z),(a,z+s*step*.90),
                                    (a+size*.90,z+s*step*.90),(a+size*.90,z))]
                        face(m,"Painted curved body oil and fleet identity",
                             "Emboss cream lettering" if word=="OIL" else "Blue band enamel",points)
                pos+=len(glyph[ch][0])+1


def parts():
    under=F.mesh()
    F.irons(under,False)
    cab=F.mesh()
    F.cab(cab,False)
    # The sister vehicles share the Witcombe family running gear, not the
    # factory's Hereford-painted side identity or an open cargo bin.
    for part in ("Original raised fleet nameplate characters",
                 "Pressed rear body rail carrying period lamps",
                 "Ruby stop lamp in grease resistant ring",
                 "Upper amber rear direction winker",
                 "Period aft license plate with raised surround"):
        cab.vertices.pop(part)
        cab.parts.pop(part)
    tank=cistern()
    label(tank)
    return (("Witcombe cab and glazed panes",cab),
            ("Chassis and tires",under),("Closed tank and bolted mount",tank),
            ("Rear ladder, hose and discharge",service()))


def combine(groups):
    body=F.mesh()
    for title,m in groups:
        for name, faces in m.parts.items():
            v=m.vertices[name]
            for idx,mat in faces:
                body.face(name,mat,[v[i] for i in idx])
    return body


def save_atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    (R.TEXTURES/f"bl_{NAME}_atlas.png").write_bytes(
        b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))
        +chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b""))


def preview(sc,mats,path):
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003))
    bpy.context.object.data.materials.append(mats[P["Review road"]])
    bpy.ops.object.camera_add(location=(1.7,-2.45,1.33))
    c=bpy.context.object
    c.rotation_euler=(Vector((0,0,.312))-c.location).to_track_quat("-Z","Y").to_euler()
    c.data.type="ORTHO"
    c.data.ortho_scale=1.95
    sc.camera=c
    sc.world=bpy.data.worlds.new("Temperate oil yard")
    sc.world.color=(.16,.20,.24)
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x,sc.render.resolution_y=1400,950
    sh=sc.display.shading
    sh.light="STUDIO"
    sh.color_type="MATERIAL"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    sh.background_type="WORLD"
    sc.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    use_palette()
    groups=parts()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · Witcombe Oil Tanker #132"
    sc["Native mount"]="Uniform visual_size=.42; world tire datum Y0; front -Z."
    sc["Stock catalog"]="OpenTTD 14.1 global 132, road index 16, image 3, 21,000 L nominal, closed body at all loads."
    sc["Art provenance"]="Original meshes Swatch atlas; CC BY 2.0 photographs consulted for period details only; see art/witcombe_oil_tanker.md."
    sc.view_settings.view_transform="Standard"
    materials=R.materials()
    for color,i in P.items():
        mat=materials[i]
        mat.name=color
        node=mat.node_tree.nodes["Principled BSDF"]
        node.inputs["Metallic"].default_value=.38 if any(p in color.lower() for p in ("steel","iron","alloy","nickel","machined")) else 0
        node.inputs["Roughness"].default_value=.34 if "glass" in color.lower() else .63
    for title,m in groups:
        F.linked(title,m,materials,sc)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.29)
                v.region_3d.view_distance=2.65
                v.region_3d.view_rotation=Vector((1.44,-2.1,1.16)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{NAME}.blend"),compress=True)
    p=R.MODELS/f"bl_{NAME}.obj"
    R.export_obj(p,S.local_obj(combine(groups)))
    data=p.read_text()
    p.write_text("# Original Witcombe Oil Tanker #132, tools/build_witcombe_oil_tanker_art.py\n"+data.split("\n",1)[1])
    save_atlas()
    if path:=os.getenv("WITCOMBE_OIL_REVIEW"):
        preview(sc,materials,path)


if __name__=="__main__":
    main()
