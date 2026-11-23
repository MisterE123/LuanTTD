#!/usr/bin/env python3
"""Original Blender #26 AsiaStar express powerhead; deploy-ready fixed/sprung geometry."""
import os
from pathlib import Path
import sys
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_tim_art as T

F,SH,C,R,W,J,G=T.F,T.SH,T.C,T.R,T.W,T.J,T.G
B,D,Pipe=T.B,T.D,T.Pipe
NAME="rail_asiastar"
# Preserve the ordered shared pantograph atlas and its exact hues.
PALETTE={**SH.PAL,
    "Electric enamel blue":"ebebe0","Blue sunward edge":"c8dfdd","Blue shadow coachwork":"50636d",
    "Blue charcoal glazing":"21434f","Sky reflection":"91b7bb","Grey blue lower band":"234353",
    "Ochron yellow warning apron":"e4b860","Yellow shoulder highlight":"f0c977",
    "Lower warning shade":"88965e","Cab lower vent blue":"3e7777","Side window grey gradient":"497d83"}
P={n:i for i,n in enumerate(PALETTE)}
# This is not a recolor of the T.I.M.: long drag visor reaching over a
# narrow lower pilot, sculpted pointed nose, and a light high shell.
SECTIONS=(
    (-.465,.050,.278,.167,.264),(-.447,.098,.289,.166,.275),
    (-.422,.136,.309,.166,.289),(-.398,.164,.314,.170,.302),
    (-.368,.190,.337,.176,.324),(-.336,.201,.366,.186,.348),
    (-.302,.213,.408,.194,.386),(-.264,.220,.468,.199,.437),
    (-.226,.224,.516,.202,.458),(-.187,.224,.546,.204,.471),
    (-.142,.224,.560,.204,.482),(-.091,.225,.563,.204,.483),
    (.277,.225,.563,.204,.483),(.378,.218,.558,.202,.478),
    (.423,.196,.540,.199,.459),
)
AXLES=(-.251,-.183,.185,.259)

def setup():
    R.COLORS[:]=PALETTE.values()
    SH.P=J.P=W.P=G.P=F.P=P

def shell(m):
    for (a,*A),(b,*B) in zip(SECTIONS,SECTIONS[1:]):
        p,q=F.body_contour(*A),F.body_contour(*B)
        for i in range(len(p)):
            j=(i+1)%len(p)
            if i in (0,1,18): col="Roof deep trough"
            elif i in (2,17): col="Grey blue lower band"
            elif a<-.300 and i in (4,5,6,7,8,9,10,11,12,13,14,15): col="Ochron yellow warning apron"
            elif a>=-.091 and i in (8,9,10,11): col="Roof paint slate"
            elif i in (5,6,7,12,13,14): col="Blue sunward edge"
            else: col="Electric enamel blue"
            points=((p[i][0],a,p[i][1]),(q[i][0],b,q[i][1]),
                    (q[j][0],b,q[j][1]),(p[j][0],a,p[j][1]))
            F.face(m,"Continuous express shell with long tapered nose",col,points)
    for i in (0,-1):
        z,*f=SECTIONS[i];q=[(x,z,h) for x,h in F.body_contour(*f)]
        F.face(m,"Pilot nose and rear inter-car sheet","Blue shadow coachwork",q if i==0 else q[::-1])

def screen(m):
    rows=SECTIONS[6:11]
    def panel(sign,name,col,l,r,pieces,dr):
        for front,back in zip(pieces,pieces[1:]):
            p=[]
            for section,w in ((front,l),(front,r),(back,r),(back,l)):
                x=sign*section[1]*w
                p.append((x,section[0],T.deck_at(section,x)+dr))
            F.face(m,name,col,p if sign>0 else p[::-1])
    for sign in (-1,1):
        panel(sign,"Teal continuous swept wind visor surround","Cab lower vent blue",.020,.81,rows,.0032)
        panel(sign,"Broad flush front cab glazing","Blue charcoal glazing",.044,.735,rows,.0056)
        panel(sign,"Pale grey-blue grazing light on glass","Sky reflection",.060,.705,rows[2:],.0067)
        def on_glass(z,x):
            for front,back in zip(rows,rows[1:]):
                if front[0]<=z<=back[0]:
                    u=(z-front[0])/(back[0]-front[0])
                    return (x,z,(1-u)*T.deck_at(front,x)+u*T.deck_at(back,x)+.0109)
            raise ValueError(z)
        Pipe(m,"Swept one-piece spring-back windshield wiper","Dark glazing rubber",
             on_glass(-.272,sign*.059),on_glass(-.212,sign*.103),.0027,8)
        B(m,"Rectangular outboard brushed marker housing","Grey blue lower band",sign*.054,-.467,.043,.013,.230,.258,.0035)
        D(m,"Cut white glass in shaped pilot","Headlamp ivory glass",(sign*.064,-.475,.245),.0078,"z",-.003,.003,16)
        D(m,"Inset deep red tail light","Ruby lens red",(sign*.045,-.475,.240),.0049,"z",-.003,.002,12)
    B(m,"Inter-car drawing gear protection lower deck","Grey blue lower band",0,-.417,.171,.091,.145,.190,.013)

def side(m):
    for sign in (-1,1):
        def p(n,c,z0,z1,h0,h1,lift):
            F.skin_panels(m,n,c,SECTIONS,sign,z0,z1,h0,h1,lift)
        p("Continuous teal belt below cab glass","Cab lower vent blue",-.323,.376,.292,.316,.003)
        p("Second pale border above teal belt","Blue sunward edge",-.297,.389,.316,.328,.0038)
        p("Long integral steel maintenance door","Blue shadow coachwork",-.120,-.031,.275,.453,.0053)
        p("Continuous curved cab side glazing","Dark glazing rubber",-.187,-.124,.379,.461,.0034)
        p("Pale visor return quarter-light","Side window grey gradient",-.180,-.133,.389,.454,.0053)
        p("Ribbed roof compressor cooling pocket","Dark cooler trough",.052,.321,.365,.453,.0034)
        for k in range(14):
            z=.063+k*.018
            p("Separate pressed copper-nickel exchanger vanes","Vent sunlit nickel",z,z+.0065,.371,.445,.0058)
        for z in (-.207,.096,.260):
            B(m,"Recessed underframe skirt hinge","Side cooler steel",sign*.183,z,.022,.034,.137,.181,.004)
        B(m,"Recessed roof ceramic housing access panel","Roof deep trough",sign*.044,-.100,.074,.119,.550,.568,.009)
    B(m,"Tinted rear corridor bellows and suspension gasket","Roof deep trough",0,.437,.191,.032,.227,.432,.008)
    B(m,"Curved rear corridor moving door","Blue charcoal glazing",0,.455,.151,.011,.240,.419,.006)
    B(m,"Rear equipment raised safety step","Grey blue lower band",0,.458,.152,.033,.176,.205,.006)

def gear(m):
    J.shaped(m,"Long low coupled traction cabinet","Frame iron",
       [(-.142,-.447),(.142,-.447),(.187,-.265),(.187,.294),(.154,.437),(-.154,.437),(-.187,.294),(-.187,-.265)],
       .100,.180,"Dark wheel tread")
    for z in (-.217,.222):SH.bogie(m,z)
    for s in (-1,1):
        B(m,"Short standard coupler casting","Frame iron",0,s*.464,.062,.059,.135,.185,.006)
        B(m,"Coupler knuckles","Bright coupling nipple nickel",0,s*.494,.0105,.010,.146,.168,.002)

def build():
    setup()
    parts=(("01 • Long sculpted express shell",shell),("02 • Widescreen vision and lighting",screen),
           ("03 • Intake workings, teal lining and corridor",side),("04 • Lower traction and independent axles",gear))
    m=SH.mesh()
    for _,fn in parts:fn(m)
    for z in AXLES:SH.wheel(m,z)
    hinged=SH.mesh();SH.collectors(hinged)
    C._shaft(m,hinged,C.MOUNTS)
    T.export(m,"bl_"+NAME+"_body",Path(__file__).name)
    C._shaft(m,hinged,C.MOVING)
    T.export(m,"bl_"+NAME,Path(__file__).name)
    F.atlas(NAME,R.COLORS)
    setup()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD stock AsiaStar electric power head #26"
    scene["Upstream"]="OpenTTD 16.0-RC1 source data; original geometry and paint."
    scene["Collector"]="8/16 stock body; 0.424 native gauge; raised contact shoe Y=.784."
    F.M.PAL=PALETTE;F.M.P=P
    mats=F.M.colors()
    for name,fn in parts:
        m=SH.mesh();fn(m);J.geometry(scene,name,m,mats)
    for i,z in enumerate(AXLES,1):
        m=SH.mesh();SH.wheel(m,z)
        col=J.geometry(scene,f"0{i+4} • Native axle {i}",m,mats)
        pivot=bpy.data.objects.new(f"Axle {i} wheelset pivot",None)
        pivot.location=(0,z,SH.RAD);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.045
        col.objects.link(pivot)
        for ob in tuple(col.objects):
            if ob!=pivot:ob.parent=pivot;ob.location=(0,-z,-SH.RAD)
    J.geometry(scene,"09 • Globally reusable variable-height collector",hinged,mats)
    F.render(scene,NAME,os.getenv("ASIASTAR_REVIEW"),center=.34,side_scale=1.47)

if __name__=="__main__":
    build()
