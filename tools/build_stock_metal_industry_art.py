#!/usr/bin/env python3
"""Original native art for two pinned RC1 Temperate industries, layout zero.

STOCK_METAL_RENDER_DIR=/tmp blender -b -t 2 --python-exit-code 1 \
  --python tools/build_stock_metal_industry_art.py
Set STOCK_METAL_SITE=iron_mine or steel_mill to rebuild only one site.
Coordinates are Luanti site X, Z, height. Source nodes use the NW tile anchor.
"""
from math import atan2, cos, hypot, pi, sin, sqrt
from pathlib import Path
from random import Random
import os
import sys
import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

R,A=S.R,S.A
B,T,F,Q=S.B,S.T,S.F,S.Q
ROOT=Path(__file__).resolve().parents[1]
PAL=dict(S.PAL, **{
    "aggregate":"82786a","ashphalt":"686564","dryyard":"a39580","rustyard":"8d6b51",
    "hematite":"854d3d","hematite_sun":"a06649","hematite_dark":"684037",
    "clay_cut":"ab7f61","shale":"6e675d","limonite":"ba8953","granite":"9f968c",
    "millbrick":"93604f","millbrick_dark":"754a3b","workstone":"a39a87",
    "nickel":"adb6ad","oxidized_steel":"674533","darkiron":"4a4d4b","metal_blue":"526d7e",
    "roof_zinc":"748383","roof_rib":"536269","coke":"49423e","coke_sun":"5c5650",
    "steel_plate":"75858b","yellow_safety":"d0ab53","hot":"d98851","slag":"6d574e",
})
A.PAL=PAL
A.P=A.H.P={name:i for i,name in enumerate(PAL)}
R.COLORS[:]=PAL.values()
SOURCE_SHA="07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
IRON={(x,z):100+4*x+z for x in range(4) for z in range(4)}
STEEL={(2,1):52,(2,2):53,(3,1):54,(3,2):55,(0,0):56,(1,0):57,
       (0,1):56,(1,1):57,(0,2):56,(1,2):57,(2,0):56,(3,0):57}


def beam(m,name,c,a,b,w=.032):
    T(m,name,c,a,b,w,w,4)


def ground(m,layout,kind):
    for (x,z),gfx in layout.items():
        a,b=2*x-.5,2*z-.5
        group=f"GFX{gfx} graded working surface"
        c=kind
        if kind=="rustyard":
            c="rustyard" if (x*3+z)%4 else "dryyard"
        Q(m,group,c,a,a+2,b,b+2,.003)
        rng=Random(145+x*45+z)
        for j in range(18):
            px,pz=a+.06+rng.random()*1.86,b+.07+rng.random()*1.83
            Q(m,group+" weathered material flecks",rng.choice((c,"aggregate","coke","dryyard","workstone")),
              px,px+rng.uniform(.012,.056),pz,pz+rng.uniform(.015,.040),.006)


def strata(m,name,cx,cz,rx,rz,h,colors,seed,layers=9):
    """Closed irregular granular ore ridge/bench, one continuous crossed-tile form."""
    rng=Random(seed)
    turns=25
    profile=[1-(j/layers)**.72*.91 for j in range(layers)]
    noise=[rng.uniform(.83,1.11) for i in range(turns)]
    rings=[]
    for j in range(layers):
        p=profile[j]
        ring=[]
        for i in range(turns):
            angle=i*2*pi/turns
            shift=(1-p)*.109
            y=.018+h*(j/layers)**.93
            if j>0:
                y+=rng.uniform(-h*.045,h*.045)
            length=noise[i]*p*rng.uniform(.973,1.028)
            ring.append((cx+shift+cos(angle)*rx*length,cz+sin(angle)*rz*length,y))
        rings.append(ring)
    for j,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(turns):
            k=(i+1)%turns
            col=rng.choice(colors[max(0,(j//2)%4-2):] or colors)
            if j%3==1 and i%6 not in (0,1):
                col=colors[0]
            F(m,name+" variegated terraced strata",col,(a[i],a[k],b[k]))
            F(m,name+" broken strata facet",rng.choice((col,col,"shale")),(a[i],b[k],b[i]))
    for i in range(turns):
        k=(i+1)%turns
        F(m,name+" weathered apex",colors[(i//4)%len(colors)],(rings[-1][i],rings[-1][k],(cx+.10,cz,h+.017)))
        F(m,name+" sealed stockpile underside","rustyard",((cx,cz,.018),rings[0][k],rings[0][i]))


def ore_bin(m,name,x,z,w,d,low,high,col="oxidized_steel"):
    # Four sloping sheet panels converging on a cast outlet, not a box painted like a chute.
    tw,td=w*.5,d*.5
    low_w,low_d=w*.191,d*.20
    bottom=[(x+u*low_w,z+v*low_d,low) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))]
    top=[(x+u*tw,z+v*td,high) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))]
    for i in range(4):
        j=(i+1)%4
        F(m,name+" tapered riveted steel side",col,(bottom[i],bottom[j],top[j],top[i]))
        F(m,name+" internal wearing liner","darkiron",(top[i],top[j],bottom[j],bottom[i]))
        beam(m,name+" forged hopper lip","steel_plate",top[i],top[j],.022)
        beam(m,name+" articulated corner seam","oxidized_steel",bottom[i],top[i],.017)
    B(m,name+" hanging segmented gate","darkiron",x,z,low_w*2+.021,low_d*2+.016,low-.11,low+.008,.014)
    for side in (-1,1):
        for dz in (-.31,.31):
            B(m,name+" trestle plate footing","foundation",x+side*tw*.85,z+dz*d,.148,.126,.02,.103,.013)
            B(m,name+" outer channel support","metal_blue",x+side*tw*.85,z+dz*d,.073,.073,.095,high-.054,.007)
    for side in (-1,1):
        beam(m,name+" diagonal load brace","metal_blue",(x+side*tw*.85,z-.32*d,.16),(x+side*tw*.85,z+.32*d,high-.13),.022)
    B(m,name+" exposed rack gear enclosure","yellow_safety",x+low_w+.051,z, .112,.123,low-.139,low+.057,.013)


def track(m,name,points,rail=.195):
    """Embedded non-drivable site rail. Positive vertical offset avoids grade z-fighting."""
    A.line(m,name+" coarser ballast bed","aggregate",points,rail*2+.245,.025)
    for (x,z),(u,v) in zip(points,points[1:]):
        d=hypot(u-x,v-z)
        dx,dz=(v-z)/d,(x-u)/d
        for s in (-1,1):
            t=rail*s
            beam(m,name+" warm web of display track","oxidized_steel",(x+t*dx,z+t*dz,.068),(u+t*dx,v+t*dz,.068),.018)
            beam(m,name+" burnished running surface","nickel",(x+t*dx,z+t*dz,.083),(u+t*dx,v+t*dz,.083),.012)
        n=int(d/.158)
        for j in range(n):
            t=(j+.52)/max(1,n)
            sx,sz=x+t*(u-x),z+t*(v-z)
            beam(m,name+" short creosoted crosstie","wood",
                 (sx+dx*(rail+.071),sz+dz*(rail+.071),.041),(sx-dx*(rail+.071),sz-dz*(rail+.071),.041),.025)
    for x,z in (points[0],points[-1]):
        B(m,name+" compact buffer stop","yellow_safety",x,z,.56,.114,.075,.161,.008)


def conveyor(m,name,a,b,w=.39):
    axis=Vector(b)-Vector(a)
    length=hypot(axis.x,axis.y)
    p=(axis.y/length,-axis.x/length)
    def pos(t,r,h):
        return a[0]+t*axis.x+p[0]*r,a[1]+t*axis.y+p[1]*r,a[2]+t*axis.z+h
    F(m,name+" rubber belt carrying crushed ore","coke",(pos(0,-w*.43,0),pos(1,-w*.43,0),pos(1,w*.43,0),pos(0,w*.43,0)))
    for q in (-1,1):
        for h in (-.115,.025):
            beam(m,name+" rolled straight galvanized stringer","metal_blue",pos(0,q*w*.51,h),pos(1,q*w*.51,h),.028)
        N=max(5,round(length/.37))
        for i in range(N):
            beam(m,name+" diagonal triangular belt truss","metal_blue",
                 pos(i/N,q*w*.51,-.12),pos((i+1)/N,q*w*.51,.016),.016)
        for t in (.19,.57,.84):
            x,z,h=pos(t,q*w*.54,-.123)
            if h>.17:
                B(m,name+" isolated square pier","foundation",x,z,.14,.14,.013,.09,.021)
                beam(m,name+" braced conveyor column","oxidized_steel",(x,z,.087),(x,z,h),.032)
    for i in range(max(5,round(length/.125))):
        t=(i+.5)/max(5,round(length/.125))
        beam(m,name+" distinct idler station supporting belt","darkiron",pos(t,-w*.51,-.023),pos(t,w*.51,-.023),.012)


def ladder(m,n,x,z,low,high):
    for s in (-1,1):
        T(m,n+" fixed ladder upright","darkiron",(x+s*.068,z,low),(x+s*.068,z,high+.06),.011,.011,6)
    for i in range(1,max(3,round((high-low)/.12))):
        hi=low+i*.111
        if hi>=high:break
        T(m,n+" even polished step","nickel",(x-.072,z,hi),(x+.072,z,hi),.010,.010,7)


def shed(m,n,x,z,w,d,eave,ridge,roof="slate",north_south=True,open_south=False):
    B(m,n+" set-back chamfered footing","foundation",x,z,w+.12,d+.11,.005,.090,.019)
    B(m,n+" darkened brick rear elevation","millbrick_dark",x,z-d*.50,w,.085,.078,eave)
    for side in (-1,1):
        X=x+side*w*.50
        B(m,n+" side brick elevation","millbrick",X,z,.087,d,.078,eave)
        for i in range(max(2,round(d/.35))):
            Z=z-d*.434+i*min(.37,d*.86/max(1,round(d/.35)-1))
            B(m,n+" tall masonry buttress","millbrick_dark",X,Z,.121,.080,.085,eave,.004)
            if i%2:
                B(m,n+" glazed side steel-framed light","dark_slate",X+side*.047,Z+.107,.014,.143,eave*.48,eave*.74,.004)
                B(m,n+" faint upper window reflection","glass_dark",X+side*.052,Z+.106,.013,.110,eave*.59,eave*.72,.003)
    front=z+d/2
    if open_south:
        for s in (-1,1):
            B(m,n+" deep masonry edge to working bay","millbrick",x+s*w*.405,front,w*.19,.087,.082,eave)
    else:
        B(m,n+" warm masonry front elevation","millbrick",x,front,w,.083,.081,eave)
        A.doorway(m,n+" service staff weatherproof doors",x,front+.054,min(.34,w*.285),.106,eave*.81,"metal_blue")
        for s in (-1,1):
            xx=x+s*w*.296
            A.facade_window(m,n+" divided steel sash",xx,front+.048,min(.234,w*.192),eave*.36,eave*.77)
    for f in (-1,1):
        S.gable_panel(m,n+" high triangular brick infill",x,z+f*d*.50,w,eave,ridge-.058,
                      "millbrick" if f>0 else "millbrick_dark",f>0)
        B(m,n+" lintel real relief across broad bay","workstone",x,z+f*d*.504,w,.101,eave-.076,eave+.025,.008)
    A.gable(m,n+" standing-seam pitched roof",x,z,w+.139,d+.132,eave+.027,ridge,roof,"z")
    for s in (-1,1):
        for i in range(6):
            t=(i+.65)/6.5
            X=x+s*t*(w+.139)/2
            H=(1-t)*ridge+t*(eave+.027)
            T(m,n+" shallow raised roofing seams","roof_rib",(X,z-(d+.125)/2,H+.009),(X,z+(d+.125)/2,H+.009),.010,.010,4)
        for dz in (-.5,.5):
            T(m,n+" continuous weather flashing","nickel",(x,z+dz*(d+.137),ridge),(x+s*(w+.139)/2,z+dz*(d+.137),eave+.027),.016,.016,5)
    T(m,n+" bent ridge flashing","roof_zinc",(x,z-(d+.139)/2,ridge),(x,z+(d+.139)/2,ridge),.018,.018,6)


def mine_terrain(m):
    ground(m,IRON,"rustyard")
    # The workfloor remains at stock flat height; perched ring benches give
    # depth without overrunning the adjacent game terrain or changing grade.
    for x,z,rx,rz,h,seed in ((.48,3.15,.83,1.94,.94,666),(.55,5.95,.86,1.15,.77,556),
                           (2.04,6.67,1.28,.63,1.00,518),(3.26,6.93,.97,.43,.69,902)):
        strata(m,"Western cut bank",x,z,rx,rz,h,("shale","clay_cut","granite","limonite","hematite_dark"),seed,7)
    for x,z,rx,rz,h,seed in ((2.06,4.92,.78,.75,.47,254),(3.55,5.22,.54,.63,.37,552),
                           (5.53,6.52,.67,.66,.59,444),(6.57,6.51,.77,.62,.42,497)):
        strata(m,"Rust-red iron ore graded stockpile",x,z,rx,rz,h,
               ("hematite_dark","hematite","hematite_sun","limonite","hematite"),seed,7)
    A.line(m,"Winding truck haul road base","dryyard",[(.04,1.11),(1.34,1.03),(2.32,1.59),(2.75,3.10),(3.38,3.98),(4.28,4.10),(6.26,3.68),(7.38,3.78)],.65,.014)
    A.line(m,"Packed working center rut","aggregate",[(.04,1.11),(1.34,1.03),(2.32,1.59),(2.75,3.10),(3.38,3.98),(4.28,4.10),(6.26,3.68),(7.38,3.78)],.23,.017)


def headframe(m):
    x,z=.50,.29
    B(m,"Heavy rectangular mine collar and foot slabs","foundation",x,z,1.28,1.18,.007,.116,.041)
    Q(m,"Black actual mine shaft opening","coke",x-.321,x+.324,z-.24,z+.29,.121)
    for xx in (-.44,.44):
        for zz in (-.402,.398):
            beam(m,"Riveted lattice headframe tall upper beams","metal_blue",(x+xx,z+zz,.112),(x+xx*.59,z+zz*.66,2.28),.060)
            if zz>0:
                beam(m,"Trailing structural kicker to winch house","oxidized_steel",
                     (x+xx,z+.894,.111),(x+xx*.58,z+.27,2.01),.048)
        for zz in (-.402,.398):
            beam(m,"Raised rectangular girder horizontal fence","metal_blue",(x+xx-.014,z+zz,.77),(x-xx+.014,z+zz,.77),.039)
    for yy in (.28,.96,1.58):
        lean=.44*(1-yy*.17)
        for zz in (-.323,.349):
            beam(m,"Triangular truss headframe bracing","metal_blue",(x-lean,z+zz,yy),(x+lean*.85,z+zz,yy+.61),.024)
            beam(m,"Modular standing braced steel lattice","oxidized_steel",(x+lean,z+zz,yy),(x-lean*.85,z+zz,yy+.61),.022)
    for xx in (-.162,.162):
        h=2.14
        for i in range(24):
            a,b=i*pi/12,(i+1)*pi/12
            def wheel(t):return (x+xx,z+.20*sin(t),h+.20*cos(t))
            T(m,"Independent circular winding sheave rim","oxidized_steel",wheel(a),wheel(b),.024,.024,7)
            if i%3==0: T(m,"Seven spoked mine winding sheave","steel_plate",(x+xx,z,h),wheel(a),.013,.013,5)
        T(m,"Working vertical winding cable","darkiron",(x+xx,z+.195,h),(x+xx,z+.195,.226),.008,.008,7)
        T(m,"Deflected winding cable down to gear","darkiron",(x+xx,z-.190,h),(1.62,z-.11,.456),.008,.008,7)
    T(m,"Transverse sheave axle","nickel",(x-.29,z,2.14),(x+.29,z,2.14),.037,.037,12)
    B(m,"Open headframe maintenance service landing","yellow_safety",x,z,.83,.73,1.872,1.910,.006)
    ladder(m,"Headframe inspection access",x+.369,z+.414,.107,1.923)
    shed(m,"Brick steam winch and dispatch house",2.52,.53,1.30,1.23,.75,1.035,"roof_zinc")
    B(m,"Enamel painted mine office plaque","metal_blue",2.52,1.183,.44,.045,.833,.927,.008)
    A.lettering(m,"Raised Iron Ore dispatch sign","IRON ORE",(2.52,1.208,.888),.009,"south","bone")


def mine_process(m):
    shed(m,"Riveted ore crushing and screen house",4.59,2.63,1.59,1.41,1.13,1.638,"roof_zinc",open_south=True)
    ore_bin(m,"Elevated coarse feed bin",4.62,2.45,1.23,1.10,.50,1.377,"metal_blue")
    B(m,"Exposed crusher rotational motor case","metal_blue",4.91,3.30,.48,.31,.115,.47,.035)
    T(m,"Crushing drive visible flywheel",( "darkiron"),(4.68,3.46,.311),(4.68,3.60,.311),.169,.169,14)
    B(m,"Metal flywheel segmented safety guard","yellow_safety",4.68,3.61,.181,.026,.321,.469,.008)
    conveyor(m,"Headframe to crusher belt",(1.127,.627,.581),(4.14,2.42,1.315),.34)
    conveyor(m,"Product sized conveyor to gravity bins",(5.19,3.13,1.213),(5.01,5.75,1.591),.46)
    ore_bin(m,"Twin loading hopper battery left",4.76,5.88,.89,.81,.72,1.39,"oxidized_steel")
    ore_bin(m,"Twin loading hopper battery right",5.68,5.88,.88,.80,.72,1.37,"oxidized_steel")
    B(m,"Riveted storage bank main access girder","metal_blue",5.19,5.88,1.87,.081,1.066,1.156,.008)
    ladder(m,"Hopper roof access",4.28,6.114,.129,1.258)
    track(m,"Private industrial ore loading siding",[(7.10,5.64),(6.65,5.81),(5.02,5.89),(3.53,5.91),(2.58,5.99)],.18)
    shed(m,"Quiet flake zinc maintenance shed",6.60,.46,1.24,1.35,.58,.849,"slate")
    for x,z in ((6.34,2.42),(6.66,2.78),(6.96,3.01),(3.59,3.68)):
        T(m,"Blue lubricant drums with closed rims","metal_blue",(x,z,.05),(x,z,.291),.087,.083,12)
        for y in (.123,.231): T(m,"Pressed lip reinforcing barrel seam","nickel",(x,z,y),(x,z,y+.017),.089,.089,12)


def walkway(m,n,x,z,h,radius):
    def p(t,delta,dy=0):
        return (x+(radius+delta)*cos(t),z+(radius+delta)*sin(t),h+dy)
    count=24
    for i in range(count):
        # Individual deck planks have narrow drainage joints and independent edges.
        a,b=i*2*pi/count,(i+.963)*2*pi/count
        F(m,n+" welded annular anti-slip platform","darkiron",(p(a,-.084),p(a,.052),p(b,.052),p(b,-.084)))
        beam(m,n+" handrail with unclipped arc","yellow_safety",p(a,.052,.145),p(b,.052,.145),.012)
        if i%3==0:
            beam(m,n+" physical isolated handrail stanchion","nickel",p(a,.052),p(a,.052,.15),.012)


def pipe(m,n,col,points,r,flanges=True):
    for i,(a,b) in enumerate(zip(points,points[1:])):
        T(m,n+" thick gas pipe run",col,a,b,r,r,12)
        if i<len(points)-2:
            S.ellipse(m,n+" bent sealed pipe join",col,*b,r,r,r,8)
        if flanges:
            a,b=Vector(a),Vector(b)
            middle=a+(b-a)*.63
            v=(b-a).normalized()*.013
            T(m,n+" bolted pipe flange","darkiron",middle-v,middle+v,r*1.2,r*1.2,12)


def stack(m,n,x,z,h,r):
    T(m,n+" broad furnace firebrick footing","millbrick_dark",(x,z,.018),(x,z,.22),r*1.24,r*1.02,12)
    rings=(.21,.49,h*.55,h-.10,h)
    for j,(a,b) in enumerate(zip(rings,rings[1:])):
        R=r*(1-(a/h)*.46)
        U=r*(1-(b/h)*.46)
        T(m,n+" individually colored brick courses",("millbrick","millbrick_dark","millbrick","steel_plate")[j],
          (x,z,a),(x,z,b),R,U,16)
    for j in (.50,.73,.95):
        H=h*j;R=r*(1-j*.46)
        T(m,n+" raised rounded reinforcing collar","workstone",(x,z,H),(x,z,H+.031),R*1.09,R*1.08,16)
    T(m,n+" dark open throat hood","darkiron",(x,z,h),(x,z,h+.019),r*.402,r*.397,14)


def blast(m,n,x,z,y,scale=1):
    # Closed multi-radius stepped furnace body, visibly separate staves,
    # heating trains, tapping channel and working platform.
    profile=[(.10,.53),(.26,.48),(.68,.44),(1.16,.60),(1.82,.61),(2.20,.50),(2.56,.40),(2.74,.37)]
    for i,((a,ar),(b,br)) in enumerate(zip(profile,profile[1:])):
        T(m,n+" wrought blast furnace process shell",("millbrick_dark","oxidized_steel","darkiron","metal_blue","oxidized_steel","steel_plate","darkiron")[i],
          (x,z,y+a*scale),(x,z,y+b*scale),ar*scale,br*scale,22)
    for h,r in ((.67,.47),(1.20,.63),(1.51,.62),(1.84,.62),(2.22,.51),(2.59,.43)):
        T(m,n+" distinct horizontal ring band","nickel",(x,z,y+h*scale),(x,z,y+(h+.031)*scale),r*scale,r*scale,20)
    for k in range(16):
        t=k*pi/8
        u,v=cos(t)*scale,sin(t)*scale
        beam(m,n+" external cooling upright","darkiron",(x+.601*u,z+.601*v,y+1.26*scale),
               (x+.614*u,z+.614*v,y+1.813*scale),.010)
    for h,r in ((1.201,.674),(2.23,.55)):
        walkway(m,n+" cast service balcony",x,z,y+h*scale,r*scale)
    ladder(m,n+" high-level inspection ladder",x-.294,z+.569*scale,y+.19,y+2.26*scale)
    # Furnace base opens into a working hearth chute and safety-retaining sill.
    dx,dz=x-.047,z+.60
    B(m,n+" insulated tap lintel housing","darkiron",dx,dz,.40,.31,.13,.37,.06)
    B(m,n+" protected interior of the tapping mouth","hot",dx,dz+.161,.156,.018,.204,.291,.008)
    B(m,n+" protective refractory side of tapping channel","millbrick_dark",dx-.101,dz+.325,.062,.55,.073,.187,.012)
    B(m,n+" protective refractory side of tapping channel","millbrick_dark",dx+.103,dz+.325,.062,.55,.073,.187,.012)
    Q(m,n+" exposed hot channel floor","hot",dx-.074,dx+.073,dz+.056,dz+.551,.106)


def steel_yard(m):
    ground(m,STEEL,"ashphalt")
    for x,z,h in ((.38,.49,.36),(2.41,.49,.54),(4.41,.53,.43),(6.59,.56,.55),(.46,2.49,.44),(2.50,2.43,.51)):
        kind="Fines and screened iron ore receiving bank"
        if x>3.5 and z<1 or (x<1 and z<1):
            strata(m,kind,x,z,.60,.55,h,("hematite_dark","hematite","hematite_sun","clay_cut","limonite"),int(x*980+z*6),6)
        else:
            strata(m,"Dark coke fines and waste heap",x,z,.69,.54,h,("coke","coke_sun","shale","slag","coke"),int(x*980+z*6),6)
    for x,z in ((.46,.50),(2.42,.52),(4.43,.54),(6.59,.51),(.46,2.49),(2.52,2.43)):
        B(m,"Semi-open stockpile retaining divider","workstone",x,z-.67,1.55,.093,.012,.19,.017)
        B(m,"Side of partially contained material bay","aggregate",x+.77,z-.259,.084,.76,.013,.154,.014)
    for x,z in ((.51,4.59),(2.54,4.51)):
        for j in range(5):
            xx=x+(j%3-1)*.33
            zz=z+(j//3-.5)*.505
            for k in range(3):
                B(m,"Distinct layered finished slab ingot stacks",("steel_plate","roof_rib","darkiron")[(j+k)%3],
                  xx,zz,.274,.617,.045+k*.055,.085+k*.055,.011)
        B(m,"Separated low slag bin","oxidized_steel",x,3.86,1.31,.31,.020,.167,.019)
        for i in range(6):
            XX=x-.51+i*.20
            T(m,"Discarded cast shape in open slag bin","slag",(XX,3.81,.154),(XX+.084,3.93,.217),.057,.043,8)
    track(m,"Siding along steel ingot yard",[(.02,3.29),(2.30,3.27),(3.63,3.39),(5.07,3.31),(7.16,3.37)],.18)
    track(m,"Under-house low hot section runner",[(4.73,4.91),(5.61,4.83),(6.64,4.81),(7.15,4.75)],.16)


def steel_house(m):
    shed(m,"Large steel rolling and tapping shed",5.60,3.85,2.55,2.59,1.23,1.74,"roof_zinc",open_south=True)
    for x in (4.74,5.24,5.77,6.32):
        B(m,"Interior long-throw traveling gantry post","oxidized_steel",x,4.97,.093,.076,.058,1.17,.008)
        T(m,"Under-canopy stiffener truss","metal_blue",(x,4.94,.94),(x+.12,4.94,1.145),.021,.021,4)
    B(m,"Overhead maintenance runway beam","metal_blue",5.72,4.97,2.17,.105,1.084,1.154,.008)
    B(m,"Overhead block and tackle traveler","yellow_safety",5.16,4.99,.290,.13,1.072,1.201,.013)
    T(m,"Overhead grapnel dropline","darkiron",(5.16,5.02,1.111),(5.16,5.02,.572),.009,.009,7)
    for q in (-1,1):
        beam(m,"Suspended gantry fork grab","oxidized_steel",(5.16,5.02,.577),(5.16+q*.085,5.02,.459),.016)
    B(m,"Long roof high ventilating ridge monitor","roof_rib",5.61,3.73,.454,1.68,1.64,1.934,.020)
    for xx in (5.371,5.845):
        for k in range(9):
            zz=3.0+k*.177
            B(m,"Raised steel vent window extrusion","glass_dark",xx,zz,.014,.112,1.74,1.89,.004)
            B(m,"Separate zinc highlights of high window","nickel",xx,zz,.015,.139,1.87,1.896,.004)
    B(m,"Tall monitor ridge cap","metal_blue",5.607,3.731,.573,1.76,1.933,1.987,.019)
    B(m,"Weathered enamel site office sign","metal_blue",5.58,5.18,.67,.046,1.183,1.285,.011)
    A.lettering(m,"Raised steel foundry yard lettering","STEEL",(5.58,5.208,1.233),.012,"south","bone")


def steel_furnaces(m):
    blast(m,"GFX52 riveted number one blast furnace",4.54,2.15,.03,1.0)
    blast(m,"GFX54 twin second working blast furnace",6.49,2.128,.079,.84)
    stack(m,"GFX54 furnace exhaust chimney",7.08,2.28,3.083,.184)
    stack(m,"GFX52 hot air stove smoke chimney",5.40,1.82,2.64,.133)
    pipe(m,"GFX52 wide refractory-coated gas offtake","roof_zinc",[(4.54,2.15,2.696),(4.54,2.15,2.93),
        (4.70,2.15,3.01),(5.17,2.15,2.94),(5.44,1.98,2.65),(5.44,1.98,1.82)],.082)
    pipe(m,"GFX54 curved gas main from charging bell","steel_plate",[(6.49,2.13,2.352),(6.49,2.13,2.64),
         (6.64,2.16,2.75),(6.91,2.30,2.61),(7.10,2.31,2.35),(7.10,2.31,1.43)],.085)
    for i,(x,z) in enumerate(((3.75,2.21),(3.39,2.66),(7.12,2.89))):
        h=1.37+i*.11
        T(m,"Cowper upright hot blast pressure stove foot","millbrick_dark",(x,z,.04),(x,z,.17),.278,.269,14)
        T(m,"Cowper stove extended oxygen preheat heat exchanger","oxidized_steel",(x,z,.154),(x,z,h),.218,.206,14)
        T(m,"Cowper stove closed mild-steel dome","roof_zinc",(x,z,h-.011),(x,z,h+.122),.211,.082,14)
    conveyor(m,"Long trestled gravity load to furnace skip",(2.61,1.11,.298),(4.53,2.04,2.47),.38)
    ore_bin(m,"High charging and gravity skip discharge bin",4.71,1.94,.72,.63,2.30,2.75,"metal_blue")
    for x in (5.67,6.11):
        for z in (1.88,2.35):
            B(m,"Low metal-gas switching control cabinets","metal_blue",x,z,.22,.213,.049,.464,.019)
    pipe(m,"Continuous cross-tile return blast gas main","oxidized_steel",[(3.45,2.23,.69),(4.06,2.23,.69),
        (4.09,2.43,.75),(5.12,2.43,.75),(5.40,2.17,.75),(6.39,2.15,.75)],.071)


SITES={
 "iron_mine":(18,IRON,(( "Excavated iron-bearing rock and graded site",mine_terrain),
                       ("No. 1 shaft winding gear and steam house",headframe),
                       ("Actual transfer conveyors and ore loading chutes",mine_process)),
              "Stock Iron Ore Mine",(3.40,3.45,.55),(12.8,12.7,9.7),11.0),
 "steel_mill":(8,STEEL,(( "Stock materials yards with iron fines, slag and internal rails",steel_yard),
                        ("Wide roof monitor and rolling-shop bridge crane",steel_house),
                        ("Dual blast furnace shells, refractory uptakes and stove trains",steel_furnaces)),
               "Stock Steel Mill",(3.39,2.42,.83),(12.3,13.1,10.2),10.6),
}


def triangulated(m):
    out=A.mesh()
    for n,faces in m.parts.items():
        for ids,c in faces:
            p=[m.vertices[n][i] for i in ids]
            for j in range(1,len(p)-1):
                out.face(n,c,(p[0],p[j],p[j+1]))
    return out


def build(site):
    id,layout,groups,title,look,cam,scale=SITES[site]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name=title
    scene["Upstream art metadata"]=f"OpenTTD 16.0-RC1 {SOURCE_SHA}; src/table/build_industry.h"
    scene["Type and layout"]=f"{id} layout 0: "+", ".join(f"({x},{z}) GFX{n}" for (x,z),n in layout.items())
    scene["Datum"]="Z up, rigid ground Z=0; separate native grade+1 NW anchors for each exact layout cell."
    mats=R.materials()
    for i,n in enumerate(PAL):mats[i].name=n.replace("_"," ").title()
    for group,builder in groups:
        m=A.mesh()
        builder(m)
        collection=bpy.data.collections.new(group)
        scene.collection.children.link(collection)
        R.to_blender(triangulated(m),collection,mats)
    geo=source_mesh(site)
    for (x,z),gfx in layout.items():
        f=R.MODELS/f"bl_industry_{site}_{x}_{z}.obj"
        R.export_obj(f,triangulated(S.clip(geo,x,z,layout)))
        p=f.read_text().split("\n",1)[1]
        f.write_text(f"# OpenTTD 16.0-RC1 industry {id}, layout 0 ({x},{z}) GFX {gfx}; original Blender art\n"+p)
    S.atlas("industry_"+site,PAL)
    rot=(Vector(look)-Vector(cam)).to_track_quat("-Z","Y")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=look
                view.region_3d.view_distance=scale*1.24
                view.region_3d.view_rotation=rot
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"stock_{site}.blend"),compress=True)
    if not os.getenv("STOCK_METAL_RENDER_DIR"):return
    bpy.ops.mesh.primitive_plane_add(size=40,location=(look[0],look[1],-.001))
    lower=bpy.data.materials.new("Meadow");lower.diffuse_color=(.162,.243,.096,1)
    bpy.context.object.data.materials.append(lower)
    camera=bpy.data.objects.new("Review survey camera",bpy.data.cameras.new("Review survey camera"))
    scene.collection.objects.link(camera)
    camera.location=cam
    camera.rotation_euler=rot.to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=scale
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1470
    scene.render.resolution_y=1150
    style=scene.display.shading
    style.light="STUDIO"
    style.color_type="MATERIAL"
    style.show_shadows=True
    style.show_cavity=True
    style.cavity_type="BOTH"
    scene.view_settings.view_transform="Standard"
    scene.render.filepath=str(Path(os.environ["STOCK_METAL_RENDER_DIR"])/f"{site}.png")
    bpy.ops.render.render(write_still=True)


def source_mesh(site):
    m=A.mesh()
    for _,builder in SITES[site][2]:
        builder(m)
    return triangulated(m)


if __name__=="__main__":
    only=os.getenv("STOCK_METAL_SITE")
    for site in ([only] if only else SITES):
        build(site)
