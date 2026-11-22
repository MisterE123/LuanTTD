#!/usr/bin/env python3
"""Original standard-gauge Cedar coal loader and Riverbend receiving platform."""
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import sys
import struct
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as r
TRACK={f"Rail {i}":color for i,color in enumerate(r.COLORS)}
import build_rail_wagon_art as w

bpy=w.bpy
Vector=w.Vector
PREFIX="bl_rail_coal_stage"
PAL=TRACK | {
    "Dressed limestone":"aaa491","Stone foundation":"7d7c72","Stone dark":"6a6c63","Dock concrete":"999a8d",
    "Oiled deck":"85897f","Concrete edge":"b0ad95","Paving seams":"707471","Pedestrian trim":"cab37e",
    "Mine teal":"486663","Mine frame":"36504f","Mine enamel":"537975","Steel bright":"8b9890",
    "Dark iron":"445351","Thin iron":"62716a","Pin bright":"aeb0a0","Oxide":"8f6954",
    "Coal ash":"4d504b","Coal fresh":"303536","Coal clinkers":"373d3d","Coal shadow":"292d2d",
    "Coal gleam":"5e6258","Drive rubber":"363d39","Crown gravel":"757260","Rubble warm":"8b806c",
    "Metal rust":"a26b4d","Signal ochre":"d6af60","Hazard cream":"d5c189","Electric housing":"778374",
    "Plant brick":"995e4a","Brick shade":"784e42","Brick sun":"ab7156","Brick mortar":"8a7e6a",
    "Slate flash":"81918b","Slate panel":"556963","Slate shadow":"455750","Slate highlight":"6f7c70",
    "Cable black":"343c3a","Window dark":"354847","Window pale":"8ca8a2","Verdigris":"58746c",
    "Letters carbon":"41483f","Enamel cream":"ded0ab",
}
P={k:i for i,k in enumerate(PAL)}
w.P=P
r.COLORS[:]=PAL.values()
B=w.slab
T=w.circular
R=w.faces_xz

def face(m,g,color,points):
    m.face(g,P[color],points)

def q(x,z,wid,length,c=0):
    return w.rect(x,z,wid,length,c)

def clip(value):
    return lambda x,z:value

def pipe(m,g,c,a,b,rad=.01,segments=10):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,0,1) if abs(d.z)<.87 else (1,0,0))).normalized()
    v=d.cross(u)
    def ring(p):
        return [tuple(p+rad*(u*cos(tau*i/segments)+v*sin(tau*i/segments))) for i in range(segments)]
    lo,hi=ring(a),ring(b)
    face(m,g,c,lo[::-1]);face(m,g,c,hi)
    for i in range(segments):
        j=(i+1)%segments
        face(m,g,c,(lo[i],lo[j],hi[j],hi[i]))

def bar(m,g,c,a,b,width,depth):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    t=d.cross(Vector((0,0,1) if abs(d.z)<.87 else (0,1,0))).normalized()*width/2
    v=d.cross(t).normalized()*depth/2
    cross=(t+v,-t+v,-t-v,t-v)
    lo=[tuple(a+p) for p in cross]
    hi=[tuple(b+p) for p in cross]
    face(m,g,c,lo[::-1]);face(m,g,c,hi)
    for i in range(4):
        j=(i+1)%4
        face(m,g,c,(lo[i],lo[j],hi[j],hi[i]))

def sheet(m,g,c,x,z,wid,length,h):
    face(m,g,c,[(u,v,h(u,v) if callable(h) else h) for u,v in q(x,z,wid,length)])

def open_box(m,g,c,x0,x1,z0,z1,bottom,top,thick=.031):
    # Side sections are split so the opening is physically hollow.
    for a,b in ((x0,x0+thick),(x1-thick,x1)):
        B(m,g,c,(a+b)/2,(z1+z0)/2,b-a,z1-z0,bottom,top,.002,"Dressed limestone")
    for a,b in ((z0,z0+thick),(z1-thick,z1)):
        B(m,g,c,(x0+x1)/2,(a+b)/2,x1-x0-2*thick,b-a,bottom,top,.002,"Dressed limestone")

def bolts(m,x,z,h,axis="x",scale=.008):
    T(m,"Forged hex anchor bolt heads","Pin bright",(x,z,h),scale,axis,-.005,.005,6)

def relief_coal(m,g,x,z,rx,rz,h,seed,n=46):
    rng=Random(seed)
    colors=("Coal fresh","Coal clinkers","Coal fresh","Coal ash","Coal shadow","Coal gleam")
    for i in range(n):
        a=rng.uniform(0,tau); f=rng.uniform(0,.96)
        u,v=x+rx*f*cos(a),z+rz*f*sin(a)
        up=h-rng.uniform(.015,.028)*f
        rad=rng.uniform(.007,.031)
        ring=[(u+rad*rng.uniform(.6,1.1)*cos(tau*j/5),v+rad*sin(tau*j/5),up-rng.uniform(.003,.020)) for j in range(5)]
        roof=(u+rng.uniform(-.008,.008),v+rng.uniform(-.007,.007),up+rng.uniform(.010,.035))
        for j in range(5):
            face(m,g,rng.choice(colors),(ring[j],ring[(j+1)%5],roof))

def signage(m,g,x,z,h,text,width=.235,direction=-1):
    # Slate-on-enamel raised strokes on a real plate in the -Z plane.
    glyph={
        "L":("10","10","11"),"O":("111","101","111"),"A":("010","111","101"),
        "D":("110","101","110"),"U":("101","101","111"),"N":("1101","1011","1001"),
        "T":("111","010","010"),"I":("111","010","111"),"P":("111","111","100"),
    }
    B(m,g,"Mine frame",x,z,width,.024,h-.010,h+.072,.007)
    B(m,g,"Enamel cream",x,z+direction*.013,width-.019,.010,h,h+.060,.005)
    k=.0115
    w=sum(len(glyph[c][0])+1 for c in text)-1
    u=x-w*k/2
    for character in text:
        pattern=glyph[character]
        for row,seq in enumerate(pattern):
            for i,v in enumerate(seq):
                if v=="1":
                    a=x-direction*(u+(i+.5)*k-x)
                    y=h+.014+(2-row)*k
                    zz=z+direction*.019
                    stroke=((a-.48*k,zz,y),(a+.48*k,zz,y),
                            (a+.48*k,zz,y+.95*k),(a-.48*k,zz,y+.95*k))
                    face(m,g+" legible glyphs","Letters carbon",stroke if direction<0 else stroke[::-1])
        u+=(len(pattern[0])+1)*k

def platform(m,kind,geos):
    # One outer wall per layer, including the side walls of the receiving
    # hole. The old three touching boxes continued their hidden faces into
    # the facing walls, and the darker base and coping traded depth at .963.
    def rect(x0,x1,z0,z1):
        return [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]

    def deck(front):
        outside=geos.union([rect(front,.963,-1,1)])
        if kind=="load":
            return outside
        hole=geos.union([rect(.493,.921,-.620,.620)])
        inset=geos.difference(outside,hole)
        geos.free(outside,hole)
        return inset

    foundation="Continuous dressed service platform foundation"
    coping="Continuous nonfouling ashlar coping"
    base,walk=deck(.365),deck(.358)
    m.side(base,foundation,P["Stone foundation"],.002,.206,geos)
    m.side(walk,coping,P["Dressed limestone"],.206,.282,geos)
    ledge=rect(.358,.365,-1,1)
    face(m,coping,"Dressed limestone",[(x,z,.206) for x,z in ledge[::-1]])

    # One .282 surface: colored joints cut the deck, never float across it.
    # At the pit, retain the inner portion of the rear access strip.
    joint_rings=([rect(.919,.926,-1,1)] if kind=="load" else
        [rect(.919,.926,-1,-.620),rect(.921,.926,-.620,.620),rect(.919,.926,.620,1)])
    for i in range(12):
        z=-.930+i*.169
        if kind=="unload" and abs(z)<.624:
            continue
        joint_rings.append(q(.696,z,.454,.008,.001))
    joints=geos.union(joint_rings)
    safety=geos.union([rect(.412,.434,-1,1)])
    blank=geos.difference(walk,joints)
    concrete=geos.difference(blank,safety)
    level=lambda x,z:.282
    m.skin(concrete,coping,P["Dock concrete"],level,geos)
    m.skin(joints,"Flush service deck contraction joints",P["Paving seams"],level,geos)
    m.skin(safety,"Platform sulfur safety line",P["Hazard cream"],level,geos)
    geos.free(base,walk,joints,safety,blank,concrete)

    # As on the ordinary passenger platform, no entire cap belongs to
    # the shared boundary. Two stages can never render against one plane.
    for z in (-.976,.976):
        cap=((.365,z,.002),(.963,z,.002),(.963,z,.206),(.365,z,.206))
        face(m,"Finished ashlar platform end caps","Stone dark",cap if z<0 else cap[::-1])
        lintel=((.358,z,.206),(.963,z,.206),(.963,z,.282),(.358,z,.282))
        face(m,"End-coping limestone highlight","Dressed limestone",lintel if z<0 else lintel[::-1])
    for z in (-.87,.875):
        x=.850
        B(m,"Protective junction bollard plinth","Stone dark",x,z,.092,.087,.280,.309,.009)
        T(m,"Removable plant bollard","Metal rust" if kind=="unload" else "Mine frame",
          (x,z,.305),.024,"h",0,.199,10)
        T(m,"Bollard reflectors","Signal ochre",(x,z,.463),.026,"h",0,.021,12)

def stairs(m,z=.62,offset=.782):
    # Rugged open-tread access. Non-overlapping risers, outboard of track.
    for side in (-1,1):
        z0=z+side*.103
        bar(m,"Raised access stair stringer","Mine frame",
            (offset-.102,z0,.286),(offset+.091,z0,.621),.035,.036)
        pipe(m,"Access stair guardrail","Thin iron",
             (offset-.118,z0,.455),(offset+.092,z0,.789),.009)
        for j in range(3):
            t=j/2
            x=offset-.103+.196*t
            h=.287+.328*t
            pipe(m,"Guardrail stanchion","Mine frame",(x,z0,h),(x,z0,h+.17),.008)
    for i in range(8):
        t=(i+.5)/8
        x=offset-.103+.194*t;h=.290+.335*t
        B(m,"Open checker-plate access treads","Steel bright",x,z,.036,.193,h,h+.013,.003)
    B(m,"Open access landing","Thin iron",offset+.073,z,.165,.226,.616,.638,.010)

def funnel(m,x,z,top,bottom,wtop,ltop,wbot,lbot):
    # A truly open four-sided taper. No flat coal-colored roof.
    a=q(x,z,wbot,lbot);b=q(x,z,wtop,ltop)
    inside0=q(x,z,wbot-.037,lbot-.037);inside1=q(x,z,wtop-.038,ltop-.040)
    for i in range(4):
        j=(i+1)%4
        for pts,mat in ((((*a[i],bottom),(*a[j],bottom),(*b[j],top),(*b[i],top)),"Mine teal"),
             (((*inside0[j],bottom+.007),(*inside0[i],bottom+.007),(*inside1[i],top-.004),(*inside1[j],top-.004)),"Coal ash"),
             (((*b[i],top),(*b[j],top),(*inside1[j],top-.004),(*inside1[i],top-.004)),"Thin iron")):
            face(m,"Open steel surge hopper plates",mat,pts)
        pipe(m,"Beaded rolled hopper oak braces","Thin iron",(*b[i],top),(*b[j],top),.018)
        pipe(m,"Beaded rolled hopper oak braces","Mine frame",(*a[i],bottom),(*b[i],top),.018)
    for sign in (-1,1):
        for j in range(6):
            px=x+(j-2.5)*wtop*.148
            bolts(m,px,z+sign*(ltop*.5+.007),top-.018,"z",.008)

def conveyor(m,start,end,width=.247):
    a,b=Vector(start),Vector(end)
    d=(b-a).normalized()
    across=Vector((-d.y,d.x,0)).normalized()
    low=[tuple(a-across*width*.5),tuple(a+across*width*.5),tuple(b+across*width*.5),tuple(b-across*width*.5)]
    face(m,"Textured open troughed belt below feed","Drive rubber",low)
    face(m,"Returning continuous belt","Coal ash",[(x,z,h-.057) for x,z,h in low[::-1]])
    for sign in (-1,1):
        off=across*sign*(width*.5+.009)
        top=Vector((0,0,.026))
        down=Vector((0,0,-.066))
        bar(m,"Stockyard inclined carrier beam","Mine frame",tuple(a+off+down),tuple(b+off+down),.039,.042)
        pipe(m,"Spillage guard rails along conveyor","Oxide",tuple(a+off+top),tuple(b+off+top),.011)
        for j in range(6):
            p=a.lerp(b,(j+.45)/6)
            pipe(m,"Real inclined conveyor roller brackets","Thin iron",tuple(p+off+down),tuple(p+off+top),.007)
            if sign==1:
                pipe(m,"Belt idler rollers","Steel bright",tuple(p+off),tuple(p-off),.014)
        for p in (a,b):
            pipe(m,"Conveyor head and tail drum","Drive rubber",tuple(p+off),tuple(p-off),.037)
    for j in range(8):
        p=a.lerp(b,(j+.56)/9)
        for off in (-width*.22,width*.10):
            x,z,h=p+across*off+Vector((0,0,.016))
            relief_coal(m,"Visible coal riding feed conveyor",x,z,.016,.012,h,472+int(j*13+off*71),3)

def loader(m,geos):
    platform(m,"load",geos)
    # Open supports, no box volume spanning the running way.
    for x in (-.473,.492):
        datum=.003 if x<0 else .282
        for z in (-.397,.397):
            B(m,"Gantry granite spread foot","Stone dark",x,z,.221,.173,datum,datum+.118,.017,"Dock concrete")
            B(m,"Cast steel hold-down flange","Dark iron",x,z,.170,.141,datum+.114,datum+.141,.009)
            B(m,"Riveted lattice hopper tower columns","Mine frame",x,z,.060,.075,datum+.136,1.228,.005)
            for side in (-1,1):
                B(m,"Column I-iron cap and edge","Mine teal",x+side*.034,z,.017,.088,datum+.140,1.228,.002)
            for h in (datum+.151,.653,1.168):
                for qz in (-.021,.022):
                    bolts(m,x+(.048 if x>0 else -.048),z+qz,h+.022)
        for sign in (-1,1):
            bar(m,"Gantry turned truss bracing","Thin iron",(x+sign*.036,-.380,datum+.162),
                (x+sign*.036,.379,1.094),.033,.027)
            bar(m,"Gantry turned truss bracing","Mine frame",(x-sign*.038,-.378,1.094),
                (x-sign*.038,.380,datum+.160),.029,.021)
        B(m,"Longitudinal channel under surge bin","Mine frame",x,0,.103,.906,1.087,1.195,.007,"Mine teal")
    for z in (-.398,.398):
        B(m,"Over-track lattice carrying girder","Mine teal",0,z,1.074,.111,1.076,1.233,.007)
        for h in (1.08,1.200):
            B(m,"Main lifted box-girder welded flange","Dark iron",0,z,1.130,.143,h,h+.025,.004)
    funnel(m,0,0,1.636,1.207,.875,.697,.321,.301)
    for i in range(5):
        z=(i-2)*.057
        pipe(m,"Rotating grate visible in feed gate","Dark iron",(-.141,z,1.228),(.141,z,1.228),.015)
    relief_coal(m,"Raw coal visible in open surge hopper",.015,-.019,.340,.253,1.528,719,62)
    # A real dangling telescoping loading spout. It ends well above the tallest engine.
    for x in (-.163,.163):
        B(m,"Coal slide chute outer side walls","Oxide",x,0,.030,.271,1.030,1.210,.005)
    for z in (-.131,.131):
        B(m,"Coal slide chute outer end walls","Oxide",0,z,.288,.031,1.042,1.211,.004)
    for j in range(4):
        h=1.043+j*.040
        open_box(m,"Clear flanged loading telescoping collar","Dark iron",-.191,.191,-.158,.158,h,h+.017,.031)
    pipe(m,"Actuator and linkage for loading gate","Oxide",(.173,-.17,1.074),(.238,-.281,1.239),.020)
    pipe(m,"Actuator piston rod","Pin bright",(.237,-.281,1.239),(.283,-.355,1.341),.011)
    conveyor(m,(.952,0,.663),(.284,0,1.711))
    stairs(m)
    for sign in (-1,1):
        signage(m,"Cedar Coal loading gantry enamel board",0,sign*.469,1.145,"LOAD",direction=sign)
    for x in (-.339,.338):
        B(m,"Cast cast-iron gantry lamp arm","Dark iron",x,-.458,.034,.075,1.025,1.075,.005)
        T(m,"Warm lens below gantry","Signal ochre",(x,-.476,1.030),.024,"h",-.014,-.003,12)


def shed_roof(m):
    # Broad industrial canopy kept visually open at both rail portals.
    # Real standing seams break up the slate-colored roof in a survey view.
    for s in (-1,1):
        a,b=sorted((.148,.148+s*.811))
        h=lambda u,v:1.494-abs(.148-u)*.252
        for row in range(10):
            z0=-.580+row*.116;z1=z0+.1152
            y=lambda u,v:h(u,v)-.043
            profile=q((a+b)/2,(z0+z1)/2,b-a,z1-z0)
            underside=[(x,z,y(x,z)) for x,z in profile]
            top=[(x,z,h(x,z)) for x,z in profile]
            face(m,"Sheltering pitched standing-seam roof",PICK_ROOF[(row+s)%4],top)
            face(m,"Interior high-clearance roof lining","Slate shadow",underside[::-1])
            for i in range(4):
                j=(i+1)%4
                face(m,"Visible folded roof edges","Slate shadow",(underside[i],underside[j],top[j],top[i]))
            bar(m,"Raised standing seam roof ribs","Slate flash",(a,z0,h(a,z0)),(b,z0,h(b,z0)),.014,.012)
        for z in (-.590,.592):
            bar(m,"Gabled end gusset eaves","Slate flash",(a,z,h(a,z)-.034),(b,z,h(b,z)-.034),.040,.023)
        u=.148+s*.813
        pipe(m,"Cast rain gutter","Dark iron",(u,-.591,1.286),(u,.591,1.286),.021)
    pipe(m,"Rolled central ridge cap","Slate flash",(.148,-.591,1.495),(.148,.591,1.495),.023)

PICK_ROOF=("Slate panel","Slate highlight","Slate panel","Slate shadow")


def arc_cradle(m,z):
    # Low semicircular rotary-frame sector. The running tunnel is truly
    # hollow and all structural hardware is outside the clearance prism.
    center=.694
    lo,hi=.522,.579
    count=26
    for i in range(count):
        a,b=-.24+i*(pi+.48)/count,-.24+(i+1)*(pi+.48)/count
        def pt(radius,angle,depth):
            return (radius*cos(angle),depth,center+radius*sin(angle))
        ring=[pt(l,k,v) for l,k,v in (
            (lo,a,z-.031),(lo,b,z-.031),(hi,b,z-.031),(hi,a,z-.031),
            (lo,a,z+.031),(lo,b,z+.031),(hi,b,z+.031),(hi,a,z+.031))]
        for sides,c in (((0,1,2,3),"Oxide" if i%6 else "Metal rust"),((4,7,6,5),"Dark iron"),
                        ((0,4,5,1),"Thin iron"),((2,6,7,3),"Mine frame")):
            face(m,"Rotary unloading cradle semicircular channels",c,[ring[j] for j in sides])
        if i%2==1:
            x=cos(a)*.55; h=center+sin(a)*.55
            bolts(m,x,z-.034,h,"z",.009)
        if i%3==1:
            x,zp,h=pt(.581,a,z)
            pipe(m,"Dumper ring rack teeth","Thin iron",(x,zp-.038,h),(x,zp+.039,h),.009)
    for x in (-.545,.545):
        B(m,"Cast-iron rocker pedestal","Dark iron",x,z,.149,.127,.265,.574,.012)
        T(m,"Rotary tipper bearing shaft","Oxide",(x,z,.545),.059,"z",-.082,.082,18)
        T(m,"Rotary bearing service nut","Pin bright",(x,z-.087,.545),.028,"z",-.009,.009,8)


def unload(m,geos):
    platform(m,"unload",geos)
    for x in (-.608,.876):
        for z in (-.532,.535):
            datum=.005 if x<0 else .282
            B(m,"Brick pier ashlar footing","Stone foundation",x,z,.164,.187,datum,datum+.092,.012,"Dressed limestone")
            B(m,"Brick shed buttresses","Plant brick",x,z,.120,.133,datum+.088,1.196,.008)
            for i in range(int((1.192-datum)/.082)):
                h=datum+.112+i*.077
                B(m,"Mortared coal shed brick ledges","Brick mortar",x,z,.122,.135,h,h+.008,.008)
                if i%2==0:
                    B(m,"Varied individual header brick","Brick sun",x,z-.070,.064,.007,h+.019,h+.051,.003)
            B(m,"Exposed wall plate","Slate flash",x,z,.169,.164,1.195,1.226,.010)
        bar(m,"Continuous end wall canopy beam","Thin iron",(x,-.561,1.259),(x,.561,1.259),.052,.068)
        for z in (-.393,.395):
            bar(m,"Short iron staircase gusset","Dark iron",(x,z-.066,1.158),(x,z+.083,1.267),.033,.046)
    for z in (-.519,.519):
        B(m,"Transverse portal steel lintel","Dark iron",.116,z,1.515,.069,1.242,1.306,.007)
    shed_roof(m)
    # Outboard open receiving pit built into the raised ordinary platform
    # height, so its shadows and grizzly bars actually have depth.
    open_box(m,"Open paired dump sump masonry","Stone dark",.499,.919,-.612,.612,.019,.291,.049)
    B(m,"Cinder-black sump foundation floor","Coal shadow",.708,0,.310,1.100,.018,.034,.007)
    relief_coal(m,"Loose fuel below open receiving grate",.717,.007,.126,.490,.075,449,91)
    for i in range(10):
        z=-.511+i*.114
        B(m,"Open heavy grizzly bar with gaps","Thin iron",.706,z,.322,.028,.260,.286,.002)
    for x in (.550,.865):
        B(m,"Squared grizzly bearing edge","Dark iron",x,0,.024,1.137,.247,.289,.003)
    for z in (-.376,.381):
        arc_cradle(m,z)
    for z in (-.385,.389):
        bar(m,"Sump steadying support timber","Oxide",(.358,z,.391),(.683,z,.295),.046,.060)
    # Side tipping deflector and controlled power transfer: not a drawn black square.
    a=[(.344,-.283,.472),(.344,.286,.472),(.645,.355,.328),(.645,-.356,.328)]
    face(m,"Sloped formed steel wagon tipping throat","Oxide",a)
    face(m,"Tipping throat rolled steel underside","Dark iron",[(x,z,h-.022) for x,z,h in a[::-1]])
    for x,y,wid in ((.345,.476,.566),(.643,.338,.709)):
        B(m,"Rolled tipping throat edge","Thin iron",x,0,.029,wid,y-.024,y+.003,.006)
    for z in (-.283,.284):
        bar(m,"Wagon receiving first deflectors","Mine frame",(.348,z,.521),(.679,z,.353),.032,.043)
    # Shed drive cabinet, opening heavy lever and relay lamp at operator height.
    B(m,"Open wall power receiver masonry plinth","Stone foundation",-.642,.092,.255,.310,.004,.174,.012)
    B(m,"Plant rotary gear motor block","Dark iron",-.635,.084,.222,.264,.174,.391,.018)
    T(m,"Motor cooling ducts and fan cover","Electric housing",(-.638,-.050,.282),.103,"z",-.028,.024,16)
    T(m,"Gear reduction shaft flanged joint","Thin iron",(-.612,.229,.280),.081,"z",-.025,.043,16)
    for x in (-.691,-.653,-.616,-.579):
        B(m,"Electric motor ventilator slots","Cable black",x,-.080,.012,.012,.215,.337,.003)
    pipe(m,"Greased moving cradle coupling shaft","Pin bright",
         (-.606,.265,.295),(-.554,.371,.545),.015)
    B(m,"Riverbend power relay cabinet","Electric housing",.856,.733,.160,.215,.283,.537,.015)
    B(m,"Relay gasketed control panel","Dark iron",.850,.621,.128,.015,.339,.491,.011)
    T(m,"Receiving operator reading lamp","Signal ochre",(.849,.609,.451),.024,"z",-.008,.008,12)
    bolts(m,.867,.607,.372,"z",.009)
    for h in (.338,.474):
        pipe(m,"Safety guard behind open coal pit","Oxide",(.942,-.565,h),(.942,.625,h),.013)
    for z in (-.559,.022,.619):
        pipe(m,"Protective guardrail uprights","Thin iron",
             (.942,z,.285),(.942,z,.501),.013)
    for z in (-.552,.537):
        pipe(m,"Grounded shed rain pipe","Oxide",(-.650,z,1.274),(-.650,z,.069),.018)
    for sign in (-1,1):
        signage(m,"Riverbend unloading shed enamel board",.102,sign*.580,1.273,"TIP",direction=sign)
    for x in (-.352,.427):
        B(m,"Double porcelain fixture concrete former","Slate shadow",x,-.396,.063,.095,1.272,1.303,.010)
        T(m,"Interior high yard lamps","Signal ochre",(x,-.412,1.264),.027,"h",0,.015,12)


def track_and_stage(kind,geos):
    m=r.rail_geometry(2,0,geos)
    if kind=="unload":
        # Pebbles and normal track remain, while the art surrounds it.
        unload(m,geos)
    else:
        loader(m,geos)
    return m


def orient(m,axis,much):
    out=r.Mesh(r.terrain_height(0))
    for group,data in m.parts.items():
        for inds,c in data:
            points=[]
            legible=group.endswith("legible glyphs")
            for i in (inds[::-1] if much and not legible else inds):
                x,z,h=m.vertices[group][i]
                if much:
                    if not legible:x=-x
                    elif group.startswith("Riverbend"):x-=.204
                if axis==0:x,z=-z,x
                points.append((x,z,h))
            out.face(group,c,points)
    return out


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    content=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(PAL),8,8,2,0,0,0))
    content+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (r.TEXTURES/(PREFIX+"_atlas.png")).write_bytes(content)


def render_setup(scene,parts):
    for kind,a in (("load",-1.35),("unload",1.35)):
        r.instance(scene,parts[kind,1,False],a,0)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.007))
    floor=bpy.data.materials.new("Muted temperate industrial surroundings")
    floor.diffuse_color=(.18,.238,.19,1)
    bpy.context.object.data.materials.append(floor)
    bpy.ops.object.camera_add(location=(2.0,-5.8,4.1))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((.07,0,.70))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=6.0;scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1580;scene.render.resolution_y=1080
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.35
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Cloudy quarry light")
    scene.world.color=(.15,.18,.23)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    g=r.Geos()
    mats=r.materials()
    for i,m in enumerate(mats):m.name=list(PAL)[i]
    parts={}
    for kind in ("load","unload"):
        seed=track_and_stage(kind,g)
        for a in (0,1):
            for mirror in (False,True):
                suffix=f"{kind}_{a}"+("_mirror" if mirror else "")
                variant=orient(seed,a,mirror)
                parts[kind,a,mirror]=r.stash(variant,mats,suffix)
                r.export_obj(r.MODELS/(PREFIX+"_"+suffix+".obj"),variant)
    atlas()
    scene=bpy.context.scene
    scene.name="LuanTTD | Cedar loading screen and Riverbend covered tipper"
    render_setup(scene,parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(r.ROOT/"art"/"rail_coal_stages.blend"),compress=True)
    if result:=os.getenv("RAIL_COAL_STAGE_RENDER"):
        scene.render.filepath=result
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()
