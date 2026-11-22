#!/usr/bin/env python3
"""Original Class 8-inspired SH '8P' #10 art. Runtime -Z nose and Y=0 tread."""
from math import cos, pi, sin, tau
import os
from pathlib import Path
from random import Random
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
NAME="bl_rail_sh_8p"
PAL={
 "Green-shadow enamel":"2c4b43","Leaf-green boiler":"426950","Moss-green glancing steel":"5e8364",
 "Deep green panel enamel":"365d4d","Tender green":"426850","Tender painted edging":"577963",
 "White-pale lining":"c3bda0","Carriage red lining":"a96a4e","Smokebox blue-black":"2e3738",
 "Smokebox edge graphite":"4c5754","Smokebox shoulder steel":"5e6660","Dry dark cast steel":"38423d",
 "Heat worn graphite":"535955","Handrail nickel":"a3a899","Bright steel pin":"bac2b3",
 "Crown shadow":"405548","Weathered pressure valve":"a38c5e","Burnished red beam":"a84a3d",
 "Buffer contact nickel":"a2a79b","Cab sash black":"32403b","Glazing slate":"375357",
 "Horizon glint":"739b99","Cab brass gauge":"c0a270","Cab copper tap":"ac7956",
 "Warm lamp window":"f6dfa4","Rear shell ruby":"b95449","Cab wood burnish":"7d6952",
 "Crank web green-black":"3c5246","Dry tread steel":"596763","Tread centre steel":"99a89c",
 "Inner guide flange":"46564c","Spoke glancing green":"607866","Tender coal shade":"292e2b",
 "Tender coal diffuse":"424945","Coal worn edge":"565e57","Sign dark gold":"8f7756",
 "Sign bone letters":"e6d8b4","Review ballast":"827d71",
}
P={k:i for i,k in enumerate(PAL)}
GROUPS=(
 ("leading",(-.321,-.263),.028,.053,.027),
 ("drivers",(-.184,-.057,.070),.060,.036,.029),
 ("trailing",(.155,),.025,.050,.024),
 ("tender",(.236,.289,.344),.025,.054,.028),
)


def palette():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=P


def mesh():
    return R.Mesh(R.terrain_height(0))


def F(m,n,c,p):
    m.face(n,P[c],p)


def tube(m,name,rings,materials,caps=None,n=32):
    circles=[[(r*cos(i*tau/n),z,h+r*sin(i*tau/n)) for i in range(n)] for z,r,h in rings]
    for a,b,c in zip(circles,circles[1:],materials):
        for j in range(n):
            k=(j+1)%n
            light=c[0] if (a[j][2]+a[k][2])/2>a[0][2]+.036 else c[1]
            F(m,name,light,(a[j],b[j],b[k],a[k]))
    if caps:
        F(m,name,caps[0],circles[0])
        F(m,name,caps[1],circles[-1][::-1])


def boiler(m):
    ht=.355
    tube(m,"Long standard 8P tapered circular boiler",
         [(-.323,.144,ht),(-.283,.148,ht),(-.184,.153,ht),(-.104,.155,ht),
          (.009,.159,ht),(.084,.159,ht),(.119,.149,ht)],
         [("Moss-green glancing steel","Leaf-green boiler")]*6,
         ("Leaf-green boiler","Deep green panel enamel"))
    tube(m,"Grooved smokebox cylinder and dished hot door",
         [(-.429,.070,ht),(-.419,.112,ht),(-.405,.132,ht),(-.389,.143,ht),(-.316,.146,ht)],
         [("Smokebox edge graphite","Smokebox blue-black")]*3+
         [("Smokebox shoulder steel","Smokebox blue-black")],
         ("Smokebox blue-black","Smokebox blue-black"))
    for z,ra in ((-.292,.149),(-.178,.154),(-.064,.158),(.062,.160)):
        rings=[(z-.003,ra,ht),(z,ra+.0017,ht),(z+.004,ra,ht)]
        tube(m,"Separate lined shrink bands on circular steam boiler",rings,
             [("White-pale lining","Carriage red lining"),("Carriage red lining","Carriage red lining")])
    # Long double chimney housing: two genuine open bores into the
    # smokebox, with one raised oval collar around the pair.
    B(m,"Oval bed under double 8P exhaust chimney","Smokebox edge graphite",
      0,-.360,.078,.095,.485,.513,.014)
    for z in (-.380,-.343):
        L(m,"Two genuine perforated exhaust chimney mouths",
          [(.507,.026),(.525,.022),(.545,.022),(.553,.026),(.558,.027),
           (.558,.019),(.550,.018),(.520,.016)],"h",(0,z,0),
          ("Heat worn graphite","Smokebox blue-black","Smokebox edge graphite",
           "Smokebox blue-black","Smokebox edge graphite","Smokebox blue-black"),24,False,False)
    L(m,"Rounded separate boiler sand dome with low flared pedestal",
      [(.492,.035),(.510,.035),(.527,.027),(.542,.019),(.547,.003)],"h",(0,-.111,0),
      ("Deep green panel enamel","Leaf-green boiler","Moss-green glancing steel"),24)
    for z in (.037,.055):
        L(m,"Twin exposed brass safety-valve seats",
          [(.508,.013),(.523,.013),(.538,.009),(.547,.010)],"h",(0,z,0),
          ("Dry dark cast steel","Weathered pressure valve","Bright steel pin"),14)
    for s in (-1,1):
        # The open boiler and free-standing upright smoke wings are the
        # major silhouette distinction from the earlier Jubilee and A4.
        outer=[(-.414,.241),(-.274,.241),(-.256,.429),(-.266,.490),
               (-.285,.512),(-.379,.515),(-.413,.479)]
        for i in (0,1):
            q=[(s*(.122+i*.010+.035*(z+.414)/.16),z,h) for z,h in outer]
            F(m,"Broad freestanding curved 8P smoke deflector sheet",
              "Smokebox edge graphite" if i else "Smokebox blue-black",q if (s>0)==bool(i) else q[::-1])
        for a,b in zip(outer,outer[1:]+outer[:1]):
            f=lambda q:(s*(.133+.035*(q[0]+.414)/.16),q[0],q[1])
            Pipe(m,"Turned nickel bead around 8P smoke wing", "Smokebox shoulder steel",f(a),f(b),.0033,8)
        for z,h in ((-.393,.281),(-.294,.277),(-.360,.467)):
            x=.133+.035*(z+.414)/.16
            Pipe(m,"Short bracket leaving a real deflector-slot gap","Dry dark cast steel",
                 (s*(x-.023),z,h),(s*x,z,h),.0072,8)
        points=[(s*.123,-.412,.438),(s*.153,-.287,.435),(s*.158,-.189,.433),
                (s*.165,-.086,.430),(s*.169,.072,.425)]
        for a,b in zip(points,points[1:]):
            Pipe(m,"Continuous bright boiler maintenance handrail","Handrail nickel",a,b,.0027,8)
        for x,z,h in points[1:-1]:
            Pipe(m,"Raised handrail standoff","Heat worn graphite",(x-s*.018,z,h-.012),(x,z,h),.003,8)
        Gbeam(m,"Long steam delivery pipes below boiler belly","Smokebox edge graphite",
             (s*.127,-.266,.271),(s*.127,.081,.252),.021,.025)
        L(m,"Lead steam cylinder forged oval end cap",
          [(-.293,.048),(-.280,.053),(-.211,.053),(-.205,.037)],"z",(s*.172,0,.135),
          ("Dry dark cast steel","Heat worn graphite","Smokebox edge graphite"),23)
        D(m,"Compact visible Caprotti chamber cover",
          "Dry dark cast steel",(s*.197,-.230,.133),.029,"x",-.009,.014,15)
        D(m,"Caprotti eccentric dark fastener","Weathered pressure valve",
          (s*.209,-.231,.134),.009,"x",-.002,.006,12)
    for x,z0,z1 in ((-.046,-.429,-.433),(.046,-.429,-.433)):
        B(m,"Raised real smokebox door hinge tabs","Smokebox shoulder steel",x,
          (z0+z1)/2,.019,.012,.370,.421,.002)
    D(m,"Central 8P smokebox locking boss","Bright steel pin",(0,-.432,.356),
      .011,"z",-.005,.005,12)
    Pipe(m,"Smokebox two-lever latch handles","Handrail nickel",
      (-.016,-.435,.348),(.018,-.435,.364),.0034,8)
    B(m,"High front black fleet number plate","Smokebox blue-black",0,-.432,.081,.009,.391,.414,.003)
    glyph(m,"8P",0,-.438,.396,.004)


def glyph(m,word,x,z,h,d,side=None):
    table={"8":("111","101","111","101","111"),"P":("110","101","110","100","100"),
           "S":("111","100","111","001","111"),"H":("101","101","111","101","101"),
           " ":("000","000","000","000","000")}
    for c,ch in enumerate(word):
        for j,row in enumerate(table[ch]):
            for k,a in enumerate(row):
                if a!='1':continue
                w=(c*4+k-2*len(word)+.5)*d
                y=h+(4-j)*d
                if side is None:
                    B(m,"Original stamped 8P fleet name characters","Sign bone letters",x+w,z,
                        d*.9,.0025,y,y+d*.93,.00015)
                else:
                    B(m,"Original stamped 8P fleet name characters","Sign bone letters",x,
                        z+side*w,.0025,d*.9,y,y+d*.93,.00015)


def framing(m):
    J.shaped(m,"Pressed standard 8P chassis and sloped running board","Dry dark cast steel",[
      (-.103,-.420),(.103,-.420),(.168,-.348),(.198,-.228),(.193,.091),
      (.164,.181),(-.164,.181),(-.193,.091),(-.198,-.228),(-.168,-.348)],
      .124,.197,"Heat worn graphite")
    for s in (-1,1):
        Gbeam(m,"Low separate raised lined running plate","Deep green panel enamel",
            (s*.195,-.232,.198),(s*.166,.173,.194),.032,.028)
        for z,h in ((.128,.162),(.145,.129),(.153,.101)):
            B(m,"Separate cut treads below the open driver cab","Heat worn graphite",
              s*.178,z,.047,.035,h,h+.008,.003)
        Pipe(m,"Stout steam-heated pipe and grease service line to tender",
             "Weathered pressure valve",(s*.069,.158,.157),(s*.062,.229,.147),.0055,8)
    for s,z in ((-1,-.408),(1,.414)):
        B(m,"Heavy bright red end beam with stock proportions","Burnished red beam",
          0,z,.194,.033,.126,.204,.007)
        for side in (-1,1):
            D(m,"Low mounted inboard buffer shanks","Heat worn graphite",
              (side*.079,z+s*.013,.161),.019,"z",-.011,.011,18)
            D(m,"Low compact round steam-era buffer face","Buffer contact nickel",
              (side*.079,z+s*.024,.161),.022,"z",-.003,.003,18)
        B(m,"Central cast draw pocket","Dry dark cast steel",0,s*.447,.061,.044,.132,.183,.006)
        B(m,"Center drawarm connecting beam to coupler","Heat worn graphite",0,s*.479,
          .025,.024,.144,.171,.004)
        B(m,"Coupler knuckles","Buffer contact nickel",0,s*.494,.0105,.010,.146,.168,.002)
    D(m,"Raised warm running lamp on front plate","Warm lamp window",(0,-.419,.228),
      .016,"z",-.006,.003,17)
    D(m,"Small aft ruby tail lamp","Rear shell ruby",(-.052,.426,.329),
      .012,"z",-.002,.004,15)


def cabin(m):
    z0,z1=.083,.177
    roof=[(-.174,.486),(-.147,.522),(-.092,.549),(0,.555),(.092,.549),(.147,.522),(.174,.486)]
    for (x,h),(y,H) in zip(roof,roof[1:]):
        F(m,"Revolved green-black 8P cab crown over open sides","Smokebox edge graphite",
          ((x,z0-.009,h),(y,z0-.009,H),(y,z1+.009,H),(x,z1+.009,h)))
        F(m,"Cab canopy true inner rolled roof","Cab sash black",
          ((x,z1+.009,h-.007),(y,z1+.009,H-.007),(y,z0-.009,H-.007),(x,z0-.009,h-.007)))
    B(m,"Wide driver floor into separate tender passage","Cab wood burnish",
      0,.132,.301,.106,.194,.213,.006)
    for s in (-1,1):
        p=[(s*.165,z0,.201),(s*.166,z1,.201),(s*.177,z1,.358),(s*.175,z0,.358)]
        for side,c in ((p,"Deep green panel enamel"),(p[::-1],"Green-shadow enamel")):
            F(m,"Deep green individually formed lower cab side walls",c,side)
        for z in (z0+.006,z1-.006):
            Gbeam(m,"Rolled pillars framing actual open cab sides","Tender painted edging",
                  (s*.173,z,.345),(s*.163,z,.497),.015,.014)
        Pipe(m,"Narrow brass cabin window sill and pulled grab",
             "Handrail nickel",(s*.174,z0+.009,.367),(s*.172,z1-.009,.372),.0032,8)
        B(m,"Original 8P builder plate","Sign dark gold",s*.168,.131,.008,.074,.286,.314,.003)
        glyph(m,"SH 8P",s*.173,.131,.294,.0033,s)
        for h in (.281,.321):
            Pipe(m,"Paired green-white cab panel trim stripes",
                 "White-pale lining" if h>.30 else "Carriage red lining",
                 (s*.169,z0+.006,h),(s*.171,z1-.008,h),.0013,6)
        D(m,"Three dimensional brass pressure dial","Cab brass gauge",
          (s*.070,z0+.012,.401),.013,"z",-.003,.005,14)
        Gbeam(m,"Raised one-sided ash trap and brake controller","Cab copper tap",
              (s*.079,.138,.215),(s*.092,.124,.343),.014,.016)


def tender(m):
    J.shaped(m,"Integrated but visibly separate 8P tender frame","Deep green panel enamel",
              [(-.117,.221),(.117,.221),(.158,.248),(.150,.367),
               (.101,.420),(-.101,.420),(-.150,.367),(-.158,.248)],.112,.214,"Tender painted edging")
    B(m,"Separate visible tender drawbar between the units","Heat worn graphite",
      0,.202,.069,.059,.118,.151,.006)
    B(m,"Cab-to-tender corrugated transit plate","Cab wood burnish",0,.203,.147,.061,.187,.202,.005)
    for s in (-1,1):
        a=[(s*.153,.223,.210),(s*.147,.365,.214),(s*.109,.416,.223),
           (s*.104,.415,.402),(s*.143,.385,.434),(s*.163,.242,.430)]
        out=a if s>0 else a[::-1]
        F(m,"Separate long green banded 8P tender shoulder", "Tender green",out)
        F(m,"Inner thickness of rolled tender water casing", "Green-shadow enamel",
          [(x-s*.010,z,h) for x,z,h in out[::-1]])
        for (x,z,h),(y,Z,H) in zip(a[3:],a[4:]):
            Pipe(m,"Turned metal tender rolled open coal coping","Tender painted edging",(x,z,h),(y,Z,H),.006,9)
        for h,c in ((.252,"White-pale lining"),(.264,"Carriage red lining"),(.386,"Carriage red lining"),(.395,"White-pale lining")):
            Pipe(m,"Brush-lined period tender pane with cream red trim",c,
               (s*.157,.239,h),(s*.151,.375,h),.0015,7)
        B(m,"Small original fleet badge on lined tender",
          "Sign dark gold",s*.155,.304,.005,.067,.304,.334,.003)
        glyph(m,"8P",s*.160,.303,.312,.0038,s)
        Pipe(m,"Low rear ladder sideward grip","Handrail nickel",
             (s*.070,.418,.251),(s*.070,.418,.367),.0035,7)
    B(m,"Close rear sheet with tender inset water stand","Deep green panel enamel",
      0,.404,.214,.027,.213,.400,.008)
    B(m,"Solid tender fore bulkhead","Deep green panel enamel",0,.226,
      .245,.016,.214,.420,.006)
    B(m,"Low green tender water tank at the rear","Tender painted edging",
      0,.385,.200,.059,.347,.398,.007)
    D(m,"Aft screw-down sealed water lid","Smokebox edge graphite",
      (.036,.380,.399),.016,"h",-.004,.005,16)
    J.shaped(m,"Low irregular coal in the true molded tender housing",
      "Tender coal diffuse",[(-.120,.235),(.118,.234),(.132,.305),(.089,.362),
            (-.099,.356),(-.130,.302)],.307,.407,"Tender coal shade")
    rng=Random(810)
    for i in range(37):
        x=rng.uniform(-.110,.103);z=rng.uniform(.240,.353)
        h=.414+.032*(1-abs(x)/.112)-.17*abs(z-.268)
        d=rng.uniform(.006,.014)
        pts=[(x+d*cos(t*tau/5),z+d*sin(t*tau/5),h-d*.23) for t in range(5)]
        for j in range(5):
            F(m,"Individual original fractured tender coal lumps",
              ("Tender coal shade","Tender coal diffuse","Coal worn edge")[(i+j)%3],
              (pts[j],pts[(j+1)%5],(x+d*.13,z+d*.18,h+d*.42)))


def wheels(m,kind,axes,rad,outer,inner):
    for z in axes:
        D(m,"Cross-gauge steel axle shaft","Dry dark cast steel",(0,z,rad),rad*.25,"x",-.220,.220,12)
        for s,side in ((-1,"L"),(1,"R")):
            x=s*.212
            a,b=sorted((s*outer,-s*inner))
            L(m,"Rolling tread "+kind+" "+side,[(a,.72*rad),(a,rad),(-.004,rad),(.004,rad),
                (b,rad),(b,.72*rad),(a,.72*rad)],"x",(x,z,rad),
              ("Dry dark cast steel","Dry tread steel","Dry tread steel","Dry tread steel",
               "Inner guide flange","Dry dark cast steel"),24,False,False)
            a,b=sorted((-s*.042,-s*.035))
            L(m,"Authentic .009 native wheel-guide flanges",[(a,.74*rad),(a,rad+.009),
              (b,rad+.009),(b,.74*rad),(a,.74*rad)],"x",(x,z,rad),("Inner guide flange",),24,False,False)
            if kind=="drivers":
                for k in range(15):
                    v=tau*k/15
                    start=(x+s*.020,z+.015*cos(v),rad+.015*sin(v))
                    end=(x+s*.022,z+.048*cos(v),rad+.048*sin(v))
                    Gbeam(m,"Fifteen individually cast spokes on each large driving wheel",
                          "Spoke glancing green" if k%3==0 else "Crank web green-black",start,end,.005,.008)
                for k in range(8):
                    t=-.56+.11*k
                    p=[(x+s*.025,z+r*cos(a),rad+r*sin(a)) for r,a in (
                       (.031,t),(.047,t),(.047,t+.13),(.031,t+.13))]
                    F(m,"Pressed crescent weights fixed to the driving wheel spokes",
                      "Crank web green-black",p if s>0 else p[::-1])
            else:
                D(m,"Pressed smaller bogie and tender wheel discs","Dry dark cast steel",
                  (x+s*(outer-.009),z,rad),rad*.78,"x",-.005,.005,16)
            D(m,"Dished wheel grease cap and axle end nut","Crank web green-black",
              (x+s*(outer-.009),z,rad),rad*.28,"x",-.007,.007,16)


def permanent():
    m=mesh()
    framing(m);boiler(m);cabin(m);tender(m)
    for s in (-1,1):
        q=(.013 if s>0 else -.013)
        z=(-.184,-.057,.070)
        x=s*.246
        for a,b in zip(z,z[1:]):
            Gbeam(m,"Production 8P polished coupling rods, not Walschaerts valve rig",
                 "Bright steel pin",(x,a,.061+q),(x,b,.061+q),.010,.007)
        Gbeam(m,"8P crosshead main connecting rod","Handrail nickel",
             (s*.235,-.216,.129),(x,z[1],.061+q),.014,.009)
        for a in z:
            D(m,"Closed crank pin turned steel coupling eyes","Bright steel pin",
              (x+s*.004,a,.061+q),.008,"x",-.004,.004,12)
        B(m,"Distinct tender bogie cheek plate over springs and axles",
          "Dry dark cast steel",s*.187,.290,.055,.157,.077,.123,.008)
        for a in (.236,.289,.344):
            B(m,"Individual tender cast axle hornblock","Dry dark cast steel",s*.200,a,
              .046,.042,.062,.117,.005)
            B(m,"Layered shiny tender suspension leaf","Heat worn graphite",s*.207,a,
              .021,.048,.102,.111,.003)
    return m


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):
        return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(NAME+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
      c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    mats=R.materials()
    for label,mat in zip(P,mats):
        mat.name=label
        n=mat.node_tree.nodes["Principled BSDF"]
        n.inputs["Metallic"].default_value=.40 if any(t in label.lower() for t in ("nickel","steel","brass")) else .05
        n.inputs["Roughness"].default_value=.45 if ("enamel" in label) else .68
    return mats


def main():
    palette()
    m=permanent()
    for kind,axes,rad,o,i in GROUPS:
        wheels(m,kind,axes,rad,o,i)
    obj=R.MODELS/(NAME+".obj")
    R.export_obj(obj,W.local_obj(m))
    content=obj.read_text()
    obj.write_text("# Original SH '8P' #10 · tools/build_sh_8p_art.py\n"+content.split("\n",1)[1])
    atlas()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · SH '8P' stock Pacific"
    sc.view_settings.view_transform="Standard"
    sc["Stock"]="14.1 engine #10: one standard modular unit with integral rendered tender"
    sc["Reference"]="Original articulated geometry, Duke of Gloucester form reference only (art/rail_sh_8p.md)"
    sc["Mount"]="Local -Z nose, rail tread Y0, .424 track gauge, unit scale"
    mats=colors()
    J.geometry(sc,"Original body, framed cab, exposed rods and separate-looking coal tender",permanent(),mats)
    for kind,axes,rad,o,i in GROUPS:
        for j,z in enumerate(axes,1):
            q=mesh()
            wheels(q,kind,(z,),rad,o,i)
            title=f"{kind} wheelset {j}"
            box=J.geometry(sc,title,q,mats)
            ax=bpy.data.objects.new(title+" axle pivot",None)
            ax.empty_display_type="CIRCLE"
            ax.empty_display_size=rad+.010
            ax.location=(0,z,rad)
            box.objects.link(ax)
            for ob in tuple(box.objects):
                if ob!=ax:
                    ob.parent=ax
                    ob.location=(0,-z,-rad)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.269)
                v.region_3d.view_rotation=Vector((.84,-1,.43)).to_track_quat("Z","Y")
                v.region_3d.view_distance=1.84
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_sh_8p.blend"),compress=True)
    if dest:=os.getenv("SH_8P_REVIEW"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),"SH '8P' original"),dest)


if __name__=="__main__":
    main()
