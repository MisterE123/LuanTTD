#!/usr/bin/env python3
"""Original 1970s stock Uhl coal, Foster oil and Reynard mail road bodies.

blender -b -t 2 --python-exit-code 1 --python tools/build_stock_road_fleet_d_art.py
ROAD_D_QA=/absolute/directory renders each original model at three angles.
ROAD_D_ONLY=coal,oil,mail selects build families.
"""
from copy import deepcopy
from math import cos, pi, sin, sqrt, tau
import os
from pathlib import Path
from random import Random
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_road_primitives as road

w,r,bpy,V=road.w,road.r,road.bpy,road.Vector
B,C,rod=road.B,road.C,road.rod
G={
    "Axle grey":"566063","Frame":"394443","Rubber":"292f31","Tyre scuff":"4b5150",
    "Hub":"657074","Nurled iron":"465055","Rim":"aab3ac","Roof dark":"454e4e",
    "Glass rim":"2c3a40","Glass":"325461","Glass glint":"7297a4","Rear glass":"3c5a62",
    "Nickel":"a4b6b4","Cold roller wear":"859b9c","Deep rubber":"344144","Pale lamp":"ebdbac",
    "Amber":"cf9652","Red crystal":"b64640","Mirror":"adbdc1","Floor underbody":"576463",
    "Black plate":"30424a","Cream plate":"dbc896","Reflector":"bac4b1","Road dust":"596465",
}
PIGMENTS={
 "coal":{
  "Cab main":"a67848","Cab shade":"825d3e","Cab shoulder":"bc8e56","Cab peak":"ccb98c",
  "Cab recess":"715d49","Cab trim":"bdac85","Hood highlight":"c79053","Front grille":"474d46",
  "Overpaint band":"ddc696","Load skin":"686c63","Load bevel":"81847a","Load shadow":"545f61",
  "Load pan":"65665a","Load silvery rim":"9b9e90","Load steel fold":"7b8075",
  "Coal seam dark":"37403f","Coal fissure":"202c2e","Coal slate":"454b4b",
  "Coal cleaved cool":"515a5a","Coal muted grit":"575b54","Coal soil":"433a36",
  "Dry rust":"906048","Metal curl":"82859a","Steel high":"acb8b7",
 },
 "oil":{
  "Cab main":"93554c","Cab shade":"703f39","Cab shoulder":"a76c64","Cab peak":"dbcfb3",
  "Cab recess":"653f3a","Cab trim":"bcb49d","Hood highlight":"88544c","Front grille":"4f514b",
  "Overpaint band":"e3d6b8","Tank warm side":"d1ba95","Tank cream":"e2cda5",
  "Tank pale":"eedcba","Tank bottom":"a69070","Tank sunset stripe":"b7784b",
  "Steel straps":"929487","Saddle iron":"666356","Tank hatch bronze":"aa9c7d","Ladder steel":"a6a191",
  "Booth hose":"363e39","Hose retention steel":"6c7467","Tank tray":"60544c","Valve warn red":"a94740",
  "Warning pale":"d8ab5d","Valve nickel":"acb3a6","Tank shade":"857c68",
 },
 "mail":{
  "Cab main":"436d8c","Cab shade":"314e63","Cab shoulder":"5284a0","Cab peak":"78a0b1",
  "Cab recess":"2f4b5b","Cab trim":"9fb3b9","Hood highlight":"6091a8","Front grille":"384857",
  "Overpaint band":"decda3","Van midnight":"2d455d","Van shallow blue":"567b91",
  "Van panel enamel":"4c748e","Van lid canvas":"444e53","Van crown":"555d61",
  "Van cover seam":"67716f","Van trim bright":"9fb4b5","Van steel floor":"627777",
  "Van hinge tone":"859d9d","Van envelope line":"e6dbb9","Van parcel shadow":"334c5c",
  "Van leather apron":"455252","Van cream trim":"c6be9f","Stamp detail":"8d7b54",
 },
}
AXLES={
 "coal":(-.510,.440,.223,.134),
 "oil":(-.525,.459,.218,.143),
 "mail":(-.495,.469,.225,.123),
}

def init_color(kind):
    colors=G|PIGMENTS[kind]
    while len(colors)<64:colors[f"Neutral {len(colors)}"]="7e8883"
    assert len(colors)==64
    w.P=road.P={k:i for i,k in enumerate(colors)}
    r.COLORS[:]=colors.values()
    return colors


def face(m,name,tone,p):
    road.f(m,name,tone,p)


def chassis(m,kind):
    front,rear,wt,rad=AXLES[kind]
    road.wheels(m,front,rear,wt,rad,"Cab trim",True)
    for s in (-1,1):
        B(m,"Two pressed C-section longitudinal frame rails","Frame",s*.147,.003,.048,1.455,.137,.211,.009)
        B(m,"Continual lower wear flange pressed into reinforcements","Axle grey",s*.152,.023,.053,1.401,.150,.164,.003)
        for z in (front,rear):
            road.fender(m,"Pressed steel round wheel guard",s*.240,z,rad,rad+.031,.091,"Cab shade")
            for row in range(3):
                B(m,"Three-stage spring leaf packs","Floor underbody",s*.135,z,.041,
                  .199-row*.015,.144+row*.009,.151+row*.009,.004)
            B(m,"Rearward flexible rubber wheel flap","Rubber",s*.226,z+.132,.131,.026,.045,.205,.004)
        B(m,"Practical cab access step aft of front tire","Floor underbody",s*.242,-.290,.103,.128,.143,.176,.009)
        for z in (-.332,-.311,-.288,-.267):
            B(m,"Separate anti-slip indents on driver step","Deep rubber",s*.249,z,.069,.007,.174,.181,.002)
        for z in (-.43,-.195,.340,.679):
            C(m,"Chassis gusset pressed bolts","Nickel",(s*.171,z,.167),.007,"x",-.004,.006,7)
    for z in (-.659,-.209,.139,.413,.697):
        B(m,"Solid transverse ladder cross brace","Frame",0,z,.344,.045,.152,.208,.006)
    B(m,"Visible rounded metal fuel tank below bed","Nurled iron",.165,.206,.124,.271,.109,.203,.016)
    for z in (.122,.267):
        B(m,"Body-colored bolted fuel tank straps","Axle grey",.163,z,.135,.021,.120,.213,.003)
    C(m,"Heavy exposed underfloor driveshaft","Axle grey",(0,.032,.118),.019,"z",-.366,.417,11)
    C(m,"Central tail axle differential","Nurled iron",(0,rear,.125),.055,"x",-.073,.079,14)


def cab_shape(m,rows):
    def section(z,w,h,low):
        return z,[(-w*.82,low),(w*.82,low),(w,low+.040),(w,h-.085),
                  (w*.933,h-.033),(w*.74,h),(-w*.74,h),(-w*.933,h-.033),
                  (-w,h-.085),(-w,low+.040)]
    road.section_hull(m,"Original shaped pressed steel cab shell",
        [section(*row) for row in rows],
        ["Cab shade","Cab shade","Cab main","Cab shoulder","Cab peak","Cab peak",
         "Cab peak","Cab shoulder","Cab main","Cab shade"],"Cab main")


def face_panes(m,z,y0,y1,span):
    # Rigid flat glass at the pressure rail of square cab forms; the
    # adjacent frame/hood rings taper without forcing the panes inside it.
    for s in (-1,1):
        B(m,"Independent front window rubber pressure gasket","Glass rim",s*span/2,z,
          span,.024,y0,y1,.009)
        B(m,"Wide divided triplex safety windshield","Glass",s*span/2,z-.014,
          span-.020,.017,y0+.010,y1-.009,.007)
        B(m,"Recessed rearward sky in windshield strip","Glass glint",s*span/2,z-.024,
          span-.038,.006,y1-.049,y1-.031,.003)
        rod(m,"Windshield wiper in separate mechanical assembly","Glass rim",
          (s*span*.25,z-.027,y0+.026),(s*span*.67,z-.027,y0+.063),.0030)


def side_cab(m,z,w,h0,h1):
    for s in (-1,1):
        B(m,"Pressed heavy door recessed black outer seam","Cab recess",s*w,z,
          .021,.277,.270,h1+.026,.013)
        B(m,"Original clean embossed driver door","Cab main",s*(w+.011),z,
          .015,.256,.288,h1+.018,.009)
        road.panes(m,"Independent cabin quarter-drop glazing",s*(w+.020),z,.218,h0,h1,"Glass rim")
        B(m,"Separate nickel narrow sliding pane divider","Nickel",s*(w+.035),z-.041,
          .004,.010,h0+.014,h1-.012,.0017)
        B(m,"Flushed latch within steel door relief","Cold roller wear",s*(w+.025),z+.082,
          .009,.042,.341,.358,.003)
        B(m,"Faded fleet waist pinstripe fascia","Overpaint band",s*(w+.017),z,
          .014,.250,.311,.329,.002)
        rod(m,"Tucked wing mirror linked to early cab side","Front grille",
          (s*(w-.003),z-.116,.467),(s*.284,z-.150,.503),.0052)
        B(m,"Original sloped period door mirrors","Cab shade",s*.288,z-.163,.038,.026,.475,.536,.008)
        B(m,"Rearward rectangle polished mirror glass insert","Mirror",s*.288,z-.147,
          .027,.009,.483,.528,.003)
    B(m,"Independent cab-top air and emergency hatch","Cab shoulder",0,z-.015,.177,.128,h1+.069,h1+.090,.011)


def front_bumper(m,z,w,shape):
    B(m,"True front bumper and rolled steel wings","Cab shade",0,z,w,.064,.147,.220,.014)
    B(m,"Tough pressed lower pale bumper insert","Front grille",0,z-.035,w-.019,.020,.164,.185,.006)
    B(m,"Independent blank stamped front plate recess","Black plate",0,z-.047,.125,.014,.170,.208,.005)
    for i in range(6):
        B(m,"Geometry-only unbranded plate marks","Reflector",(i-2.5)*.015,z-.057,
          .005,.006,.177,.191+(i%2)*.003,.001)
    for s in (-1,1):
        x=s*.173
        if shape=="round":
            C(m,"Spun round headlamp housing","Nickel",(x,z-.014,.273),.044,"z",-.010,.008,16)
            C(m,"Actual warm front round lens","Pale lamp",(x,z-.028,.274),.031,"z",-.006,.003,16)
        else:
            B(m,"Dark inset forward rectangular lamp case","Front grille",x,z-.009,
              .123,.033,.245,.334,.009)
            B(m,"True front-facing color lens","Pale lamp",x,z-.028,.092,.012,.261,.320,.005)
        B(m,"Original ochre corner turn signal","Amber",s*.224,z-.007,.044,.022,.219,.245,.004)


def tail_lighting(m,z):
    B(m,"Rear steel tubular underride bar lower face","Frame",0,z,.460,.039,.129,.168,.011)
    for s in (-1,1):
        B(m,"Sealed aft lamp mount steel casing","Black plate",s*.170,z-.001,.102,.034,.163,.226,.008)
        for j,col in enumerate(("Red crystal","Amber","Reflector")):
            B(m,"Directional rear individual three-colour lamps",col,s*(.146+j*.023),z+.020,
              .019,.009,.178,.214,.003)
    B(m,"Rear blank brass plate backing","Cream plate",0,z+.015,.127,.014,.150,.181,.004)
    for j in range(6):
        B(m,"Unique thin tool-pressed vehicle plate marks","Black plate",(j-2.5)*.015,z+.024,.005,.005,
          .155,.171+(j%2)*.003,.001)


def rim_section(x,a,b,c,h):
    return [(-x+c,a,h),(x-c,a,h),(x,a+c,h),(x,b-c,h),
            (x-c,b,h),(-x+c,b,h),(-x,b-c,h)] + [(-x,a+c,h)]


def coal(m):
    cab_shape(m,[(-.754,.225,.565,.208),(-.739,.248,.615,.205),
                 (-.690,.261,.634,.204),(-.574,.263,.644,.203),(-.310,.263,.644,.203),
                 (-.230,.248,.631,.212),(-.196,.220,.597,.222)])
    face_panes(m,-.751,.414,.561,.208)
    side_cab(m,-.470,.259,.408,.548)
    front_bumper(m,-.753,.514,"square")
    B(m,"Rectangular coal cab long nickel warm dividing panel","Overpaint band",0,-.752,.472,.022,.373,.410,.008)
    B(m,"Independent coal broad slat grille","Front grille",0,-.763,.229,.029,.252,.362,.009)
    for i in range(7):
        B(m,"Original coal truck horizontal running grille rib","Cab trim",0,-.781,.204,.008,
          .261+i*.013,.267+i*.013,.002)
    base=rim_section(.188,-.164,.696,.023,.258)
    low=rim_section(.221,-.182,.717,.028,.299)
    upper=rim_section(.253,-.194,.740,.032,.475)
    lip=rim_section(.258,-.194,.742,.033,.500)
    inner=rim_section(.228,-.170,.714,.029,.501)
    pan=rim_section(.189,-.156,.690,.029,.311)
    name="Closed structural open coal tipper bed with thicker rolled rim"
    face(m,name,"Load shadow",base[::-1])
    for paint,a,b in zip(("Load shadow","Load skin","Load bevel","Load silvery rim","Load steel fold"),
                        (base,low,upper,lip,inner),(low,upper,lip,inner,pan)):
        for i,u in enumerate(a):
            j=(i+1)%8
            face(m,name,paint,(u,a[j],b[j],b[i]))
    face(m,name,"Load pan",pan)
    for s in (-1,1):
        for z in (-.124,.023,.170,.317,.464,.610):
            rod(m,"Rolled diagonal coal tipper strengthening box ribs","Load bevel",
              (s*.218,z,.292),(s*.253,z,.467),.011)
            B(m,"Independent side head stamped oval bolt","Cold roller wear",s*.261,z,.011,.037,.451,.472,.003)
        B(m,"Rust-dark transit latch over rear pin","Dry rust",s*.256,.714,.031,.053,.352,.435,.008)
        B(m,"Greased main body tipping pivot mount","Load shadow",s*.181,.642,
          .061,.083,.186,.288,.013)
        C(m,"Independent rear articulated tipper hinge hub","Metal curl",(s*.207,.646,.238),
          .026,"x",-.012,.014,12)
        rod(m,"Twin side tilted ram bracing under open coal body","Load shadow",
            (s*.134,-.018,.191),(s*.201,.290,.264),.014)
    # A collapsed two-stage center ram connects fixed chassis to the tilt bed.
    rod(m,"Coal tipper hood hydraulic cylinder housing","Load shadow",(-.006,-.220,.198),(.001,.054,.249),.029)
    rod(m,"Independent chromed telescoping piston link","Steel high",(.001,.022,.240),(.006,.184,.286),.014)
    B(m,"Rear swinging thick amber-gray tailgate panel","Load skin",0,.743,.454,.030,.296,.487,.009)
    for x in (-.149,0,.149):
        C(m,"Upper tailgate hinge shafts","Metal curl",(x,.744,.482),.014,"x",-.031,.031,11)
    B(m,"Rear lower pressed latching beam","Load bevel",0,.763,.424,.016,.320,.357,.004)
    rod(m,"Real diagonal external latching lever above tail bar","Metal curl",
        (.086,.776,.328),(.165,.771,.378),.009)
    tail_lighting(m,.747)


def coal_payload(m):
    rng=Random(1241975)
    # A solid low granular heap fills the tipper, with individually
    # closed irregular angular pieces and distinct broken faces on top.
    z0,z1=-.146,.696
    nx,nz=10,22
    def height(x,z):
        a=(z-z0)/(z1-z0)
        return .429 + .055*max(0,1-(x/.205)**2)*max(0,sin(a*pi))**.67 + .009*sin(tau*a*2+.15)
    q=[[(x,z,height(x,z)+rng.uniform(-.006,.006)) for x in [i*.039-.195 for i in range(nx+1)]]
       for z in [z0+(z1-z0)*j/nz for j in range(nz+1)]]
    shade=("Coal seam dark","Coal fissure","Coal slate","Coal cleaved cool","Coal soil")
    name="Coal cargo bed core"
    for j in range(nz):
        for i in range(nx):
            a,b=q[j][i:i+2]
            d,c=q[j+1][i:i+2]
            face(m,name,rng.choice(shade),(a,b,c,d))
    edge=q[0][:-1]+[row[-1] for row in q[:-1]]+q[-1][:0:-1]+[row[0] for row in q[:0:-1]]
    floor=[(x*.926,z,.314) for x,z,_ in edge]
    for i,(a,b) in enumerate(zip(edge,floor)):
        j=(i+1)%len(edge)
        face(m,name,"Coal seam dark",(a,b,floor[j],edge[j]))
        face(m,name,"Coal fissure",(floor[j],b,(0,.274,.314)))
    index=0
    for zi in range(14):
        for xi in range(7):
            x=(xi-3)*.048+rng.uniform(-.007,.008)
            z=z0+.030+zi*.060+rng.uniform(-.010,.008)
            y=height(x,z)+rng.uniform(-.008,.008)
            width=rng.uniform(.016,.030);length=rng.uniform(.019,.034);tall=rng.uniform(.013,.031)
            a=rng.random()*tau
            n=6
            index+=1
            rock=f"Separate watertight crushed coal rock {index:03d}"
            shape=[(cos(a+i*tau/n)*width*rng.uniform(.82,1.12),
                    sin(a+i*tau/n)*length*rng.uniform(.80,1.15)) for i in range(n)]
            bottom=[(x+dx*.75,z+dz*.75,y-.010) for dx,dz in shape]
            ring=[(x+dx,z+dz,y+rng.uniform(-.003,.009)) for dx,dz in shape]
            top=[(x+dx*.45+.002,z+dz*.51,y+tall*rng.uniform(.62,1.07)) for dx,dz in shape]
            face(m,rock,"Coal fissure",bottom[::-1])
            face(m,rock,rng.choice(shade[2:4]),top)
            for prev,next_ in ((bottom,ring),(ring,top)):
                for i,p in enumerate(prev):
                    j=(i+1)%n
                    face(m,rock,rng.choice(shade),(p,prev[j],next_[j],next_[i]))


def ring_shell(m,name,rows,mat,cap):
    n=24
    q=[[(x*cos(tau*i/n),z,y+h*sin(tau*i/n)) for i in range(n)] for z,y,x,h in rows]
    face(m,name,cap,q[0])
    face(m,name,cap,q[-1][::-1])
    for a,b in zip(q,q[1:]):
        for i in range(n):
            j=(i+1)%n
            face(m,name,mat[i],(a[i],b[i],b[j],a[j]))


def tanker(m):
    cab_shape(m,[(-.737,.207,.565,.219),(-.721,.229,.592,.214),(-.678,.248,.626,.206),
                 (-.590,.252,.639,.205),(-.302,.251,.640,.208),(-.238,.233,.616,.220),
                 (-.208,.211,.585,.229)])
    face_panes(m,-.735,.414,.555,.195)
    side_cab(m,-.473,.250,.407,.542)
    front_bumper(m,-.736,.501,"round")
    B(m,"Vintage separate wide cream grille surround","Overpaint band",0,-.742,
      .396,.024,.278,.374,.011)
    B(m,"Period oval charcoal lower radiator aperture","Front grille",0,-.754,
      .309,.018,.286,.368,.008)
    for j in range(4):
        B(m,"Original pressed horizontal grille ridges above bumper","Cab trim",0,-.767,
          .289,.007,.293+j*.017,.300+j*.017,.002)
    yc=.450
    rx,ry=.224,.164
    name="Continuous sealed contoured Foster oil barrel with both pressure heads"
    tone=[]
    for i in range(24):
        sn=sin(tau*(i+.5)/24)
        tone.append("Tank sunset stripe" if -.29<sn<.12 else
                    "Tank pale" if sn>.73 else "Tank cream" if sn>.19 else
                    "Tank bottom" if sn<-.67 else "Tank warm side")
    rows=[(z,yc,rx*t,ry*t) for z,t in ((-.194,.42),(-.181,.72),(-.153,.88),(-.120,.97),
             (-.083,1.),(.587,1.),(.629,.97),(.669,.88),(.701,.70),(.721,.45))]
    ring_shell(m,name,rows,tone,"Tank cream")
    for zz in (.011,.476):
        contour=[(-.174,.211),(.174,.211),(.207,.318),(.173,.345),(.100,.333),
                 (.000,.288),(-.100,.333),(-.173,.345),(-.207,.318)]
        road.section_hull(m,"Load bearing two pressed curved saddles beneath oil tank",
           [(zz-.026,contour),(zz+.026,contour)],"Saddle iron")
        for s in (-1,1):
            B(m,"Saddle flange angled fastening plate","Tank shade",s*.154,zz,.085,.070,.217,.247,.006)
            C(m,"Roof tank strap mounting bolt foundation","Valve nickel",(s*.179,zz,.249),
               .009,"h",-.008,.009,10)
        # Real closed radial sleeves press around the entire vessel.
        z0,z1=zz-.017,zz+.017
        outer=[(rx*1.032*cos(tau*i/24),yc+ry*1.033*sin(tau*i/24)) for i in range(24)]
        inner=[(rx*.997*cos(tau*i/24),yc+ry*.997*sin(tau*i/24)) for i in range(24)]
        g="Two separate closed full circumference tension bands"
        for i in range(24):
            j=(i+1)%24
            a,b,c,d=outer[i],outer[j],inner[i],inner[j]
            def v(p,z):return p[0],z,p[1]
            for q in ((v(a,z0),v(a,z1),v(b,z1),v(b,z0)),
                      (v(c,z1),v(c,z0),v(d,z0),v(d,z1)),
                      (v(c,z0),v(a,z0),v(b,z0),v(d,z0)),
                      (v(a,z1),v(c,z1),v(d,z1),v(b,z1))):
                face(m,g,"Steel straps",q)
    hatch=.247
    C(m,"Bolted circular top dome access flange","Steel straps",(0,hatch,.615),.072,"h",-.013,.022,22)
    C(m,"Satin circular oil filling hatch dome","Tank hatch bronze",(0,hatch,.637),.060,"h",-.008,.021,22)
    C(m,"Painted inner lid recess","Tank shade",(0,hatch,.658),.044,"h",-.006,.008,18)
    for i in range(8):
        a=tau*i/8
        C(m,"Circular fastener mounting ears","Valve nickel",(.062*cos(a),hatch+.062*sin(a),.640),
          .006,"h",-.003,.005,7)
    rod(m,"Curved top hatch manipulator lever","Ladder steel",(-.031,hatch,.663),(.038,hatch,.676),.007)
    C(m,"Separate short pressure relief nipple","Tank hatch bronze",(.079,.432,.608),.022,"h",-.012,.030,13)
    for s in (-1,1):
        y=.285;x=s*.191
        B(m,"Side protective deployed hose storage trough","Hose retention steel",x,.266,.068,.724,
          y-.017,y+.013,.008)
        for z in (.009,.193,.391,.562):
            B(m,"Separate adjustable hose band retaining brackets","Steel straps",x,z,
              .066,.022,y-.024,y+.046,.006)
        rod(m,"Separate long continuous flexible delivery hose","Booth hose",(x,-.065,y+.025),(x,.620,y+.025),.012)
        rod(m,"Visible steel coupler on hose tail","Valve nickel",(x,.593,y+.025),(x,.640,y+.025),.017)
        for z in (.060,.230,.413,.574):
            rod(m,"Attached load-tank service top side rail supports","Steel straps",
                (s*.114,z,yc+.126),(s*.114,z,.644),.005)
        rod(m,"Real long Foster top service grab rails","Ladder steel",
          (s*.114,-.028,.644),(s*.114,.599,.644),.007)
    for x in (.106,.170):
        p=[(x,.741,.232),(x,.762,.393),(x,.713,.530),(x,.646,.628)]
        for a,b in zip(p,p[1:]):rod(m,"Angled tail maintenance ladder stringers","Ladder steel",a,b,.008)
    for x in (.106,.170):
        rod(m,"Welded upper ladder mounting heel ties to tank hoops","Ladder steel",
            (x,.650,.626),(x,.637,.548),.008)
        rod(m,"Lower ladder foot stays seat on tank tray frame","Hose retention steel",
            (x,.743,.243),(x,.704,.249),.008)
    for zz,h in ((.746,.281),(.753,.337),(.761,.388),(.743,.443),(.725,.492),(.699,.549),(.658,.605)):
        rod(m,"Individual round anti-slip tail ladder rungs","Valve nickel",(.106,zz,h),(.171,zz,h),.0068)
    B(m,"Covered oil valve rear catch pan","Tank tray",-.071,.716,.187,.125,.237,.278,.010)
    C(m,"Flanged actual gravity discharge oil tube","Hose retention steel",(-.067,.707,.332),
      .035,"z",-.044,.052,15)
    C(m,"Separate round visible pipe joint flange","Valve nickel",(-.067,.754,.332),.048,"z",-.005,.009,18)
    C(m,"Deep open oil valve mouth and black gasket","Booth hose",(-.067,.765,.332),.022,"z",-.002,.005,14)
    rod(m,"Independent shutoff valve angled red lever","Valve warn red",
        (-.068,.764,.349),(-.146,.772,.383),.012)
    for color,sz,z in (("Warning pale",.040,.740),("Valve warn red",.034,.744)):
        x,y=-.069,.455
        face(m,"Original diamond cargo caution marking",color,
            ((x-sz,z,y),(x,z,y+sz),(x+sz,z,y),(x,z,y-sz)))
    tail_lighting(m,.739)


def mail(m):
    rows=[(-.771,.177,.420,.206),(-.747,.222,.460,.203),(-.710,.244,.510,.199),
          (-.661,.258,.575,.197),(-.609,.260,.633,.200),(-.555,.263,.652,.204),
          (-.320,.263,.651,.208),(-.250,.246,.634,.215),(-.209,.225,.603,.224)]
    cab_shape(m,rows)
    def p(s,f,z,lift):
        for a,b in zip(rows,rows[1:]):
            if a[0]<=z<=b[0]:
                t=(z-a[0])/(b[0]-a[0])
                w,h=[a[i]+(b[i]-a[i])*t for i in (1,2)]
                return (s*w*f,z,h+lift-max(0,f-.72)*.11)
        raise ValueError(z)
    for s in (-1,1):
        for tag,c,first,last,span,lift in (
            ("Reynard curved wrap screen gasket","Glass rim",-.729,-.607,.84,.008),
            ("Separate swept twin front laminate panes","Glass",-.720,-.613,.765,.014),
            ("Soft sky top reflection on front panes","Glass glint",-.631,-.621,.69,.017),
        ):
            zs=[first,*(a[0] for a in rows if first<a[0]<last),last]
            for a,b in zip(zs,zs[1:]):
                fs=(.06,.31,.55,span)
                for u,v in zip(fs,fs[1:]):
                    face(m,tag,c,(p(s,u,a,lift),p(s,v,a,lift),p(s,v,b,lift),p(s,u,b,lift))[::s])
        rod(m,"Original low front windscreen wiper arm","Glass rim",
            p(s,.191,-.716,.020),p(s,.536,-.687,.021),.0034)
        rod(m,"Original narrow wiper blade","Glass rim",
            p(s,.536,-.687,.021),p(s,.625,-.663,.021),.0027)
    side_cab(m,-.477,.260,.393,.537)
    front_bumper(m,-.779,.476,"square")
    B(m,"Reynard navy compact twin horizontal intake mouths","Front grille",0,-.785,.231,.024,.255,.345,.010)
    for j in (0,1,2,3):
        B(m,"Four industrial cast silver intake guide bars","Cab trim",0,-.798,.199,.008,
          .264+j*.019,.269+j*.019,.002)
    # Closed, period weather-proof box with a much flatter rain canopy than
    # the stock livestock van. Recessed mail loading surfaces are actual 3D.
    def outer(z,x,b,h):
        return z,[(-x*.86,b),(x*.86,b),(x,b+.031),(x,h-.070),(x*.945,h-.027),
                  (x*.72,h),(-x*.72,h),(-x*.945,h-.027),(-x,h-.070),(-x,b+.031)]
    sections=[outer(-.208,.215,.222,.612),outer(-.177,.252,.220,.644),
              outer(-.121,.255,.220,.655),outer(.674,.255,.220,.655),
              outer(.724,.249,.226,.636),outer(.748,.223,.236,.608)]
    road.section_hull(m,"Watertight Reynard sealed mail van curved crown shell",sections,
       ["Van steel floor","Van midnight","Van panel enamel","Van lid canvas","Van crown",
        "Van crown","Van crown","Van lid canvas","Van panel enamel","Van midnight"],"Van shallow blue")
    for s in (-1,1):
        xx=s*.256
        for y,color in ((.279,"Van midnight"),(.565,"Van trim bright"),(.591,"Van cover seam")):
            rod(m,"Independently fixed long exterior van rain and rubbing rail",color,
              (xx,-.151,y),(xx,.709,y),.006)
        for z0 in (-.120,.070,.326,.546,.704):
            B(m,"Visible postal side welded frame edge","Van shallow blue",xx,z0,.018,.018,.261,.560,.004)
            for y in (.279,.535):
                C(m,"Period pressed double row of van fasteners","Van hinge tone",(xx+s*.011,z0,y),
                  .005,"x",-.002,.003,7)
        B(m,"Actual broad sliding parcel door deep rail shadow","Van parcel shadow",xx,.286,
          .025,.401,.288,.554,.009)
        B(m,"Wall mounted sliding steel mail door main body","Van panel enamel",xx+s*.013,.286,
          .017,.375,.297,.546,.009)
        for y in (.306,.527):
            B(m,"Visible cargo sliding door upper and lower pressed channels","Van trim bright",xx+s*.021,
                .286,.009,.346,y-.005,y+.005,.002)
        B(m,"Van compact bronze parcel door recessed pull","Stamp detail",xx+s*.021,.430,
          .014,.045,.396,.432,.004)
        rod(m,"Solid actual loading door pull fixture","Van hinge tone",
          (xx+s*.029,.413,.403),(xx+s*.029,.446,.424),.004)
        B(m,"Bone fleet belt ahead of mail icon","Van cream trim",xx+s*.006,-.040,
          .011,.193,.384,.423,.005)
        B(m,"Bone fleet belt supplement aft of mail icon","Van cream trim",xx+s*.006,.585,
          .011,.222,.384,.423,.005)
        # Simple generic letter envelope, authored from actual raised
        # lines rather than using a real postal logo or projected texture.
        P=lambda z,y:(xx+s*.027,z,y)
        left,right=.212,.339
        lo,hi=.380,.463
        for a,b in (((left,lo),(right,lo)),((left,hi),(right,hi)),
                    ((left,lo),(left,hi)),((right,lo),(right,hi)),
                    ((left,hi),(.274,.412)),((.274,.412),(right,hi)),
                    ((left,lo),(.244,.411)),((right,lo),(.307,.411))):
            rod(m,"Raised original line-art letter symbol","Van envelope line",P(*a),P(*b),.0033)
    for j in range(7):
        zz=-.092+j*.122
        for s in (-1,1):
            contour=[(0,zz,.655),(s*.093,zz,.654),(s*.180,zz,.651),(s*.218,zz,.632)]
            for a,b in zip(contour,contour[1:]):
                rod(m,"Thin rounded weather roof canvas crossbow seam","Van cover seam",a,b,.0029)
    for s in (-1,1):
        xx=s*.112
        B(m,"Dark rear double mail door rubber joint","Van parcel shadow",xx,.746,
          .217,.026,.252,.603,.008)
        B(m,"Distinct press-stamped closed mail compartment doors","Van panel enamel",xx,.763,
          .198,.016,.262,.593,.007)
        B(m,"Cream aft registration band across double doors","Van cream trim",xx,.775,.196,.008,.400,.432,.003)
        for y in (.290,.525):
            B(m,"Four separately bolted tail swing-door hinge plates","Van hinge tone",s*.187,.781,
              .058,.012,y-.011,y+.013,.003)
            C(m,"Real separate van gate hinge pivot barrel","Nickel",(s*.214,.779,y),
              .009,"h",-.017,.020,11)
        rod(m,"Painted rear mail door external vertical latch shaft","Van hinge tone",
          (s*.023,.780,.280),(s*.023,.781,.550),.0053)
        rod(m,"Rear mail gate bent latch handle","Nickel",
          (s*.023,.785,.408),(s*.063,.790,.436),.0066)
    B(m,"Heavy straight rear mail platform protective bumper","Van midnight",0,.771,
      .478,.039,.217,.253,.010)
    tail_lighting(m,.752)


def save_atlas(path,palette):
    def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    row=b"".join(bytes.fromhex(v)*16 for v in palette.values())
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",1024,16,8,2,0,0,0))
                     +chunk(b"IDAT",zlib.compress((b"\0"+row)*16))+chunk(b"IEND",b""))


def make(kind,stem,label,stock_id,builder):
    colors=init_color(kind)
    model=ROOT/"mods/luanttd_core/models"
    tex=ROOT/"mods/luanttd_core/textures"
    save_atlas(tex/f"bl_{stem}_atlas.png",colors)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name=f"LuanTTD | {label} #{stock_id}"
    scene["game"]="OpenTTD 16.0-RC1"
    scene["engine_id"]=stock_id
    scene["native"]="−Z nose, literal Y=0 tread, visual size .42"
    co=bpy.data.collections.new("01 • Editable original truck, chassis and running gear")
    scene.collection.children.link(co)
    body=r.Mesh(r.terrain_height(0))
    chassis(body,kind)
    builder(body)
    mats=r.materials()
    for name,mat in zip(colors,mats):
        mat.name=name
        p=mat.node_tree.nodes.get("Principled BSDF")
        p.inputs["Roughness"].default_value=.32 if "Glass" in name else .72 if "Coal" in name else .60
        p.inputs["Metallic"].default_value=.38 if "Steel" in name or "Nickel" in name else .06
    r.to_blender(body,co,mats)
    variants=[("",body)]
    cargo=None
    if kind=="coal":
        contents=r.Mesh(r.terrain_height(0))
        coal_payload(contents)
        cargo=bpy.data.collections.new("02 • Independently toggled coal load (98 closed 3D rocks)")
        scene.collection.children.link(cargo)
        r.to_blender(contents,cargo,mats)
        full=deepcopy(body)
        for group,faces in contents.parts.items():
            for ins,color in faces:
                full.tri(group,color,[contents.vertices[group][i] for i in ins])
        variants.append(("_loaded",full))
    for suffix,mesh in variants:
        file=model/f"bl_{stem}{suffix}.obj"
        r.export_obj(file,w.local_obj(mesh))
        arr=file.read_text().splitlines()
        arr[0]=f"# Original LuanTTD {label}; tools/build_stock_road_fleet_d_art.py"
        file.write_text("\n".join(arr)+"\n")
    prev=set(scene.objects)
    road.studio(scene)
    studio=bpy.data.collections.new("90 • Inspection cameras and pavement. Not exported")
    scene.collection.children.link(studio)
    front=scene.camera
    shots=[("front",front,(2.11,-2.63,1.55)),("rear",None,(2.11,2.66,1.61)),
           ("empty" if cargo else "side",None,(2.11,2.66,1.61) if cargo else (3.48,.60,.81))]
    views=[]
    for name,cam,place in shots:
        if cam is None:
            cam=front.copy()
            cam.data=front.data.copy()
            scene.collection.objects.link(cam)
        cam.name=f"{name.title()} inspection"
        cam.location=place
        cam.rotation_euler=(V((0,0,.326))-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.ortho_scale=1.96 if name!="side" else 1.90
        views.append((name,cam))
    for ob in set(scene.objects)-prev:
        for layer in list(ob.users_collection):layer.objects.unlink(ob)
        studio.objects.link(ob)
    scene.render.resolution_x,scene.render.resolution_y=1050,740
    scene.render.resolution_percentage=100
    scene.view_settings.exposure=.49
    scene.display.shading.studiolight_rotate_z=.38
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{stem}.blend"),compress=True)
    if qa:=os.getenv("ROAD_D_QA"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        for name,cam in views:
            if cargo:cargo.hide_render=name=="empty"
            scene.camera=cam
            scene.render.filepath=str(Path(qa)/f"{stem}-{name}.jpg")
            bpy.ops.render.render(write_still=True)


def main():
    requested=os.environ.get("ROAD_D_ONLY","coal,oil,mail").split(",")
    for group,stem,label,id,builder in (("coal","stock_uhl_coal_truck","Uhl Coal Truck",124,coal),
        ("oil","stock_foster_oil_tanker","Foster Oil Tanker",133,tanker),
        ("mail","stock_reynard_mail_truck","Reynard Mail Truck",127,mail)):
        if group in requested:
            make(group,stem,label,id,builder)


if __name__=="__main__":
    main()
