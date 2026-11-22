#!/usr/bin/env python3
"""Original Class 101-inspired Manley–Morel native powered half (#11).
Set MANLEY_MOREL_REVIEW for a studio PNG. Each instance faces -Z when neutral.
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
B,D,L,Pipe,Gbeam=J.B,J.Disk,J.Lathe,J.Pipe,G.bar
NAME="bl_rail_manley_morel"
PAL={
 "DMU deep green":"2f695b","Dark under sill green":"2a4f48","Door shadow green":"2c584e",
 "Green raised edge":"568675","Light aged panel green":"3d7566","Pane cream rubber":"b9c2aa",
 "Bright cream stripe":"d9d2af","Upper frame and fillet":"849b8c","Warm yellow cab apron":"d7ac4d",
 "Amber glancing highlight":"ecd281","Cashmere painted corner":"a88e51","Lower seal graphite":"424b48",
 "Slate black rail equipment":"343e3d","Deep glass blue":"385c68","Mid glass blue":"668f97",
 "Upper sky":"8eafb0","Window shadow":"2f4b53","Window olive reflection":"728a78",
 "Roof lead blue":"646f73","Roof weather warm":"758383","Roof silver grey":"8b9894",
 "Roof end band":"555e61","Tender notice ivory":"d9d1ad","Destination dark plate":"343b3a",
 "Cast underframe graphite":"414b48","Dry tire iron":"56605b","Steel wheel flange":"495650",
 "Steel running strip":"85958c","Wheel center grease":"717c72","Fresh nickel pin":"a4ada0",
 "Air reservoir blue-grey":"687572","Brake link iron":"535a55","Warm rear ruby":"b34c46",
 "Cab lamp warm":"f4e0a3","Beam burnt oxide":"885147","Buffer mark grey":"a2aca3",
 "Inner gangway bellows":"343c3a","Inner gangway bright edge":"69726a","Review ballast":"827d71",
}
P={k:i for i,k in enumerate(PAL)}
AXLES=(-.262,-.192,.194,.266)
RAD=.044


def setup():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=P


def mesh():
    return R.Mesh(R.terrain_height(0))


def face(m,n,c,p):
    m.face(n,P[c],p)


def body_section(w,hi):
    return [(-.83*w,.170),(.83*w,.170),(w,.212),(w,.287),(w,.428),(.988*w,.457),
            (.915*w,.478),(.801*w,hi-.019),(.569*w,hi-.007),(.323*w,hi-.002),(0,hi),
            (-.323*w,hi-.002),(-.569*w,hi-.007),(-.801*w,hi-.019),
            (-.915*w,.478),(-.988*w,.457),(-w,.428),(-w,.287),(-w,.212)]


STATIONS=((-.425,.148,.508),(-.409,.171,.519),(-.375,.194,.531),(-.322,.216,.541),
          (-.246,.219,.542),(.238,.219,.542),(.319,.215,.541),
          (.368,.196,.531),(.403,.172,.515),(.421,.146,.501))


def cast(m):
    sections=[(z,body_section(x,h)) for z,x,h in STATIONS]
    for (a,q),(b,r) in zip(sections,sections[1:]):
        for k in range(len(q)):
            i=(k+1)%len(q)
            roof=k in range(6,14)
            if roof:
                c=("Roof silver grey" if k in (8,9,10,11)
                   else "Roof weather warm" if k in (7,12) else "Roof lead blue")
                if a<-.41 or b>.406:c="Roof end band"
            elif k in (0,1,18):c="Dark under sill green"
            elif k in (2,17):c="DMU deep green"
            elif k in (3,16):c="Light aged panel green"
            else:c="Green raised edge"
            if not roof and -.426<=a<=-.374 and k not in (0,1,18):
                c="Cashmere painted corner" if k in (2,17) else c
            name=("Long smooth rolled Class 101 roof" if roof else
                  "Tapered modular railcar body shell")
            face(m,name,c,((q[k][0],a,q[k][1]),(r[k][0],b,r[k][1]),
                           (r[i][0],b,r[i][1]),(q[i][0],a,q[i][1])))
    for z,ring in (sections[0],sections[-1]):
        t=[(x,z,h) for x,h in ring]
        face(m,"Unique outward cab and inward car end sheets",
          "DMU deep green" if z<0 else "Dark under sill green",t if z<0 else t[::-1])


def front_face(m,name,c,x0,x1,z,h0,h1):
    p=((x0,z,h0),(x1,z,h0),(x1,z,h1),(x0,z,h1))
    face(m,name,c,p if z<0 else p[::-1])


def nose(m):
    # Distinct outward front: three pane cab with side returns, destination
    # board above, signature shallow warning panel and two low lamp cases.
    q=[(-.133,-.427,.224),(.133,-.427,.224),(.145,-.427,.243),(.136,-.427,.340),
       (-.136,-.427,.340),(-.145,-.427,.243)]
    face(m,"Broad curved yellow half warning cab apron","Warm yellow cab apron",q)
    front_face(m,"Yellow lip below three windscreen frames","Amber glancing highlight",-.133,.133,-.430,.327,.336)
    front_face(m,"Deep cab windshield surround with central and flanking panes","Slate black rail equipment",
      -.139,.139,-.428,.344,.457)
    for i,(x0,x1) in enumerate(((-.126,-.064),(-.052,.052),(.064,.126))):
        glass=[(x0,-.432,.359),(x1,-.432,.359),(x1*.93,-.432,.444),(x0*.93,-.432,.444)]
        face(m,"Three inset panoramic driving cab windscreens","Deep glass blue",glass)
        front_face(m,"Distinct upper pale horizontal windscreen sky reflections","Upper sky",
          x0*.94,x1*.94,-.434,.422,.437)
        front_face(m,"Olive line from below the horizon in each driver window","Window olive reflection",
          x0*.94,x1*.94,-.434,.374,.380)
        k=(x0+x1)*.5
        Pipe(m,"Windshield wiper support and tilted blade","Lower seal graphite",
             (k-.011,-.436,.365),(k+.015,-.436,.400),.0028,7)
    B(m,"Rounded high inset destination headslot","Destination dark plate",
      0,-.426,.13,.012,.457,.483,.004)
    chars(m,"DMU",0,-.436,.468,.0045)
    for s in (-1,1):
        x=s*.095
        D(m,"Individual yellow apron marker bowl with cast lip","Lower seal graphite",(x,-.431,.268),
          .012,"z",-.004,.004,12)
        D(m,"Small outward warm front lamp inset glass","Cab lamp warm",(x,-.436,.268),
          .0075,"z",-.003,.003,12)
        D(m,"Inboard ruby rear lamp on each outward cab","Warm rear ruby",(s*.036,-.430,.249),
          .0064,"z",-.004,.003,11)
        Pipe(m,"Short outside front cab step handrail","Pane cream rubber",
          (s*.144,-.425,.232),(s*.142,-.424,.317),.003,8)
    B(m,"Cab face rust-red bottom collision strip","Beam burnt oxide",
      0,-.421,.241,.023,.172,.221,.007)


def position(z,h,s,dr):
    # Body section at h: side windows and trim follow the real bevel, not
    # rectangle outlines floating outside the cab's rounded corners.
    for (az,a,u),(bz,b,v) in zip(STATIONS,STATIONS[1:]):
        if az<=z<=bz:
            t=(z-az)/(bz-az)
            profile=[((1-t)*x+t*y,(1-t)*e+t*f) for (x,e),(y,f) in
                     zip(body_section(a,u),body_section(b,v))]
            for (x,e),(y,f) in zip(profile[1:8],profile[2:9]):
                if e<=h<=f and e<f:
                    return s*(x+(y-x)*(h-e)/(f-e)+dr),z,h
    raise ValueError((z,h,s,dr))


def panel(m,n,c,s,z0,z1,h0,h1,offset):
    pts=[z0,*[z for z,w,h in STATIONS if z0<z<z1],z1]
    for a,b in zip(pts,pts[1:]):
        p=[position(z,e,s,offset) for z,e in ((a,h0),(b,h0),(b,h1),(a,h1))]
        face(m,n,c,p if s>0 else p[::-1])


def panes(m):
    for s in (-1,1):
        for a,b in zip(STATIONS,STATIONS[1:]):
            for h,col in ((.286,"Bright cream stripe"),(.452,"Pane cream rubber")):
                p=position(a[0],h,s,.0023)
                q=position(b[0],h,s,.0023)
                Pipe(m,"Real continuous paired railcar waist and header lining",col,p,q,.0017,7)
        for lo,hi,role in ((-.392,-.322,"driving quarter"),(-.308,-.251,"cab door"),
                    (-.234,-.140,"saloon"),(-.121,-.031,"saloon"),(-.011,.080,"saloon"),
                    (.098,.160,"passenger door"),(.177,.263,"saloon"),(.281,.363,"luggage door")):
            h0,h1=(.329,.440) if "door" not in role else (.337,.432)
            panel(m,"Inset passenger and driver glazings bounded by metal surround",
                  "Pane cream rubber",s,lo,hi,h0,h1,.0040)
            panel(m,"Pale grey-blue saloon window faces mounted behind edge",
                  "Mid glass blue",s,lo+.0045,hi-.0045,h0+.005,h1-.005,.0060)
            panel(m,"Muted interior tint behind real partitioned saloon glazing",
                  "Deep glass blue",s,lo+.007,hi-.007,h0+.010,h0+.065,.0072)
            panel(m,"Upper moving-light band across milled saloon glass", "Upper sky",
                  s,lo+.009,hi-.009,h1-.029,h1-.012,.0074)
            if role=="saloon":
                for frac in (.27,.73):
                    z=lo+(hi-lo)*frac
                    panel(m,"Paired inset sliding top light dividers", "Pane cream rubber",
                          s,z-.0014,z+.0014,h1-.044,h1-.006,.0087)
            if "door" in role:
                for z in (lo-.004,hi+.004):
                    panel(m,"Pressed removable door seam", "Door shadow green",
                          s,z-.0012,z+.0012,.200,.451,.0037)
                panel(m,"Tiny bright carriage door latch", "Pane cream rubber",
                      s,hi-.018,hi-.003,.299,.310,.0067)
                B(m,"Under-door removable pressed stair", "Brake link iron",
                  s*.199,(lo+hi)/2,.049,hi-lo,.159,.169,.003)
        # Specific dark intake vents distinguish powered halves from trailers.
        for z in (-.157,.141,.302):
            for j in range(4):
                h=.213+j*.006
                panel(m,"Power unit lower steel side grilles","Door shadow green",s,z-.018,z+.018,h,h+.0024,.0028)
        panel(m,"Dark inset small number / class fleet plate", "Door shadow green",
              s,-.104,-.031,.226,.260,.0029)
        chars(m,"11",s*.223,-.067,.238,.0047,s)


def chars(m,text,x,z,h,step,s=None):
    table={
       "D":("110","101","101","101","110"),
       "M":("101","111","111","101","101"),
       "U":("101","101","101","101","111"),
       "1":("010","110","010","010","111"),
    }
    for i,ch in enumerate(text):
        for j,row in enumerate(table[ch]):
            for k,yes in enumerate(row):
                if yes=="1":
                    j0=(i*4+k-2*len(text)+.5)*step
                    if s is None:
                        B(m,"Inlaid original cab DMU and class marks", "Tender notice ivory",
                          x+j0,z,step*.85,.0023,h+(4-j)*step,h+(4-j+.86)*step,.0001)
                    else:
                        B(m,"Inlaid original cab DMU and class marks", "Tender notice ivory",
                          x,z+s*j0,.0023,step*.85,h+(4-j)*step,h+(4-j+.86)*step,.0001)


def gangway(m):
    # Flat inner face: a different bellows/door shape, with no outward
    # windows or lights. Leave plane space to the opposing face on a curve.
    B(m,"Closed inner passenger vestibule bulkhead", "Door shadow green",
      0,.421,.181,.021,.193,.479,.008)
    for s in (-1,1):
        B(m,"Dark inner rubber gangway accordion", "Inner gangway bellows",
          s*.050,.438,.025,.029,.212,.462,.005)
        for z in (.434,.443,.449):
            B(m,"Three individual edge bellows folds", "Inner gangway bright edge",
              s*.053,z,.026,.004,.219,.454,.001)
        for h in (.220,.445):
            Pipe(m,"Vestibule inside closed hose return", "Lower seal graphite",
              (s*.053,.421,h),(s*.076,.433,h),.0043,7)
    B(m,"Inner vestibule flex cover top", "Inner gangway bellows",0,.437,.114,.031,.450,.466,.004)
    B(m,"Wood sill to the inner connection", "Inner gangway bright edge",
      0,.439,.111,.034,.204,.216,.002)
    B(m,"Single small deep inner vestibule window", "Window shadow",
      0,.432,.074,.004,.342,.418,.004)
    front_face(m,"Darker inset interior doorway glazed panel", "Mid glass blue",-.027,.027,.435,.367,.403)


def chassis(m):
    J.shaped(m,"Continuous shaped service chassis contour", "Cast underframe graphite",
       [(-.139,-.419),(.139,-.419),(.169,-.345),(.186,-.252),(.185,.247),
        (.162,.365),(.119,.416),(-.119,.416),(-.162,.365),(-.185,.247),
        (-.186,-.252),(-.169,-.345)],.112,.176,"Dry tire iron")
    for s in (-1,1):
        z=s*.094
        B(m,"Visible pressed underfloor diesel engine pack each side", "Cast underframe graphite",
          s*.115,z,.125,.133,.077,.155,.011)
        B(m,"Distinct rectangular deep gearbox rib lines", "Air reservoir blue-grey",
          s*.146,z,.058,.109,.079,.129,.005)
        for k in range(6):
            B(m,"Pressed engine cooling ribs below the saloon", "Dry tire iron",
              s*.178,z-.042+k*.016,.010,.006,.091,.124,.001)
        D(m,"Separate round underfloor pressure reservoir", "Air reservoir blue-grey",
          (s*.097,s*-.073,.104),.028,"z",-.045,.043,15)
        Pipe(m,"Horizontal dark exhaust inboard of the low aluminum sill", "Brake link iron",
          (s*.177,-.147,.113),(s*.183,.148,.106),.0049,8)
        for j,z0 in enumerate((-.278,-.175,-.065,.042,.154,.267)):
            B(m,"Period roof passenger compartment vents", "Roof end band",
              s*.081,z0,.027,.028,.531,.547,.006)
        B(m,"Cast central bearing and dark curve-fit draw pocket",
          "Cast underframe graphite",0,s*.438,.052,.049,.131,.182,.005)
        B(m,"Short inboard coupler drawbar section", "Brake link iron",0,s*.474,
          .023,.032,.143,.171,.005)
        B(m,"Coupler knuckles","Buffer mark grey",0,s*.494,.0105,.010,.146,.168,.002)
        for x in (-.071,.071):
            D(m,"Inboard pressure buffer pads", "Buffer mark grey",(x,s*.430,.162),
                .018,"z",-.004,.004,15)


def bogies(m,z):
    J.shaped(m,"Two independent two-axle bogie side casting profiles","Cast underframe graphite",
      [(-.188,z-.067),(.188,z-.067),(.214,z-.051),(.214,z+.055),(.187,z+.068),
       (-.187,z+.068),(-.214,z+.055),(-.214,z-.051)],.063,.117,"Dry tire iron")
    for s in (-1,1):
        B(m,"Dark painted bogie girder covering upper wheel webs", "Cast underframe graphite",
          s*.220,z,.036,.146,.084,.118,.007)
        for k in (-.034,.035):
            B(m,"Mechanical bogie journal mount", "Cast underframe graphite",
              s*.211,z+k,.037,.031,.044,.083,.004)
        for v in (-.045,.046):
            for j in range(4):
                D(m,"Visible layered cast springs over bogie transoms", "Brake link iron",
                  (s*.202,z+v,0),.0092,"h",.084+j*.006,.088+j*.006,10)


def wheel(m,z):
    D(m,"Full width native steel axle", "Dry tire iron",(0,z,RAD),.012,"x",-.219,.219,14)
    for s,side in ((-1,"L"),(1,"R")):
        x=s*.212
        a,b=sorted((-s*.030,s*.049))
        L(m,"Rolling tread DMU "+side,[(a,.73*RAD),(a,RAD),(-.005,RAD),(.005,RAD),
          (b,RAD),(b,.73*RAD),(a,.73*RAD)],"x",(x,z,RAD),("Slate black rail equipment",
          "Dry tire iron","Dry tire iron","Dry tire iron","Steel wheel flange"),24,False,False)
        a,b=sorted((-s*.042,-s*.035))
        L(m,"True inner DMU railhead flange",[(a,.72*RAD),(a,RAD+.009),(b,RAD+.009),
          (b,.72*RAD),(a,.72*RAD)],"x",(x,z,RAD),("Steel wheel flange",),24,False,False)
        D(m,"Visible cast resilient steel wheel dished face","Dry tire iron",
          (x+s*.034,z,RAD),.033,"x",-.006,.006,20)
        D(m,"Bogie axle grease cap","Wheel center grease",
          (x+s*.044,z,RAD),.014,"x",-.005,.005,14)
        for i in range(5):
            a=tau*i/5
            D(m,"Visible axle greased locking studs","Fresh nickel pin",
              (x+s*.042,z+.023*cos(a),RAD+.023*sin(a)),.0024,"x",-.002,.003,7)


def parts(m):
    cast(m);nose(m);panes(m);gangway(m);chassis(m)
    for z in (-.227,.230):bogies(m,z)


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(NAME+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
      c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    m=R.materials()
    for label,mat in zip(P,m):
        mat.name=label
        n=mat.node_tree.nodes["Principled BSDF"]
        n.inputs["Metallic"].default_value=.45 if any(t in label.lower() for t in ("iron","steel","grease","nickel")) else .06
        n.inputs["Roughness"].default_value=.36 if "glass" in label.lower() else .68
    return m


def main():
    setup()
    m=mesh();parts(m)
    for z in AXLES:wheel(m,z)
    p=R.MODELS/(NAME+".obj")
    R.export_obj(p,W.local_obj(m))
    t=p.read_text()
    p.write_text("# Original stock Manley–Morel powered cab half #11, tools/build_manley_morel_art.py\n"+t.split("\n",1)[1])
    atlas()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.view_settings.view_transform="Standard"
    sc.name="LuanTTD · Manley–Morel DMU powered cab half"
    sc["Mounted unit"]="One physical stock-length cab/power car and neighboring identical opposite-facing car. Class 101 inspiration."
    sc["Runtime"]="Y=0 railhead, unit, -Z points toward glazed cab outward. Pair +Z ends face inward."
    sc["Provenance"]="Original geometry; CC BY 2.0 trackside rail photo (art/rail_manley_morel.md), no pixels or BR emblems reused."
    mats=colors()
    q=mesh();parts(q)
    J.geometry(sc,"Original pressed coachwork, powered underfloor, two bogies and inward gangway",q,mats)
    for i,z in enumerate(AXLES,1):
        w=mesh();wheel(w,z)
        c=J.geometry(sc,f"Axle {i}: gauge fitted editable assembly",w,mats)
        pivot=bpy.data.objects.new(f"Powered railcar axle {i} pivot",None)
        pivot.location=(0,z,RAD);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.049
        c.objects.link(pivot)
        for o in tuple(c.objects):
            if o!=pivot:
                o.parent=pivot;o.location=(0,-z,-RAD)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.268)
                v.region_3d.view_rotation=Vector((.90,-.84,.53)).to_track_quat("Z","Y")
                v.region_3d.view_distance=1.91
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_manley_morel.blend"),compress=True)
    if path:=os.getenv("MANLEY_MOREL_REVIEW"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),"Original Manley–Morel car angles"),path)


if __name__=="__main__":
    main()
