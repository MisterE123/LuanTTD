#!/usr/bin/env python3
"""Original purpose-built Class 86 electric for stock SH '30' (#23)."""
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
B,D,L,Pipe=J.B,J.Disk,J.Lathe,J.Pipe
NAME="bl_rail_sh_30"
PAL={
 "Electric enamel blue":"397aa5","Blue sunward edge":"65a0bc","Blue shadow coachwork":"2f4f6d",
 "Side cooler steel":"51666e","Cab lower vent blue":"386485","Grey blue lower band":"8b9b9c",
 "Upper cab roof pale":"c0c6b8","Roof paint slate":"565c5f","Roof deep trough":"384348",
 "Ochron yellow warning apron":"e1b53f","Yellow shoulder highlight":"efc960","Lower warning shade":"ae8b35",
 "Dark glazing rubber":"303b42","Blue charcoal glazing":"365460","Sky reflection":"759ba5",
 "Side window grey gradient":"5b7982","Whistle intake graphite":"384247","Dark cooler trough":"29383f",
 "Vent sunlit nickel":"87938e","Readably black headcode":"33383b","Cream machine numerals":"e9dfaa",
 "Headlamp ivory glass":"f7e3ae","Ruby lens red":"b95046","Rust-red mechanical beam":"975346",
 "Bright coupling nipple nickel":"9fa8a0","Frame iron":"393f43","Bogies matte cast steel":"4e585d",
 "Traction gear steel":"636e6c","Dark wheel tread":"555f63","Wheel inner flange":"444e54",
 "Wheel hub nickel":"798b8a","Power contact dark copper":"655a43","Power contact polished copper":"c6a575",
 "Isolator cream glazed ceramic":"cfc2a1","High wire gantry steel":"72827d","Roof gasket alloy":"78877f",
 "Review ballast":"827d71",
}
P={k:i for i,k in enumerate(PAL)}
AXLES=(-.292,-.214,.214,.292)
RAD=.045
CROWN=.545
CONTACT=.784
SHOE_Z=.031


def setup():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=P


def mesh():return R.Mesh(R.terrain_height(0))


def F(m,n,c,v):m.face(n,P[c],v)


def prof(w,e):
    return [(-.79*w,.219),(.79*w,.219),(w,.222),(w,.291),(w,.451),
       (.98*w,.485),(.86*w,e-.018),(.56*w,e),(-.56*w,e),
       (-.86*w,e-.018),(-.98*w,.485),(-w,.451),(-w,.291),(-w,.222)]


SECTIONS=((-.429,.147,.516),(-.404,.177,.532),(-.366,.198,.539),
          (-.306,.215,CROWN),(-.236,.217,CROWN),(.236,.217,CROWN),
          (.306,.215,CROWN),(.366,.198,.539),(.404,.177,.532),(.429,.147,.516))


def locomotive_shell(m):
    sections=[(z,prof(w,h)) for z,w,h in SECTIONS]
    for (a,p),(b,q) in zip(sections,sections[1:]):
        is_cab=min(abs(a),abs(b))>=.306
        for i in range(len(p)):
            j=(i+1)%len(p)
            if i in (5,6,7,8,9):
                c="Upper cab roof pale" if is_cab else ("Roof paint slate" if i in (6,7,8) else "Roof deep trough")
                name="Long shallow steel roof and sculpted pale cab crowns"
            elif i in (0,1,13):c,name="Roof deep trough","Continuous AL6 base contour"
            elif i in (2,12):c,name="Grey blue lower band","Low greyblue skirt dividing faceted sides"
            else:
                c="Blue sunward edge" if i in (4,10) else "Electric enamel blue"
                if min(abs(a),abs(b))>.368:c="Yellow shoulder highlight" if i in (2,3,11,12) else c
                name="Original long rail blue pressed side and stepped AL6 cab"
            F(m,name,c,((p[i][0],a,p[i][1]),(q[i][0],b,q[i][1]),
                        (q[j][0],b,q[j][1]),(p[j][0],a,p[j][1])))
    for z,sec in (sections[0],sections[-1]):
        pts=[(x,z,h) for x,h in sec]
        F(m,"One distinctive near-upright faceted cab face each end",
          "Blue shadow coachwork",pts if z<0 else pts[::-1])


def face(m,n,c,s,q):
    # Positive determinant half-turn, preserving both pairs of cab normals.
    F(m,n,c,[(s*x,s*z,h) for x,z,h in q])


def cab(m):
    for e in (-1,1):
        face(m,"Two bright recessed yellow warning faces","Ochron yellow warning apron",e,
             [(-.134,-.431,.223),(.134,-.431,.223),(.146,-.431,.247),(.142,-.431,.355),
              (-.142,-.431,.355),(-.146,-.431,.247)])
        face(m,"Thin highlighted metal cab yellow sill","Yellow shoulder highlight",e,
             [(-.137,-.434,.345),(.137,-.434,.345),(.139,-.430,.359),(-.139,-.430,.359)])
        face(m,"Raised window surround around divided class 86 windscreen","Upper cab roof pale",e,
             [(-.142,-.430,.357),(.142,-.430,.357),(.136,-.430,.486),(-.136,-.430,.486)])
        for side in (-1,1):
            x0,x1=sorted((side*.012,side*.131))
            p=((x0,-.432,.365),(x1,-.432,.365),(x1*.94,-.432,.477),(x0*.94,-.432,.477))
            face(m,"Two inset panoramic rectangular cab panes on each end","Dark glazing rubber",e,p)
            q=[(x0+.005,-.434,.372),(x1-.005,-.434,.372),
               (x1*.94-.006,-.434,.469),(x0*.94+.006,-.434,.469)]
            face(m,"Physically inset panoramic electric locomotive cab glass","Blue charcoal glazing",e,q)
            q=((x0+.007,-.436,.438),(x1-.007,-.436,.438),
                (x1-.010,-.436,.456),(x0+.009,-.436,.456))
            face(m,"Narrow gradient horizon in AL6 windscreens","Sky reflection",e,q)
            Pipe(m,"Wiper arm pressed into each driving windscreen","Dark glazing rubber",
                 (e*side*.055,-e*.438,.380),(e*side*.104,-e*.438,.425),.003,7)
            q=(e*side*.093,-e*.438,.272)
            D(m,"Little independent vertical headlamp bezels", "Dark glazing rubber",q,.012,"z",-.005,.005,14)
            D(m,"Posed warm round headlamp glass", "Headlamp ivory glass",
              (q[0],q[1]-e*.004,q[2]),.0075,"z",-.002,.002,12)
            D(m,"Independent red small run tail lamp", "Ruby lens red",
              (e*side*.050,-e*.438,.243),.007,"z",-.002,.002,12)
        B(m,"Period rounded lower cab center company plate", "Readably black headcode",
          0,-e*.433,.062,.007,.291,.325,.003)
        for x in (-.021,-.005,.011,.023):
            B(m,"Original narrow cream fleet plate characters", "Cream machine numerals",
              x,-e*.438,.005,.003,.299,.317,.0007)
        for s in (-1,1):
            # Side windows sit along the true tapered cab shell, with no
            # detached side wall, used give that recognizable wraparound.
            coords=((s*.182,e*.399,.351),(s*.202,e*.356,.351),
                    (s*.197,e*.356,.467),(s*.177,e*.399,.465))
            facepts=coords if s==e else coords[::-1]
            F(m,"Fitted tapered cab quarter side window gasket","Dark glazing rubber",facepts)
            x=((s*.186,e*.394,.361),(s*.199,e*.360,.361),
               (s*.194,e*.360,.456),(s*.181,e*.394,.453))
            F(m,"Individual cool glossy cab quarter window","Side window grey gradient",x if s==e else x[::-1])
            for h in (.256,.284):
                B(m,"Small real metal boarding stair lips below each side cab",
                  "Roof gasket alloy",s*.187,e*.329,.044,.042,h-.085,h-.076,.003)
            Pipe(m,"Narrow tall side grab rod just outside the cab", "Roof gasket alloy",
              (s*.205,e*.349,.239),(s*.208,e*.349,.345),.0033,8)


def drive_and_vents(m):
    for s in (-1,1):
        for y,w in ((-.190,.082),(-.069,.083),(.071,.085),(.186,.071)):
            B(m,"Long hood dark slatted cooler bank", "Dark cooler trough",
              s*.220,y,.010,w,.348,.432,.004)
            for k in range(7):
                h=.358+k*.010
                B(m,"Separately pressed outboard horizontal AL6 louvers",
                  "Vent sunlit nickel" if k in (0,6) else "Side cooler steel",
                  s*.226,y,.005,w-.014,h,h+.004,.0007)
        B(m,"Slim long bright upper side and door rim strip","Upper cab roof pale",
          s*.216,0,.005,.540,.454,.462,.001)
        B(m,"Long faded dark sill under locomotive equipment", "Blue shadow coachwork",
          s*.215,0,.018,.670,.187,.224,.005)
        B(m,"Raised rectangular blue cab shoulder latch plate","Cab lower vent blue",
          s*.215,.315,.012,.045,.311,.332,.003)
        B(m,"Inset contrasting small original SH30 side number plate","Readably black headcode",
          s*.222,0,.012,.094,.275,.310,.002)
        for z in (-.023,-.011,.001,.013,.025):
            B(m,"Original cream miniature square AL6 stencil strokes","Cream machine numerals",
              s*.229,z,.0022,.0044,.290,.302,.0003)
        D(m,"Underframe air receiver between bogies","Traction gear steel",
          (s*.127,.049,.098),.031,"z",-.100,.069,14)
    J.shaped(m,"Tapered structural underframe full length","Frame iron",[
      (-.108,-.414),(.108,-.414),(.168,-.359),(.189,-.271),(.190,.271),
       (.168,.359),(.108,.414),(-.108,.414),(-.168,.359),(-.190,.271),
       (-.189,-.271),(-.168,-.359)],.121,.189,"Bogies matte cast steel")
    for e in (-1,1):
        B(m,"End red steel buffer beam with outboard steps","Rust-red mechanical beam",
          0,e*.419,.207,.028,.125,.206,.006)
        for s in (-1,1):
            D(m,"Taper-in short steel buffer shaft","Traction gear steel",
              (s*.081,e*.420,.162),.018,"z",-.012,.012,15)
            D(m,"Separate buffing contact pad face","Bright coupling nipple nickel",
              (s*.081,e*.432,.162),.020,"z",-.003,.003,16)
        B(m,"Narrow recessed draw guide","Frame iron",0,e*.446,.054,.046,.133,.184,.005)
        B(m,"Steel center mount forward extension","Traction gear steel",0,e*.478,.023,.023,.144,.170,.004)
        B(m,"Coupler knuckles","Bright coupling nipple nickel",0,e*.494,.0105,.010,.146,.168,.002)


def collectors(m):
    # One AL6 raised collector, matching the contemporary single pantograph.
    # The other end has stand-off insulators and low switchgear, not a copy.
    for s in (-1,1):
        for z in (.043,.171,-.177,-.095):
            L(m,"Genuine turned stacked roof ceramic standoffs",
              [(.538,.018),(.553,.014),(.560,.017),(.564,.013),(.571,.017),(.576,.012)],
              "h",(s*.070,z,0),("Roof gasket alloy","Isolator cream glazed ceramic"),12)
        B(m,"Painted rectangular scissor heel foot attached to roof",
          "Roof paint slate",s*.071,.104,.034,.143,.567,.583,.005)
        a=(s*.066,.053,.580);b=(s*.061,.167,.688);c=(s*.052,SHOE_Z,.774)
        G.bar(m,"Linked steel lower swinging pantograph arms",
              "High wire gantry steel",a,b,.016,.014)
        G.bar(m,"Slender stand-off upper support for broad collector",
              "Roof gasket alloy",b,c,.012,.012)
        D(m,"Machined visible pantograph elbow pivot bush","Power contact dark copper",
          (s*.060,.167,.688),.010,"x",-.007,.007,12)
        G.bar(m,"Fixed smaller parallelogram lower return arm",
              "Dark cooler trough",(s*.047,.081,.581),(s*.049,.151,.656),.006,.006)
        G.bar(m,"Fixed smaller parallelogram upper return arm",
              "Dark cooler trough",(s*.049,.151,.656),(s*.041,SHOE_Z,.767),.006,.006)
        B(m,"Pressed roof blue black switching cylinder isolator mount",
          "Roof deep trough",s*.058,-.145,.039,.108,.573,.591,.005)
        Pipe(m,"Independent lead and service feeder to low switchgear","Power contact polished copper",
             (s*.079,-.146,.591),(s*.079,-.054,.592),.0052,8)
    B(m,"Transverse working contact shoe, level at the specified wire",
      "Power contact dark copper",0,SHOE_Z,.166,.025,CONTACT-.009,CONTACT,.0021)
    B(m,"Thin polished outer contact edge exactly at the wire datum",
      "Power contact polished copper",0,SHOE_Z,.150,.014,CONTACT-.003,CONTACT,.0014)
    for s in (-1,1):
        G.bar(m,"Slightly bent contact shoe horns clear of the wire",
          "Roof gasket alloy",(s*.077,SHOE_Z,.778),(s*.104,SHOE_Z,.762),.010,.013)


def bogie(m,z):
    B(m,"Two independent B0-B0 cast electric bogie sideframes",
      "Bogies matte cast steel",0,z,.447,.187,.069,.116,.009)
    for s in (-1,1):
        B(m,"Two separated inboard electric axle motor housings", "Frame iron",
          s*.141,z,.083,.158,.053,.079,.006)
        for t in (-.046,.046):
            for j in range(3):
                D(m,"Layered compact coil suspension at the bogie axle",
                  "Traction gear steel",(s*.202,z+t,0),.010,"h",.091+j*.008,.096+j*.008,9)


def wheel(m,z):
    D(m,"Full width native SH30 axle shaft","Frame iron",(0,z,RAD),.010,"x",-.221,.221,12)
    for s,side in ((-1,"L"),(1,"R")):
        x=s*.212
        a,b=sorted((-s*.029,s*.047))
        L(m,"Rolling tread SH30 "+side,[(a,.73*RAD),(a,RAD),(-.005,RAD),(.005,RAD),
               (b,RAD),(b,.73*RAD),(a,.73*RAD)],"x",(x,z,RAD),
               ("Dark wheel tread","Dark wheel tread","Dark wheel tread","Dark wheel tread","Frame iron"),24,False,False)
        a,b=sorted((-s*.042,-s*.035))
        L(m,"True inward SH30 flange below contact plane",[(a,.70*RAD),(a,RAD+.009),
               (b,RAD+.009),(b,.70*RAD),(a,.70*RAD)],"x",(x,z,RAD),("Wheel inner flange",),24,False,False)
        D(m,"Four pairs of independent resilient wheel discs","Bogies matte cast steel",
          (x+s*.034,z,RAD),.036,"x",-.006,.006,18)
        D(m,"Exposed small axle oil cap","Wheel hub nickel",
          (x+s*.041,z,RAD),.013,"x",-.005,.005,12)


def run(m):
    locomotive_shell(m);cab(m);drive_and_vents(m)
    for z in (-.253,.253):bogie(m,z)
    for z in AXLES:wheel(m,z)
    collectors(m)


def atlas(name=NAME, palette=PAL):
    row=b"".join(bytes.fromhex(v)*8 for v in palette.values())
    def c(x,d):return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(name+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
        c(b"IHDR",struct.pack(">IIBBBBB",len(palette)*8,8,8,2,0,0,0))+
        c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    mats=R.materials()
    for c,m in zip(P,mats):
        m.name=c
        p=m.node_tree.nodes["Principled BSDF"]
        p.inputs["Metallic"].default_value=.37 if any(t in c.lower() for t in ("copper","steel","nickel")) else .04
        p.inputs["Roughness"].default_value=.37 if "glaz" in c.lower() else .65
    return mats


def write_assets(*, name, filename, model_name, stock, provenance, credit, palette,
                 body, wheels=wheel, collector=collectors, review=None):
    """Write a rigid Class 86/87 single-head model and editable scene."""
    assert palette.keys()==PAL.keys(), "same ordered UV swatches"
    assert tuple(palette)==tuple(PAL), "swatch order is part of the UV contract"
    setup();R.COLORS[:]=palette.values()
    m=mesh();body(m)
    for z in (-.253,.253):bogie(m,z)
    for z in AXLES:wheels(m,z)
    collector(m)
    p=R.MODELS/(name+".obj")
    R.export_obj(p,W.local_obj(m))
    data=p.read_text()
    p.write_text(credit+"\n"+data.split("\n",1)[1])
    atlas(name,palette)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.view_settings.view_transform="Standard"
    sc.name="LuanTTD · "+model_name
    sc["Stock"]=stock
    sc["Mount"]="Scale 1, .424 rail gauge, -Z nose, local Y0 rail. Raised collector local Y=.784 (base+1.398 on flat track)."
    sc["Provenance"]=provenance
    pal=colors()
    for name,f in (("Pressed electric body, cabs and cooling banks",
                  body),
                 ("Single live pantograph and independent switching equipment",collector),
                 ("Separate two bogie castings and suspended traction motors",lambda q:[bogie(q,z) for z in (-.253,.253)])):
        q=mesh();f(q);J.geometry(sc,name,q,pal)
    for i,z in enumerate(AXLES,1):
        q=mesh();wheels(q,z)
        g=J.geometry(sc,f"Editable axle {i} wheelset",q,pal)
        ax=bpy.data.objects.new(f"Transverse axle pivot {i}",None)
        g.objects.link(ax)
        ax.empty_display_type="CIRCLE";ax.empty_display_size=.056
        ax.location=(0,z,RAD)
        for o in tuple(g.objects):
            if o!=ax:o.parent=ax;o.location=(0,-z,-RAD)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.386)
                v.region_3d.view_rotation=Vector((.85,-1.03,.65)).to_track_quat("Z","Y")
                v.region_3d.view_distance=2.13
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/f"art/{filename}.blend"),compress=True)
    if review:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),model_name),review)


def main():
    write_assets(name=NAME, filename="rail_sh_30", model_name="SH '30' electric / original Class 86",
                 stock="14.1 global engine #23, image20, normal rigid one-part electric.",
                 provenance="Original model, photograph reference and OpenGFX visual cue only; art/rail_sh_30.md.",
                 credit="# Original stock SH '30' Class 86 · tools/build_sh_30_art.py", palette=PAL,
                 body=lambda m:(locomotive_shell(m),cab(m),drive_and_vents(m)),
                 review=os.getenv("SH_30_REVIEW"))


if __name__=="__main__":
    main()
