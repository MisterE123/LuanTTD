#!/usr/bin/env python3
"""Original RC1 Airtaxi A33 and large Guru X2 rotorcraft."""
from pathlib import Path
from math import cos, pi, sin, tau
from types import SimpleNamespace
import os,sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_tricario_art as h
from build_stock_guru_airtaxi_art import Variant
import build_stock_darwin_family_art as d
from mathutils import Vector

A33=Variant(
    433,236,"Late wide-body derivative, swept clean wing and broader underwing fan shrouds",
    ("eeeae0","e5e1d4","466e8a","283f57","7494a1","b8974c"),
    (1.005,1.025,.181,.277,.151,.137),
    (.934,.317,-.442,-.198,-.411,.191,.120,.113),
    (.354,-.646,-.997,.350,.042),(-.376,-.790,.646),
    (.329,.229,-.256,.153,.111,.055),
    (.238,-.148,.057,.074,2,.719,.040),24,True,"airtaxi_a33","Airtaxi_A33")

PIVOT=(0,.022,.515)
TAIL=(-.049,-.774,.325)
PAL=h.PAL | {
    "Crown ivory":"e9e8db","Panel ivory":"d2d7c9","Lit blue":"a4573a",
    "Blue taper":"b46c47","Dark coastal cobalt":"3d5255","Copper pinstripe":"c49f51",
    "Cab glass":"25515b","Window glint":"81a7a6",
}
PROFILE=(
    (-.347,.091,.231,.066,.064),(-.285,.128,.232,.091,.081),
    (-.207,.158,.232,.117,.105),(-.066,.179,.232,.135,.118),
    (.133,.180,.235,.139,.117),(.248,.168,.232,.129,.114),
    (.344,.143,.228,.112,.106),(.409,.106,.217,.094,.089),
    (.465,.073,.201,.068,.069),(.503,.037,.187,.040,.044),(.515,.008,.178,.010,.013),
)

def pressure_shell():
    B,C,M=h.B,h.C,h.Mesh
    h.PROFILE=PROFILE
    angles=[tau*i/56 for i in range(56)]
    colors=["Crown ivory" if sin(a+.055)>.70 else "Panel ivory" if sin(a+.055)>.30 else
            "Lit blue" if sin(a+.055)>-.24 else "Copper pinstripe" if sin(a+.055)>-.34 else
            "Silver pressure hull" if sin(a+.055)>-.66 else "Dark coastal cobalt" for a in angles]
    h.Art.sections("Guru X2 long-radius passenger pressure shell",
        [(y,[(w*cos(a),c+(u if sin(a)>=0 else l)*sin(a)) for a in angles])
         for y,w,c,u,l in PROFILE],"Panel ivory",colors)
    for s in (-1,1):
        for i,y in enumerate((-.246,-.171,-.095,-.020,.061,.144,.224)):
            h.side("Tall squared cabin window bezel","Glazing bezel",y,.37,.028,.226,s,.0020)
            h.side("Recessed full-height oblong glazing","Cab glass",y,.37,.024,.181,s,.0033)
            h.side("Tinted upper window daylight","Window glint",y-.004,.43,.019,.027,s,.0045)
        for y,w in ((-.276,.033),(.261,.042)):
            h.side("Sliding doors closed beneath their track","Pressure door seal",y,-.27,w,.407,s,.0042)
            h.side("Lower door separately skinned","Panel ivory",y,-.28,w*.89,.389,s,.0051)
            h.side("Recessed door handle","Landing gear chrome",y+.011,-.22,.009,.014,s,.0060)
        h.side("Tapered swept cockpit quarter light","Cab glass",.335,.44,.045,.26,s,.0038)
        p=[]
        for i in range(9):
            y=.349+i*(.148/8)
            w,c,u,l=h.E.interp(PROFILE,y)
            for j in range(11):
                a=.38+j*.103
                p.append((s*(w+.0034)*cos(a),y,c+(u+.0034)*sin(a)))
        M("Conforming angular pilot windshield",p,
           [(i*11+j,(i+1)*11+j,(i+1)*11+j+1,i*11+j+1)[::s] for i in range(8) for j in range(10)],
          "Cab glass")
        C("Main high stance wheel strut",(s*.169,-.104,.171),(s*.185,-.091,.041),.015,.013,"Landing gear chrome",12)
        C("Main exact ground contact", (s*.185-.015,-.091,.041),(s*.185+.015,-.091,.041),
          .041,.041,"Dull tire",28)
        B("Excavated side wheel-bay lip",(s*.141,-.087,.151),(.108,.278,.104),"Panel ivory",.029)
        B("Gripped boarding step under forward door",(s*.179,.184,.112),
          (.053,.165,.012),"Landing gear chrome",.005)
        for p in (.126,.242):
            C("Rigid step brace connects to pressure shell",(s*.123,p,.155),(s*.168,p,.116),
              .007,.005,"Well shadow",9)
    C("Forward twin nose strut",(0,.335,.154),(0,.346,.031),.013,.010,"Landing gear chrome",14)
    for s in (-1,1):
        C("Nose contact wheel",(s*.019-.008,.346,.031),(s*.019+.008,.346,.031),
          .031,.031,"Dull tire",28)

def tail_and_power():
    B,C=h.B,h.C
    angles=[tau*i/28 for i in range(28)]
    h.Art.sections("Long tapered elevated tail with thick control trunk",
        [(y,[(w*cos(a),c+r*sin(a)) for a in angles]) for y,w,c,r in
         ((-.806,.025,.304,.027),(-.735,.034,.283,.038),(-.602,.044,.266,.047),
          (-.465,.056,.246,.055),(-.298,.079,.245,.067))],
          "Panel ivory",["Lit blue" if sin(a)<-.24 else "Panel ivory" for a in angles])
    for s in (-1,1):
        h.Art.foil("Separate stabilizer with solid lifting skin",
           ((.009,-.657,-.806,.280,.049),(.114,-.702,-.811,.294,.031),
            (.205,-.763,-.815,.302,.011)),s)
        y=s*.096
        B("Turboshaft fairing above shell with rear louvres",(y,-.076,.379),
            (.118,.319,.129),"Blue taper",.042)
        C("Ducted aft hot exhaust stem",(y,-.246,.387),(y,-.289,.393),.041,.036,"Exhaust patina bronze",18)
        for i in range(6):
            B("Raised cooling rib", (y,-.075+i*.019,.441),(.063,.007,.011),"Well shadow",.002)
    p=[(-.018,-.758,.307),(-.015,-.809,.328),(-.013,-.795,.530),(-.013,-.757,.520),
       (-.017,-.701,.453),(-.023,-.662,.309)]
    h.Art.close_mesh("Genuine swept tail fin with continuous root",p+[(-x,y,z) for x,y,z in p],
        [(0,1,2,3,4,5),(11,10,9,8,7,6)]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)],
        ["Lit blue","Lit blue","Panel ivory","Copper pinstripe","Panel ivory","Crown ivory","Blue taper","Dark coastal cobalt"])
    C("Main rotor mast",(0,PIVOT[1],.401),PIVOT,.033,.017,"Landing gear chrome",14)
    C("Tail drive hub",(-.012,TAIL[1],TAIL[2]),TAIL,.025,.019,"Landing gear chrome",14)

def rotor(tail):
    C=h.C
    n,span=(4,.148) if tail else (5,.644)
    for i in range(n):
        a=tau*i/n
        def p(x,y,z):
            A=x*cos(a)-y*sin(a);B=x*sin(a)+y*cos(a)
            return (z,A,B) if tail else (A,B,z)
        f=(.020,.047,span*.66,span*.92,span)
        points=[]
        for j,y in enumerate(f):
            w=(.027 if tail else .041)*(.48 if j in (0,4) else 1)
            t=(.003 if tail else .006)*(1-j*.12)
            back=-.026*(y/span)**2
            points.extend(p(back+x,y,z) for x,z in ((-w,-t),(w,-t),(w,t),(-w,t)))
        polys=[(3,2,1,0)]+[(j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i) for j in range(4) for i in range(4)]+[(16,17,18,19)]
        inks=["Well shadow"]+["Skinned wing alloy"]*8+["Silver pressure hull"]*4+["Copper pinstripe"]*5
        h.Art.close_mesh(f"Cambered physical rotor blade {i+1}",points,polys,inks)
        C("Visible blade pitch link",p(-.009,.012,.008),p(-.012,.054,.009),.0056,.0036,"Landing gear chrome",8)
    stem=lambda z:(z,0,0) if tail else (0,0,z)
    C("Separate animated rotor core",stem(-.018),stem(.025),.032 if tail else .050,.023 if tail else .033,
      "Landing gear chrome",18)

def build_heli():
    b=h.bpy
    d.base.PALETTE=PAL;d.base.KEYS=list(PAL);d.base.begin()
    b.context.preferences.filepaths.save_version=0
    h.E.export_atlas("guru_x2",PAL)
    sc=b.context.scene;sc.name="LuanTTD | Guru X2 #254"
    sc["Provenance"]="Original LuanTTD mesh and livery; pinned OpenTTD 16.0-RC1 MA #254 and AVI #39 data"
    sc["Main mount"]=list(PIVOT);sc["Tail mount"]=list(TAIL)
    def gather(label,fn):
        old=set(sc.objects);fn()
        return h.Art.new_collection(sc,label,[o for o in sc.objects if o not in old])
    cabin=gather("01 | Long cabin and wheels",pressure_shell)
    stable=gather("02 | Twin turboshafts and boom",tail_and_power)
    d.write_native(SimpleNamespace(series=254,stem="guru_x2",export_name="Guru_X2"),sc,list(cabin.objects)+list(stable.objects),"ground",PAL)
    for tail,pivot,name in ((False,PIVOT,"rotor"),(True,TAIL,"tail")):
        objs=gather("03 | Animated "+name,lambda:rotor(tail))
        d.write_native(SimpleNamespace(series=254,stem="guru_x2_"+name,export_name=name),sc,list(objs.objects),"ground",PAL)
        for o in objs.objects:o.location+=Vector(pivot)
    b.ops.object.camera_add(location=(1.99,2.42,1.55));cam=b.context.object
    cam.rotation_euler=(Vector((0,-.105,.280))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=1.87;sc.camera=cam
    sc.render.engine="BLENDER_WORKBENCH";sc.render.resolution_x=1180;sc.render.resolution_y=810
    sc.render.resolution_percentage=100
    sh=sc.display.shading;sh.light="STUDIO";sh.color_type="MATERIAL";sh.show_cavity=True;sh.cavity_type="BOTH"
    sc.view_settings.view_transform="Standard"
    b.ops.wm.save_as_mainfile(filepath=str(d.ROOT/"art/stock_guru_x2.blend"),compress=True)
    if path:=os.environ.get("GURU_X2_RENDER"):
        sc.render.image_settings.file_format="JPEG";sc.render.filepath=path;b.ops.render.render(write_still=True)

if __name__=="__main__":
    d.make(A33,title="Airtaxi A33",sprite_family=4,engine_title="Open high-bypass fan housings")
    build_heli()
