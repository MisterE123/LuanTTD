#!/usr/bin/env python3
"""Original 3D continental express power head for pinned OpenTTD stock #25."""
import os
from pathlib import Path
import sys
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as F
import build_sh_30_art as SH
import build_rail_sh_collector_art as C

B,D,Pipe=SH.B,SH.D,SH.Pipe
R,W,J,G=SH.R,SH.W,SH.J,SH.G
NAME="rail_tim"
# Same ordered atlas indices as the shared independently sprung collector.
PAL={**SH.PAL,
     "Electric enamel blue":"ce642f","Blue sunward edge":"e88d4a","Blue shadow coachwork":"a75a34",
     "Grey blue lower band":"52626a","Cab lower vent blue":"964a32",
     "Upper cab roof pale":"d4d8d3","Ochron yellow warning apron":"f0aa69",
     "Yellow shoulder highlight":"e5bd98","Lower warning shade":"8e4938",
     "Sky reflection":"9cafb8"}
P={k:i for i,k in enumerate(PAL)}
SECTIONS=(
    (-.461,.100,.286,.188,.267),(-.444,.136,.315,.188,.291),(-.416,.171,.356,.188,.319),
    (-.392,.194,.391,.188,.346),(-.355,.208,.438,.189,.382),(-.312,.217,.493,.190,.427),
    (-.268,.220,.533,.191,.455),(-.219,.223,.551,.192,.472),
    (-.155,.223,.554,.192,.474),(.276,.223,.554,.192,.474),
    (.388,.216,.547,.192,.466),(.428,.193,.522,.193,.445),
)
AXLES=(-.259,-.189,.181,.255)

def setup():
    R.COLORS[:]=PAL.values()
    SH.P=J.P=W.P=G.P=F.P=P

def shell(m):
    for (a,*A),(b,*B) in zip(SECTIONS,SECTIONS[1:]):
        p,q=F.body_contour(*A),F.body_contour(*B)
        for i in range(len(p)):
            j=(i+1)%len(p)
            c=("Roof paint slate" if a>=-.219 and 8<=i<=11 else
                "Roof deep trough" if i in (0,1,18) else
                "Blue sunward edge" if i in (4,5,6,13,14,15) else
                "Blue shadow coachwork" if i in (2,17) else "Electric enamel blue")
            F.face(m,"Streamlined orange nested steel fairing",c,[(p[i][0],a,p[i][1]),(q[i][0],b,q[i][1]),
                (q[j][0],b,q[j][1]),(p[j][0],a,p[j][1])])
    for i in (0,-1):
        z,*f=SECTIONS[i]
        band=[(x,z,h) for x,h in F.body_contour(*f)]
        F.face(m,"Independent front pilot and rear bulkhead","Blue shadow coachwork",band if i==0 else band[::-1])

def deck_at(section,x):
    z,*profile=section
    cross=sorted(F.body_contour(*profile)[6:15])
    for (l,h),(r,k) in zip(cross,cross[1:]):
        if l<=x<=r:return h+(k-h)*(x-l)/(r-l)
    raise ValueError(x)

def cab_screen(m):
    samples=SECTIONS[4:8]
    def pane(side,n,c,a,b,rows,up):
        for r,s in zip(rows,rows[1:]):
            v=[]
            for sample,w in ((r,a),(r,b),(s,b),(s,a)):
                x=side*sample[1]*w
                v.append((x,sample[0],deck_at(sample,x)+up))
            F.face(m,n,c,v if side>0 else v[::-1])
    for s in (-1,1):
        pane(s,"Inset wide swept panoramic windscreen surround","Dark glazing rubber",.019,.647,samples,.0024)
        pane(s,"Wide divided driving windscreen","Blue charcoal glazing",.054,.582,samples,.0047)
        pane(s,"Natural horizon reflection on sloped windshield","Sky reflection",.072,.564,samples[2:],.0064)
        for x in (s*.076,s*.105):
            P1=(x,-.340,deck_at(SECTIONS[4],x)+.014)
            P2=(x+s*.009,-.301,deck_at(SECTIONS[5],x+s*.009)+.017)
            Pipe(m,"Outside glass wiper", "Dark glazing rubber",P1,P2,.0029,8)
        B(m,"Inlaid front lamp shadow assembly","Dark glazing rubber",s*.067,-.462,.060,.010,.225,.261,.003)
        D(m,"Independent electric halogen beam","Headlamp ivory glass",(s*.078,-.469,.247),.009,"z",-.003,.001,16)
        D(m,"Independent red tail lens","Ruby lens red",(s*.054,-.469,.235),.006,"z",-.003,.001,14)
    B(m,"Brushed lower pilot central reinforcement","Grey blue lower band",0,-.438,.231,.052,.153,.188,.009)

def equipment(m):
    for s in (-1,1):
        def p(name,c,a,b,h,k,up):
            F.skin_panels(m,name,c,SECTIONS,s,a,b,h,k,up)
        p("Whisper grey shoulder accent","Upper cab roof pale",-.310,.397,.287,.310,.0025)
        p("Small sloped driver's quarter frame","Dark glazing rubber",-.263,-.177,.379,.441,.003)
        p("Side glass on driver quarter","Side window grey gradient",-.257,-.182,.386,.433,.0045)
        p("Pressed independent access door","Cab lower vent blue",-.149,-.076,.220,.445,.0058)
        p("Electrical room door glazing surround","Roof deep trough",-.139,-.086,.364,.437,.0069)
        p("Electrical room recessed optical glass","Sky reflection",-.136,-.089,.376,.430,.0078)
        p("Traction cooling equipment full grille recess","Dark cooler trough",-.041,.267,.339,.454,.0030)
        for j in range(19):
            z=-.029+j*.0154
            p("Directional rapidly tapering traction cooling slats","Side cooler steel",z,z+.006,.345,.445,.0061)
        p("Sill positioned side air intake surround","Blue shadow coachwork",.283,.374,.233,.301,.0038)
        for j in range(6):
            p("Six separate underframe safety ribs","Vent sunlit nickel",.288+j*.013,.293+j*.013,.242,.288,.0052)
        B(m,"Textured current resistor roof deck","Roof deep trough",s*.051,-.103,.089,.113,.548,.563,.009)
        for j in range(6):
            B(m,"Raised narrow resistor vanes","Side cooler steel",s*.054,-.144+j*.015,.079,.006,.560,.566,.002)
    B(m,"Rebated streamlined stock gangway","Dark glazing rubber",0,.431,.205,.027,.214,.442,.007)
    B(m,"Pressed inter-car corridor surround","Grey blue lower band",0,.449,.149,.009,.231,.424,.004)
    B(m,"Rear gangway tinted glazed panel","Blue charcoal glazing",0,.456,.072,.005,.341,.401,.002)
    B(m,"Rear end threshold","Roof deep trough",0,.453,.148,.020,.198,.217,.003)

def export(m,target,generator='build_stock_tim_art.py'):
    p=R.MODELS/(target+".obj")
    R.export_obj(p,W.local_obj(m))
    p.write_text(f"# Original conventional electric express art from tools/{generator}\n"+
                 p.read_text().split("\n",1)[1])

def underframe(m):
    J.shaped(m,"Reinforced stock high speed chassis","Frame iron",
      [(-.16,-.430),(.16,-.430),(.185,-.280),(.185,.278),(.16,.430),(-.16,.430),(-.185,.278),(-.185,-.280)],
      .102,.179,"Dark wheel tread")
    for z in (-.224,.218):SH.bogie(m,z)
    for side in (-1,1):
        B(m,"Power head stock coupler drawing gear","Traction gear steel",0,side*.466,.032,.050,.139,.176,.004)
        B(m,"Coupler knuckles","Bright coupling nipple nickel",0,side*.494,.0105,.010,.146,.168,.002)
        B(m,"Side laterally mounted mechanical damper","Side cooler steel",side*.143,.031,.029,.227,.121,.156,.005)

def build():
    setup()
    fixed=(("01 • Express shell",shell),("02 • Operational cab optics",cab_screen),
           ("03 • Traction grilles, passenger-through gangway, resistor banks",equipment),
           ("04 • Braced locomotion",underframe))
    body=SH.mesh()
    for _,part in fixed:part(body)
    for z in AXLES:SH.wheel(body,z)
    c=SH.mesh();SH.collectors(c)
    C._shaft(body,c,C.MOUNTS)
    export(body,"bl_"+NAME+"_body")
    C._shaft(body,c,C.MOVING)
    export(body,"bl_"+NAME)
    F.atlas(NAME,R.COLORS)
    setup()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD stock electric T.I.M. #25"
    sc["Upstream"]="OpenTTD 16.0-RC1 MM/RVI #25. Original art; no source sprites."
    sc["Gauge"]="0.424 native gauge; stock lengths; shared wire shoe normal Y=.784."
    F.M.PAL=PAL;F.M.P=P
    mats=F.M.colors()
    for layer,part in fixed:
        piece=SH.mesh();part(piece);J.geometry(sc,layer,piece,mats)
    for i,z in enumerate(AXLES,1):
        piece=SH.mesh();SH.wheel(piece,z)
        children=J.geometry(sc,f"0{i+4} • Independently pivoting axle {i}",piece,mats)
        pivot=bpy.data.objects.new(f"Axle {i} pivot",None)
        pivot.location=(0,z,SH.RAD);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.045
        children.objects.link(pivot)
        for ob in tuple(children.objects):
            if ob!=pivot:ob.parent=pivot;ob.location=(0,-z,-SH.RAD)
    J.geometry(sc,"09 • Complete roof collector and isolated stand-offs",c,mats)
    F.render(sc,NAME,os.getenv("TIM_REVIEW"),center=.34,side_scale=1.47)

if __name__=="__main__":
    build()
