#!/usr/bin/env python3
"""Original standard-gauge tender 4-6-0 for stock temperate engine 8.

blender -b -t 4 --python-exit-code 1 --python tools/build_chaney_jubilee_art.py
Set JUBILEE_ART_RENDER=/path/studio.png for editable geometry preview.

OpenTTD 14.1 engine 8 Chaney Jubilee is one default-length rail controller
part. The tender is detailed original coachwork within the same body,
not a separately simulated part. OpenGFX base sprite 2905 is a company
blue cue only; no pixel or copied mesh is included. Native nose -Z,
wheel contact Y=0, 10 OBJ units per node, visual_size 1.
"""
from math import cos,pi,sin,sqrt,tau
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_kirby_art as K
W,R=K.wag,K.rail
ROOT=R.ROOT
NAME="bl_rail_chaney_jubilee"
PALETTE={
    "Boiler royal blue":"345372","Blue crown sheen":"537897","Shade blue":"253e59","Cab plate cobalt":"3d6281",
    "Lower royal blue casing":"2c4b66","Blue cab enamel shadow":"26394a","Line bronze":"bb9970",
    "Fine warm ivory":"dbc5a0","Gloss pinstripe amber":"ca8c59","Plate black ink":"443a32",
    "Gunmetal smoke plate":"353e40","Smoke face warm graphite":"4c5756","Oiled soot":"2d3638",
    "Tarnished footplate seam":"5f6e6b","Footboard iron black":"414949","Body frame gray":"414b4c",
    "Bogie blackened steel":"363c41","Nickel running tread":"848e89","Recessed flange steel":"52605c",
    "Big wheel blue painted iron":"3e5363","Driver spoke glaze blue":"617684","Rim rim muted slate":"697b7a",
    "Forged rod nickel":"bac4b8","Forged rod dark bevel":"78837c","Connecting pin brass":"a78f6e",
    "Greased crosshead":"626a62","Copper water feeder":"a87c54","Dark copper heat":"6d5444",
    "Deep red headstock buffer":"9c534b","Red edge sunlight":"ae6455","Cast spring face":"78847c",
    "Rubber air line black":"353c3b","Warm lamp front":"f1daa6","Rear ruby guard lamp":"bc5b4d",
    "Cab glass bright":"759ba3","Cab glass deep":"324650","Neutral firebox dark":"513f39",
    "Firebox orange embers":"c48858","Tender coal matte":"353738","Tender coal reflection":"4a4e4a",
    "Bunker bare coal black":"272c2f","Tender wood floor":"796454","Clean valve wheel":"8c6960",
    "QA ballast backdrop":"7b7464",
}
P={c:i for i,c in enumerate(PALETTE)}
W.P=P
R.COLORS[:]=PALETTE.values()
B,Disk=W.slab,W.circular
Lathe,Pipe,Beam=K.profile_tube,K.pipe,K.beam
GAUGE=.424
COUPLER=.499
BOGIE=(-.304,-.251)
DRIVERS=(-.148,-.007,.134)
TENDER=(.218,.267,.316)
DR=.063

def mesh():
    return R.Mesh(R.terrain_height(0))

def face(m,n,c,p):
    m.face(n,P[c],p)

def post(m,n,c,x,z,h,r0,r1,nseg=14):
    Lathe(m,n,[(h[0],r0),(h[1],r1)],"h",(x,z,0),(c,),nseg)

def shaped(m,n,c,levels,g0,g1,cap=None):
    if R.signed_area(levels)<0:levels=levels[::-1]
    a=[(x,z,g0) for x,z in levels]
    b=[(x,z,g1) for x,z in levels]
    face(m,n,c,a[::-1])
    face(m,n,cap or c,b)
    for i in range(len(a)):
        j=(i+1)%len(a)
        face(m,n,c,(a[i],a[j],b[j],b[i]))

def underframe(m):
    # Narrow shaped ends preserve neighboring wagon swing on the stock
    # short radius, rather than hiding body penetrations with clips.
    crown=[(-.125,-.419),(.125,-.419),(.212,-.325),(.211,.143),
        (.179,.180),(-.179,.180),(-.211,.143),(-.212,-.325)]
    shaped(m,"Tapered continuous steel engine footplate","Footboard iron black",crown,.178,.208,"Tarnished footplate seam")
    B(m,"Rigid locomotive front bogie cross spring","Body frame gray",0,-.279,.334,.104,.083,.153,.010)
    B(m,"Deep high frame locomotive plate","Body frame gray",0,-.079,.365,.520,.076,.188,.021)
    for s in (-1,1):
        B(m,"Fine cobalt locomotive chassis valance","Lower royal blue casing",
          s*.199,-.087,.014,.470,.163,.179,.007)
        B(m,"Raised forward running board nickel edge","Tarnished footplate seam",
          s*.200,-.090,.014,.462,.200,.211,.004)
        for z in DRIVERS:
            B(m,"Laminated leaf springs above driver","Cast spring face",
              s*.159,z,.039,.102,.104,.118,.007)
            B(m,"Body journal box visible lower recess","Bogie blackened steel",s*.178,z,.022,.060,.072,.116,.008)
            for i in range(3):
                B(m,"Three separate spring leaves","Greased crosshead",s*.165,z,.031,.098-i*.012,
                  .112+i*.006,.115+i*.006)
        for z in (.112,.163):
            B(m,"Separate crew rung foot steps","Cast spring face",s*.206,z,.049,.028,.115,.129,.004)
        B(m,"Rear steam brake pivot","Bogie blackened steel",s*.154,.127,.056,.057,.051,.090,.009)
    # Compact drawbar that visibly connects the two separately built
    # structures. It is centered, not a fake second train path.
    B(m,"Integral cab-tender visible short swivel drawbar","Tarnished footplate seam",0,.193,.070,.058,.119,.143,.009)
    TENDER_SHAPE=[(-.185,.205),(.185,.205),(.189,.357),(.156,.407),(.119,.444),
                  (-.119,.444),(-.156,.407),(-.189,.357)]
    shaped(m,"Shaped shortened tender separate carrying chassis","Body frame gray",
           TENDER_SHAPE,.067,.130,"Footboard iron black")
    for s in (-1,1):
        Pipe(m,"External separate tender water return hose","Rubber air line black",(s*.093,.164,.176),
             (s*.099,.222,.145),.006,8)
        for z in TENDER:
            B(m,"Visible leaf sprung tender axlebox","Cast spring face",s*.176,z,.024,.028,.063,.091,.008)
    for side in (-1,1):
        for z in BOGIE:
            B(m,"Forward pilot truck weather shields","Bogie blackened steel",
              side*.214,z,.078,.050,.059,.071,.008)
        for z in TENDER:
            B(m,"Tender three independent journal dust caps","Bogie blackened steel",
              side*.212,z,.082,.045,.052,.062,.007)
    for end in (-1,1):
        B(m,"Red locomotive and tender beam face","Deep red headstock buffer",0,end*.411,.242,.025,.118,.193,.009)
        B(m,"Railway red headstock overscan glint","Red edge sunlight",0,end*.423,.200,.007,.168,.183,.002)
        for x in (-.086,.086):
            # Recess narrow buffers from the rigid junction to the flexible
            # draw endpoints; the single central knuckle is at +/- .499.
            rows=sorted((end*z,r) for z,r in ((.416,.025),(.421,.020),(.428,.024),(.431,.025)))
            Lathe(m,"Independent turned steel buffer springs and faces",rows,"z",(x,0,.175),
                  ("Smoke face warm graphite","Cast spring face","Cast spring face"),18)
            Pipe(m,"Steam brake hose visible loop","Rubber air line black",
                (x*.52,end*.425,.141),(x*.72,end*.447,.108),.006,10)
        B(m,"Coupler central forged guide pocket","Footboard iron black",0,end*.448,.094,.039,.130,.193,.009)
        B(m,"Coupler draw arm pinned collar","Greased crosshead",0,end*.465,.060,.035,.133,.182,.008)
        B(m,"Coupler forged shoulder","Cast spring face",0,end*.475,.043,.019,.1305,.1835,.007)
        B(m,"Coupler knuckles","Cast spring face",0,end*.489,.014,.020,.1305,.1835,.004)

def axles(m,family,centers,rad,half,phase=0):
    # Large spoked drivers and separate small truck/tender wheels. All
    # treads touch Y=0, and the narrow flange lip fits stock inside groove.
    for z in centers:
        Disk(m,f"{family} full chair-span steel axles","Bogie blackened steel",(0,z,rad),rad*.25,"x",-.214,.214,14)
        for s in (-1,1):
            x=s*GAUGE/2
            suffix="L" if s<0 else "R"
            back=rad*.75
            slim=half if family=="Driver" else .020
            l,r=sorted((s*half,-s*slim))
            # The true outboard running lip rides a tight stock curve, but
            # a dark edge on the small wheels reads as a turned steel rim
            # rather than a long horizontal roller. Visible ring center
            # stays the exact stock gauge on all three wheel families.
            Lathe(m,f"Rolling tread {family} {suffix}",
               [(l,back),(l,rad),(l+.006,rad),(r-.006,rad),(r,rad),(r,back),(l,back)],
               "x",(x,z,rad),("Recessed flange steel","Rim rim muted slate",
                  "Nickel running tread","Rim rim muted slate","Recessed flange steel","Bogie blackened steel"),24,False,False)
            a,b=sorted((-s*.042,-s*.035))
            Lathe(m,"True inward rail guiding wheel flanges",
                  [(a,rad*.70),(a,rad+.009),(b,rad+.009),(b,rad*.70),(a,rad*.70)],
                  "x",(x,z,rad),("Recessed flange steel",),24,False,False)
            dx=s*.020
            if family=="Driver":
                Disk(m,"Driver full visible central body hub","Driver spoke glaze blue",
                      (x+dx,z,rad),.026,"x",-.009,.010,16)
                for i in range(10):
                    q=tau*i/10+phase+(pi/2 if s>0 else 0)
                    x0,z0=rad*.27*cos(q),rad*.27*sin(q)
                    x1,z1=rad*.79*cos(q),rad*.79*sin(q)
                    Beam(m,"Ten separately shaped Jubilee driving-wheel spokes","Big wheel blue painted iron",x+dx,
                         (z+x0,rad+z0),(z+x1,rad+z1),.006,.013)
                for i in range(5):
                    q=tau*i/5+phase
                    Disk(m,"Quartered big axle number bolts","Connecting pin brass",
                        (x+s*.031,z+.013*cos(q),rad+.013*sin(q)),.0038,"x",-.004,.005,7)
                for j in range(5):
                    a=phase+pi/2+j*.15
                    plate=[(x+s*.025,z+rr*cos(t),rad+rr*sin(t))
                           for rr,t in ((rad*.77,a),(rad*.79,a+.17),(rad*.48,a+.17),(rad*.48,a))]
                    face(m,"Driving wheel counterweight crescent segments","Driver spoke glaze blue",
                         plate if s>0 else plate[::-1])
            else:
                Disk(m,"Solid small spoke plate axle casting","Big wheel blue painted iron",
                     (x+s*.024,z,rad),rad*.74,"x",-.012,.019,18)
                for i in range(7):
                    q=tau*i/7
                    Disk(m,"Small bogie and tender spoke-web rivets","Cast spring face",
                         (x+s*.042,z+rad*.45*cos(q),rad+rad*.45*sin(q)),.0031,"x",-.004,.004,7)
            Disk(m,"Bright lubricator center cap on wheels","Nickel running tread",(x+s*.042,z,rad),
                 rad*.187,"x",-.004,.006,11)

def motion(m,phase):
    for s in (-1,1):
        a=phase+pi/2*(s>0)
        crank=.018
        pins=[(z+crank*cos(a),DR+crank*sin(a)) for z in DRIVERS]
        sx=s*.248
        for z,y in pins:
            Disk(m,"Quartered rotating driver crank pin brass faces","Connecting pin brass",
                 (sx,z,y),.009,"x",-.006,.007,14)
            Disk(m,"Rotating crank pin cap retaining plates","Forged rod dark bevel",
                 (sx+s*.007,z,y),.006,"x",-.004,.004,12)
        Beam(m,"Long side-railing continuous forged coupling rod","Forged rod nickel",sx,pins[0],pins[-1],.014,.009)
        Beam(m,"Continuous low highlight coupling rod web","Forged rod dark bevel",sx+s*.008,
             (pins[0][0],pins[0][1]-.002),(pins[-1][0],pins[-1][1]-.002),.004,.003)
        cp=-.218+crank*cos(a)
        Beam(m,"Eccentric main crosshead piston rod","Forged rod dark bevel",s*.255,(cp,.095),pins[1],.017,.010)
        Beam(m,"Wide main rod central polished flutes","Forged rod nickel",s*.261,(cp,.095),pins[1],.005,.004)
        Pipe(m,"Piston exposed true chrome sleeve","Forged rod nickel",(s*.224,-.321,.095),
             (s*.224,cp,.095),.0063,10)
        B(m,"Crosshead guide sliding bronze shoe","Greased crosshead",s*.228,cp,.031,.026,.081,.108,.003)
        lp=(pins[1][0]-.008,pins[1][1]+.019)
        Beam(m,"Valve gear return crank stamped link lever","Forged rod nickel",s*.261,lp,(cp-.012,.115),.008,.006)
    for s in (-1,1):
        Lathe(m,"Outboard turned steam cylinder valve castings",
                  [(-.347,.018),(-.336,.035),(-.314,.039),(-.271,.039),(-.260,.032),(-.252,.018)],
                  "z",(s*.184,0,.106),
                  ("Cast spring face","Body frame gray","Bogie blackened steel","Cast spring face","Body frame gray"),18)
        for i in range(7):
            q=tau*i/7
            Disk(m,"Polished cylinder cap screw heads","Forged rod dark bevel",
                 (s*.184+.027*cos(q),-.338,.106+.027*sin(q)),.004,"z",-.004,.004,8)

def hardware(m):
    H=.404
    Lathe(m,"Long royal blue unobstructed cylindrical boiler casing",[
         (-.343,.111),(-.333,.127),(-.300,.134),(-.257,.137),(-.111,.142),(-.059,.149),
         (.009,.148),(.085,.144),(.128,.137)],"z",(0,0,H),
        ("Shade blue","Boiler royal blue","Boiler royal blue","Boiler royal blue","Lower royal blue casing",
         "Boiler royal blue","Lower royal blue casing","Shade blue"),36)
    for i,z in enumerate((-.287,-.186,-.087,.037,.103)):
        r=(.137,.145,.151,.150,.144)[i]
        Lathe(m,"External locomotive rolled boiler binding rings",
              [(z-.003,r-.004),(z-.001,r+.002),(z+.004,r+.002),(z+.005,r-.003)],
              "z",(0,0,H),("Shade blue","Blue crown sheen","Fine warm ivory"),32,False,False)
    Lathe(m,"Oversized gunmetal smokebox casing and dished door",
       [(-.426,.050),(-.421,.074),(-.416,.109),(-.410,.130),(-.405,.140),(-.389,.143),
        (-.339,.139),(-.316,.133)],"z",(0,0,H),
       ("Smoke face warm graphite","Oiled soot","Smoke face warm graphite","Gunmetal smoke plate",
        "Gunmetal smoke plate","Oiled soot","Smoke face warm graphite"),34)
    Lathe(m,"Smokebox hinged concentric door closure ring",
       [(-.418,.105),(-.412,.127),(-.407,.134),(-.405,.128)],
       "z",(0,0,H),("Gunmetal smoke plate","Oiled soot","Smoke face warm graphite"),34,False,False)
    for i in range(18):
        q=tau*i/18
        Disk(m,"Turned steel smokebox bolt faces","Cast spring face",
           (.127*cos(q),-.413,H+.127*sin(q)),.0035,"z",-.003,.002,8)
    for h in (.357,.451):
        B(m,"Smoke door long pressed hinge brackets","Gunmetal smoke plate",-.084,-.426,.060,.011,h-.008,h+.008,.004)
        Pipe(m,"Smokebox vertically hung hinges","Cast spring face",(-.112,-.429,h-.013),(-.112,-.429,h+.015),.005,8)
    Disk(m,"Independently lathed front inspection locking centre","Cast spring face",(0,-.433,H),.019,"z",-.007,.006,18)
    Pipe(m,"Twin turning smokebox hand-latch levers","Forged rod nickel",(-.027,-.441,H),(.028,-.441,H),.004,8)
    Pipe(m,"Twin turning smokebox hand-latch levers","Forged rod nickel",(0,-.441,H-.022),(0,-.441,H+.021),.0035,7)
    B(m,"Oval black cast smokebox number plate","Oiled soot",0,-.429,.075,.013,.469,.496,.006)
    front_glyphs(m,"0814",.483,-.436,.0041,"Fine warm ivory",False)
    Lathe(m,"Taper shouldered separate air chimney with open bore",[
       (.520,.055),(.553,.057),(.568,.046),(.596,.036),(.624,.035),
       (.657,.037),(.674,.039),(.681,.052),(.689,.054),(.694,.049),(.694,.032),(.676,.031),(.667,.030)],
       "h",(0,-.361,0),("Gunmetal smoke plate","Smoke face warm graphite","Oiled soot","Gunmetal smoke plate",
        "Gunmetal smoke plate","Smoke face warm graphite","Oiled soot","Gunmetal smoke plate",
        "Smoke face warm graphite","Oiled soot","Oiled soot","Oiled soot"),30,True,False)
    Lathe(m,"Large belpaire steam dome shell and panelled liner",[
       (.529,.063),(.551,.065),(.564,.056),(.596,.046),(.616,.031),(.623,.018),(.624,.006)],
       "h",(0,-.119,0),("Shade blue","Boiler royal blue","Boiler royal blue","Blue crown sheen",
        "Boiler royal blue","Blue crown sheen"),28)
    Lathe(m,"Tall small brass steam top safety fittings",
       [(.541,.023),(.555,.024),(.563,.015),(.590,.010),(.607,.012),(.613,.015)],
       "h",(.003,.026,0),("Copper water feeder","Dark copper heat","Line bronze","Gloss pinstripe amber","Line bronze"),18)
    for s in (-1,1):
        Pipe(m,"Handrails nickel rods following boiler shoulder","Forged rod nickel",
             (s*.126,-.397,.458),(s*.151,.103,.477),.0042,10)
        for q in (-.345,-.223,-.104,.024,.096):
            Pipe(m,"Boiler shoulder stand-off rail mounting feet","Cast spring face",
                (s*.108,q,.458),(s*.145,q,.471),.0051,8)
        Pipe(m,"External live-seat feed water pipe upper elbow","Copper water feeder",
            (s*.164,-.205,.327),(s*.141,.068,.375),.0074,10)
        Pipe(m,"External live-seat feed water pipe lower elbow","Copper water feeder",
            (s*.164,-.205,.327),(s*.181,-.285,.244),.0074,10)
        Pipe(m,"Copper feed water pipe isolation spool","Dark copper heat",
            (s*.181,-.285,.244),(s*.183,-.291,.196),.007,8)
        for q in (-.251,-.076):
            Pipe(m,"Warm feeder pipe steel jacket clamp","Forged rod dark bevel",
                 (s*.160,q,.320),(s*.174,q,.320),.010,8)
        B(m,"Firebox flat boundary pressed cheek plates","Lower royal blue casing",
          s*.132,.079,.083,.097,.210,.426,.012)
        B(m,"Accent amber lining over blue firebox panel","Gloss pinstripe amber",
          s*.174,.079,.005,.079,.247,.253,.001)
        B(m,"Long black flat crew step at cab sides","Footboard iron black",
          s*.213,.126,.044,.077,.163,.177,.004)
    # Real lamp castings, one safety lens at the tender tail.
    for x in (-.084,.084):
        B(m,"Separate cast head lamps with mounting foot","Gunmetal smoke plate",x,-.421,.047,.032,
           .222,.266,.005)
        Disk(m,"Amber clear polished front locomotive lamp lens","Warm lamp front",
          (x,-.443,.246),.016,"z",-.003,.003,15)
    B(m,"Separate tail route lamp on tender","Bogie blackened steel",0,.435,.039,.043,.327,.370,.008)
    Disk(m,"Tender ruby glass rear end-of-train lamp","Rear ruby guard lamp",(0,.460,.349),.013,"z",-.005,.005,14)

GLYPHS={
    "0":("111","101","101","101","111"),
    "1":("010","110","010","010","111"),
    "4":("101","101","111","001","001"),
    "8":("111","101","111","101","111"),
    "J":("111","001","001","101","111"),
    "U":("101","101","101","101","111"),
    "B":("110","101","110","101","110"),
    "I":("111","010","010","010","111"),
    "L":("100","100","100","100","111"),
    "E":("111","100","110","100","111"),
    "C":("111","100","100","100","111"),
    " ":("000",)*5,
}

def front_glyphs(m,letters,h,z,step,col,reverse=False):
    start=-.5*(4*len(letters)-1)*step
    for j,k in enumerate(letters):
        for v,row in enumerate(GLYPHS[k]):
            for i,t in enumerate(row):
                if t!="1":continue
                x=start+(j*4+i)*step
                if reverse:x=-x-step
                y=h+(2.5-v)*step
                c=[(x,z,y-step),(x+step,z,y-step),(x+step,z,y),(x,z,y)]
                face(m,"Raised smokebox original identification characters",col,c[::-1] if reverse else c)

def lettering(m,n,text,x,z,h,s,scale=.0045):
    start=-.5*(4*len(text)-1)*scale
    for j,k in enumerate(text):
        for row,col in enumerate(GLYPHS[k]):
            for i,p in enumerate(col):
                if p!="1":continue
                d=z+s*(start+(4*j+i)*scale)
                y=h+scale*(2.5-row)
                a=[(x,d,y-scale),(x,d+s*scale,y-scale),(x,d+s*scale,y),(x,d,y)]
                face(m,n,"Fine warm ivory",a)

def cab_tender(m):
    # Deep sculptured glazed cab with visible real windows (shaped part
    # boundary, not a painted rectangle pretending to be an aperture).
    B(m,"Cab firebox and raised core footwell","Neutral firebox dark",0,.109,.342,.111,.214,.400,.012)
    for s in (-1,1):
        x=s*.182
        B(m,"Cab bottom pressed sheet envelope","Cab plate cobalt",x,.088,.024,.146,.203,.426,.005)
        B(m,"Cab left raised removable lower access lining","Lower royal blue casing",
          s*.197,.091,.007,.135,.231,.371,.003)
        for yy in (.247,.350):
            B(m,"Cab lining amber hairline inlay","Gloss pinstripe amber",s*.202,.089,.005,.135,yy,yy+.004)
        for q in (.026,.141):
            B(m,"Heavy steel cab corner window column","Blue cab enamel shadow",x,q,.026,.035,.422,.587,.004)
            B(m,"Applied fine warm cream cab pillar line","Gloss pinstripe amber",s*.197,q,.006,.015,.444,.572)
        B(m,"Cab cut-out side window top ledge","Shade blue",x,.080,.027,.143,.571,.604,.003)
        B(m,"Thin separate cab-side window glass channel","Cab glass deep",s*.170,.081,.006,.104,.437,.562,.003)
        B(m,"Clear blue reflection along cab side glazing","Cab glass bright",s*.174,.079,.003,.094,.521,.552,.001)
        B(m,"Raised driver's open doorway rear grip","Blue crown sheen",s*.197,.154,.012,.014,.433,.559,.002)
        B(m,"Fine side-cast oval maker badge","Line bronze",s*.203,.090,.008,.072,.276,.314,.006)
        B(m,"True dark bead within maker badge","Plate black ink",s*.208,.089,.006,.064,.281,.309,.005)
        lettering(m,"Individual engraved cab side coat number","814",s*.212,.089,.294,s,.0047)
        Pipe(m,"Cab handrail working against side wall","Forged rod nickel",
           (s*.207,.151,.224),(s*.207,.151,.413),.0045,8)
    for z1 in (.018,.166):
        for x in (-.088,.088):
            B(m,"Front and rear cab wall steel perforation frame","Cab plate cobalt",x,z1,.150,.014,.395,.588,.006)
            B(m,"Actual front and rear cab window inserted glazing","Cab glass deep",x,z1+(.007 if z1>.1 else -.007),
               .079,.009,.464,.558,.006)
    # Deep arched plate over the real vestibule, exact symmetrical rows.
    def roof(x):return .691-.058*(abs(x)/.205)**2
    for i in range(16):
        x0=-.207+i*.414/16; x1=x0+.414/16
        B(m,"Arched segmented full cab roof solid skin","Bogie blackened steel",(x0+x1)/2,.088,x1-x0,.190,
          lambda x,z:roof(x)-.018,lambda x,z:roof(x),.0,
          "Smoke face warm graphite" if i%3 else "Gunmetal smoke plate")
    for z in (.013,.177):
        for x in (-.169,.169):
            B(m,"Stamped short roof drip guards","Cast spring face",x,z,.073,.016,.634,.645,.003)
    B(m,"Cab room engine throttle horizontal regulator beam","Gunmetal smoke plate",0,.112,.297,.031,.304,.337,.009)
    for s in (-1,1):
        Disk(m,"Visible locomotive steam brake control wheel","Clean valve wheel",
             (s*.116,.123,.371),.024,"z",-.005,.006,16)
        Pipe(m,"Internal permanent control-cab water pipe","Copper water feeder",
             (s*.073,.129,.290),(s*.082,.123,.398),.007,9)
    B(m,"Firebox blinking metal hinged firedoor with cast frame","Neutral firebox dark",0,.115,.150,.022,
       .225,.291,.009)
    B(m,"Deep amber firebox light separator","Firebox orange embers",0,.126,.070,.009,.240,.273,.008)

    # Integral short separate appearanced coal tender with independent
    # chassis, visibly open top, swaged side panels and paired steps.
    boxprofile=[(-.183,.205),(.183,.205),(.188,.358),(.156,.404),(.121,.433),
       (-.121,.433),(-.156,.404),(-.188,.358)]
    shaped(m,"Coal tender elliptical bunker floor","Tender wood floor",boxprofile,.126,.194,"Bunker bare coal black")
    for s in (-1,1):
        p=[(s*.182,.205,.150),(s*.186,.356,.150),(s*.153,.398,.150),(s*.119,.432,.150),
            (s*.119,.432,.391),(s*.153,.398,.390),(s*.186,.356,.407),(s*.182,.205,.409)]
        face(m,"Tender curved deep painted side wall native thickness","Boiler royal blue",p if s>0 else p[::-1])
        q=[(x-s*.013,z,h) for x,z,h in p]
        face(m,"Tender thick inside open coal wall","Bunker bare coal black",q[::-1] if s>0 else q)
        for z0,z1,a,b in ((.205,.357,.182,.186),(.357,.398,.186,.153),(.398,.433,.153,.119)):
            for h in (.203,.355):
                Pipe(m,"British lined tender paired amber panel rules","Gloss pinstripe amber",
                     (s*(a+.002),z0+.002,h),(s*(b+.002),z1-.002,h),.0032,7)
            Pipe(m,"Tender visibly raised swaged upper curb rail",
                 "Line bronze",(s*a,z0,.407 if z0<.36 else .390),
                 (s*b,z1,.407 if z1<.36 else .390),.004,8)
        B(m,"Tender separate raised blue side plate","Cab plate cobalt",
          s*.187,.283,.010,.144,.221,.340,.006)
        B(m,"Tender brass inset marker","Line bronze",s*.194,.283,.006,.110,.262,.303,.005)
        B(m,"Tender black inset letterboard","Plate black ink",s*.198,.283,.005,.105,.267,.297,.004)
        lettering(m,"Tender original raised JUBILEE fleet identity","JUBILEE",s*.202,.283,.282,s,.00355)
        for q0 in (.221,.353):
            B(m,"Tender own access rails and rolled steps","Smoke face warm graphite",
               s*.157,q0,.041,.037,.102,.122,.004)
        Pipe(m,"Tender rear holding rail marker", "Cast spring face",(s*.118,.433,.220),(s*.118,.433,.352),.004,8)
    B(m,"Tender end plate blue closed taillight recess","Boiler royal blue",0,.426,.244,.018,.132,.389,.007)
    B(m,"Tender water lid shaped raised access hatch","Shade blue",0,.378,.155,.055,.350,.382,.006)
    B(m,"Tender front bulkhead carrying coal pile and narrow scene gap",
       "Blue cab enamel shadow",0,.212,.360,.017,.145,.410,.005)
    rng=Random(814)
    pile=[(-.145,.239,.336),(-.068,.227,.382),(.059,.226,.395),(.146,.239,.350),
          (.150,.345,.332),(.090,.369,.365),(-.082,.369,.350),(-.149,.343,.323)]
    for j,p in enumerate(pile):
        face(m,"Cast irregular integral tender coal bed","Tender coal matte",
             (p,pile[(j+1)%len(pile)],(0,.292,.417)))
    for j in range(45):
        x=rng.uniform(-.137,.137);z=rng.uniform(.242,.347);h=.362+.055*(1-abs(x)/.145)-abs(z-.276)*.17
        r=rng.uniform(.008,.019)
        a=[(x+cos(tau*i/5)*r,z+sin(tau*i/5)*r,h-r*.42) for i in range(5)]
        top=(x+r*.11,z-r*.22,h+r*.39)
        for i,p in enumerate(a):
            face(m,"Separate coal lumps in exposed dark tender",
               ("Tender coal matte","Tender coal reflection","Bunker bare coal black")[(j+i)%3],
               (p,a[(i+1)%5],top))

WHEELSETS=(("Bogie",BOGIE,.026,.045),("Driver",DRIVERS,DR,.027),("Tender",TENDER,.024,.048))
START=.59
FRAMES=64

def permanent():
    m=mesh();underframe(m);hardware(m);cab_tender(m)
    return m

def whole():
    m=permanent()
    for n,ax,rad,half in WHEELSETS:axles(m,n,ax,rad,half,START)
    motion(m,START)
    return m

def write_atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    p=R.TEXTURES/(NAME+".png")
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
                  +chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b""))

def geometry(scene,name,m,mats):
    c=bpy.data.collections.new(name)
    scene.collection.children.link(c)
    R.to_blender(m,c,mats)
    return c

def linear(curves):
    for f in curves:
        for p in f.keyframe_points:p.interpolation="LINEAR"

def rig(scene,mats):
    scene.frame_start=1
    scene.frame_end=FRAMES+1
    geometry(scene,"Frame, short tender, boiler and cab (one native body)",permanent(),mats)
    gear=bpy.data.collections.new("Eight independent editable wheelset joints")
    scene.collection.children.link(gear)
    for n,ax,rad,half in WHEELSETS:
        for i,z in enumerate(ax,1):
            m=mesh();axles(m,n,(z,),rad,half,START)
            c=bpy.data.collections.new(f"{n} wheelset {i} and separate wheel pieces")
            gear.children.link(c)
            R.to_blender(m,c,mats)
            ob=bpy.data.objects.new(f"{n} axle {i} · native X rotation",None)
            ob.empty_display_type="CIRCLE"
            ob.empty_display_size=.036+rad*.32
            gear.objects.link(ob)
            ob.location=(0,z,rad)
            for p in c.objects:
                # Mesh author coordinates are world at base pose.
                p.parent=ob;p.location=(0,-z,-rad)
            for k,t in ((1,0),(FRAMES+1,tau*DR/rad)):
                ob.rotation_euler.x=t
                ob.keyframe_insert(data_path="rotation_euler",index=0,frame=k)
            linear(ob.animation_data.action.fcurves)
    mm=mesh();motion(mm,START)
    G=geometry(scene,"Valve gear, moving quartered crankpins and conrods",mm,mats)
    samples=[]
    for i in range(1,16):
        m=mesh();motion(m,START+tau*i/16)
        samples.append(m)
    for o in G.objects:
        name=o.name
        if name not in mm.parts:raise RuntimeError((name,mm.parts.keys()))
        if all(sample.vertices[name]==mm.vertices[name] for sample in samples):
            continue
        o.shape_key_add(name="Base rolling pose")
        for i,sample in enumerate(samples,1):
            key=o.shape_key_add(name=f"Quartered gear turn step {i:02}")
            ps=sample.vertices[name]
            assert len(key.data)==len(ps),(name,len(key.data),len(ps))
            for v,p in zip(key.data,ps):v.co=p
            for frame,value in ((1+4*(i-1),0),(1+4*i,1),(1+4*(i+1),0)):
                key.value=value
                key.keyframe_insert(data_path="value",frame=frame)
        linear(o.data.shape_keys.animation_data.action.fcurves)
    scene.frame_set(1)

def render(scene,collection,path):
    for x,z,turn in ((-.51,.12,0),(.52,-.15,pi)):
        ob=R.instance(scene,collection,x,z)
        ob.rotation_euler.z=turn
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.011))
    stage=bpy.data.materials.new("Warm marshalling ballast")
    stage.diffuse_color=(.174,.165,.136,1)
    bpy.context.object.data.materials.append(stage)
    bpy.ops.object.camera_add(location=(2.50,-4.45,2.62))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,-.04,.31))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=2.37;scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1550,1070
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.23
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("High gray blue morning sky")
    scene.world.color=(.156,.195,.240)
    scene.view_settings.view_transform="Standard"
    scene.render.filepath=path
    bpy.ops.render.render(write_still=True)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    m=whole()
    mats=R.materials()
    for c,i in P.items():
        a=mats[i];a.name=c
        node=a.node_tree.nodes.get("Principled BSDF")
        node.inputs["Metallic"].default_value=.36 if any(n in c for n in ("tread","nickel","Gunmetal","rail","brass")) else .08
        node.inputs["Roughness"].default_value=.36 if "glass" in c else .64
    scene=bpy.context.scene
    scene.name="Chaney Jubilee independent 4-6-0 motion study"
    scene["Stock source contract"]="Engine #8 (1934 temperate); OpenTTD 14.1 single stock vehicle, center spacing 1 native node."
    scene["Native y datum"]="Rail crown Y=0 in mesh, +.614 over ordinary ground tile base. Native nose local -Z."
    scene["Artist editable rig"]="Frame 1–65: wheel rotations drive linear interpolation of sixteen real rod poses. Runtime uses only baked frame 1."
    scene["Tender"]="One separately modeled shell/drawbar within the single stock visual. Not an additional simulated consist vehicle."
    scene["Gauge and coupling"]="Rail centers +/- .212, buffers recessed and central coupler ends +/- .499."
    rig(scene,mats)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,-.035,.32)
                v.region_3d.view_distance=2.00
                v.region_3d.view_rotation=(Vector((0,-.056,.29))-Vector((1.20,-2.10,1.30))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/chaney_jubilee.blend"),compress=True)
    d=R.MODELS/(NAME+".obj")
    R.export_obj(d,W.local_obj(m))
    raw=d.read_text()
    d.write_text(raw.replace(raw.splitlines()[0],
        "# Unique authored Chaney Jubilee 4-6-0 and fixed tender, see tools/build_chaney_jubilee_art.py",1))
    write_atlas()
    if path:=os.getenv("JUBILEE_ART_RENDER"):
        # Review uses exactly same baked geometry as exported, not a frame
        # from the independent source rig.
        for c in list(scene.collection.children):scene.collection.children.unlink(c)
        ref=R.stash(m,mats,"Rendered presentation QA")
        render(scene,ref,path)

if __name__=="__main__":main()
