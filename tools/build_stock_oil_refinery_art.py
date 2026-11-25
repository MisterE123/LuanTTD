#!/usr/bin/env python3
"""Original coastal oil refinery in the exact 15-cell OpenTTD layout 0."""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import os
import sys

from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

A,R=S.A,S.R
B,T,F,Q=S.B,S.T,S.F,S.Q
PAL=dict(S.PAL, **{
    "sterling":"9ba7a3","satin":"bcc2ae","paint_cobalt":"436783","steel_blue":"577888",
    "live_pipe":"778e91","pipe_glint":"a0aaa1","dark_steel":"454f55","roof_seam":"7b8b8a",
    "paint_oil_green":"5c7c66","valve_red":"a85d4d","ironoxide":"93634d","steel_umber":"765847",
    "warning_ochre":"cd9c53","black_oil":"373d37","asphalt_c":"686f68","asphalt_l":"7d8376",
    "safety_concrete":"a5a390","gravel_c":"937f67","glassblock":"628283",
    "flare_orange":"c87c49","flare_amber":"e6a758","light_tan":"cdc0a1",
})
A.PAL=PAL;A.P=A.H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
VARIANT=int(os.getenv("STOCK_REFINERY_VARIANT","0"))
LAYOUTS=(
    {(0,0):20,(0,1):21,(0,2):22,(0,3):21,(1,0):20,(1,1):19,(1,2):22,(1,3):20,
     (2,1):18,(2,2):18,(2,3):18,(3,2):18,(3,3):18,(2,0):23,(3,1):23},
    {(0,0):18,(0,1):18,(0,2):21,(0,3):22,(0,4):20,(1,0):18,(1,1):18,(1,2):19,(1,3):20,
     (2,0):18,(2,1):18,(2,2):19,(2,3):22,(1,4):23,(2,4):23},
)
LAYOUT=LAYOUTS[VARIANT]
def positions(role):
    return tuple((x,z) for (x,z),gfx in LAYOUT.items() if gfx==role)
RECEIVE=((0,0,-1),(1,0,-1),(1,3,1)) if not VARIANT else ((0,4,1),(1,3,-1))
TANKS=positions(18)
NAME="industry_oil_refinery"+("_l1" if VARIANT else "")


def curve_pipe(m,n,c,pts,r,nside=8,flange=()):
    for j,(a,b) in enumerate(zip(pts,pts[1:])):
        T(m,n,c,a,b,r,r,nside)
        if j+1<len(pts)-1:
            x,z,h=b
            S.ellipse(m,n+" curved seamless elbow",c,x,z,h,r*.994,r*.995,r*.990,nside)
        if j in flange:
            t=Vector(b)-Vector(a)
            u=Vector(a)+t*.57
            d=t.normalized()*.022
            T(m,n+" bolted flange collar","dark_steel",u-d,u+d,r*1.28,r*1.28,nside)


def yard(m):
    for x,z in LAYOUT:
        a,b=2*x-.5,2*z-.5
        Q(m,"Refinery continuous oil-resistant yard","asphalt_c",a,a+2,b,b+2,.009)
        for q in (0,1):
            x0=a+.05; z0=b+q*.92+.08
            Q(m,"Flush grade seams within plant site","dark_steel",x0,a+1.94,z0,z0+.009,.010)
        rng=Random(1205+x+41*z)
        for _ in range(27):
            i=rng.uniform(a+.05,a+1.91);j=rng.uniform(b+.04,b+1.95)
            Q(m,"Dark aged aggregates in sealed apron",rng.choice(("asphalt_c","asphalt_l","concrete_seal")),
              i,i+rng.uniform(.015,.051),j,j+rng.uniform(.009,.037),.011)
    # Lined pedestrian-only service routes. The north arm ends before the
    # unowned north-east cell; no invented foundation/render occupancy there.
    for x0,x1,z0,z1 in (() if VARIANT else ((-.40,1.37,3.30,3.48),(3.49,7.43,3.30,3.47),
                         (3.39,3.55,1.58,5.40),(.17,1.34,6.96,7.30))):
        Q(m,"Painted operator routes by process cells","asphalt_l",x0,x1,z0,z1,.013)
    for x,z in (((2*a+.51,2*b+1.22) for a,b,_ in RECEIVE) if VARIANT else ((.5,1.22),(2.52,1.26),(2.52,5.70))):
        B(m,"Low covered drainage channel","black_oil",x,z,.390,.069,.012,.022,.007)
        for j in range(8):
            xx=x-.17+j*.049
            Q(m,"Open grating plate bars","live_pipe",xx,xx+.018,z-.030,z+.031,.026)


def hood(m,x,z,n):
    for dx in (-.31,.31):
        for dz in (-.18,.18):
            B(m,n+" collision-recessed canopy column","steel_umber",x+dx,z+dz,.046,.049,.028,.726,.005)
    F(m,n+" weather canopy deck","paint_cobalt",((x-.37,z-.24,.77),(x+.37,z-.24,.77),(x+.37,z+.23,.711),(x-.37,z+.23,.711)))
    for q in (-.36,.36):
        T(m,n+" rim on corrugated roof","live_pipe",(x+q,z-.24,.765),(x+q,z+.23,.714),.012,.012,6)
    for j in range(7):
        zz=z-.21+j*.068
        y=.768-(zz-z+.24)*.126
        T(m,n+" low relief standing sheet seam","steel_blue",(x-.365,zz,y),(x+.365,zz,y),.009,.009,5)


def unloading(m):
    for gx,gz,approach in RECEIVE:
        ox,oz=gx*2,gz*2
        x,z=ox+.44,oz+.50
        n="GFX20 road tanker crude receiving"
        za,zb=sorted((z+approach*.999,z-approach*.647))
        Q(m,n+" true open unloading approach slab","safety_concrete",x-.412,x+.412,za,zb,.015)
        for z0 in (z-.523,z+.528):
            Q(m,n+" gutter expansion shoulder","concrete_seal",x-.388,x+.395,z0-.006,z0+.006,.017)
        for dx in (-.371,.370):
            for j in range(5):
                zz=za+.11+j*.289
                Q(m,n+" hose restriction and weigh approach paint","warning_ochre",x+dx-.013,x+dx+.013,zz,zz+.142,.023)
        # Black plate exactly flush with the driving lane. Small hardware
        # is all on the right shoulder, never across either entrance.
        Q(m,n+" flush galvanized inspection grate","dark_steel",x-.337,x+.337,z-.151,z+.151,.024)
        for j in range(15):
            xx=x-.315+j*.044
            Q(m,n+" flush inspection grate slots","live_pipe",xx,xx+.023,z-.137,z+.137,.027)
        mx=x+.67
        hood(m,mx,z-approach*.079,n)
        B(m,n+" offset spill containment slab","foundation",mx,z,.559,.384,.009,.081,.026)
        B(m,n+" calibrated pump body","paint_oil_green",mx+.017,z,.271,.213,.078,.316,.032)
        B(m,n+" enclosed oil flow dial","dark_steel",mx-.128,z,.033,.138,.199,.303,.009)
        T(m,n+" brass edge flow gauge","bone",(mx-.141,z,.253),(mx-.158,z,.253),.038,.038,12)
        c=mx-.162
        curve_pipe(m,n+" curved parked delivery-connection hose","black_oil",
                   [(c,z-.11,.177),(c-.027,z-.23,.134),(c-.07,z-.239,.082),
                    (c-.067,z-.160,.097),(c-.038,z-.036,.172),(c,z+.032,.213)],.013,8)
        T(m,n+" silver tanker quick connector","pipe_glint",(c-.078,z-.225,.090),(c-.11,z-.225,.092),.022,.018,9)
        ring=mx+.161
        curve_pipe(m,n+" permanent return manifold","valve_red",[(ring,z-.11,.176),(ring,z-.25,.176),
                   (ring,z-.25,.399),(ring,z-.37,.399)],.029,10,(1,))
        for zz in (z-.394,z+.391):
            B(m,n+" protected shoulder bollard","warning_ochre",x+.487,zz,.035,.045,.022,.184,.008)
            B(m,n+" warning paint ring","dark_steel",x+.487,zz,.037,.047,.101,.127,.003)
        signz=z+approach*.279
        B(m,n+" blue porcelain receiving station placard","paint_cobalt",mx,signz,.386,.040,.553,.663,.007)
        lettering=A.mesh()
        A.lettering(lettering,n+" raised OIL label","OIL",(mx,signz+.024,.610),.011,"south","bone")
        for part,fs in lettering.parts.items():
            for ids,color in fs:
                points=[lettering.vertices[part][i] for i in ids]
                if approach<0:
                    points=[(2*mx-a,2*signz-b,h) for a,b,h in points]
                m.face(part,color,points)
        # Reproduce the stock flare silhouette alongside, not over Oil drop.
        fx,fz=ox-.233,oz+.61-approach*.388
        stack(m,fx,fz,1.926+.19*(gx+gz)*.3,flare=True)


def hoop(m,n,c,x,z,h,r,wire=.012,div=16):
    for j in range(div):
        a,b=j*2*pi/div,(j+1)*2*pi/div
        T(m,n,c,(x+r*cos(a),z+r*sin(a),h),(x+r*cos(b),z+r*sin(b),h),wire,wire,5)


def ladder(m,n,x,z,y0,y1,rail=.042,side="south",cage=False):
    l=(y1-y0)
    if l<=0:return
    for s in (-1,1):
        T(m,n+" fixed open ladder stiles","dark_steel",(x+s*rail,z,y0),(x+s*rail,z,y1),.009,.009,6)
    num=max(2,round(l/.116))
    for j in range(num+1):
        y=y0+j*l/num
        T(m,n+" punched through ladder steps","sterling",(x-rail,z,y),(x+rail,z,y),.008,.008,6)
    if cage:
        for j in range(5):
            h=y0+(j+1)*l/6
            p=[(x+rail*cos(i*pi/5),z+.056*sin(i*pi/5),h) for i in range(6)]
            for a,b in zip(p,p[1:]):T(m,n+" cage bands","roof_seam",a,b,.006,.006,4)


def vessel(m,n,x,z,y0,h,r,color="sterling",shell="satin"):
    foot=max(.008,y0-.058) if y0>.5 else .008
    T(m,n+" chamfered bolted pressure foot","foundation",(x,z,foot),(x,z,y0+.021),r*1.13,r*1.04,16)
    T(m,n+" welded cylindrical shell",color,(x,z,y0),(x,z,h-.047),r,r,20)
    T(m,n+" distinct shallow dished cap",shell,(x,z,h-.050),(x,z,h),r*.994,r*.81,20)
    for j in (.12,.87):
        y=y0+(h-y0)*j
        T(m,n+" rolled strengthening collar",shell,(x,z,y),(x,z,y+.025),r*1.006,r*1.006,20)
    T(m,n+" inspection port lead","live_pipe",(x+.10*r,z,h-.010),(x+.10*r,z,h+.059),r*.105,r*.105,10)


def stack(m,x,z,height,flare=False):
    n="GFX20 burner and perforated service flare" if flare else "GFX19 tall fractionating tower"
    rr=.075 if flare else .137
    vessel(m,n,x,z,.118,height-.050,rr,"live_pipe","sterling")
    foot=.05
    B(m,n+" anchoring skirt","steel_blue",x,z,2.8*rr,2.7*rr,.012,.131,.015)
    for j in range(3):
        y=.453+j*(height-.6)/3
        radius=rr*1.72
        T(m,n+" ring access platforms","dark_steel",(x,z,y),(x,z,y+.019),radius,radius,16)
        hoop(m,n+" continuous circumferential handrail","steel_blue",x,z,y+.110,radius*.934,.006,12)
        for i in range(6):
            alpha=i*pi/3
            bx,bz=x+radius*.927*cos(alpha),z+radius*.927*sin(alpha)
            T(m,n+" thin guard stanchions","sterling",(bx,bz,y+.018),(bx,bz,y+.112),.005,.005,5)
    ladder(m,n,x,z+rr*1.394,.113,height-rr*.741,.047,cage=True)
    if flare:
        # A neutral extinguished pilot nozzle; an effect can be attached
        # later without baking a moving flame into the core graphics.
        for a in range(3):
            h=height-.117+a*.05
            T(m,n+" three turned heat shield collars",("satin","dark_steel","ironoxide")[a],(x,z,h),(x,z,h+.03),rr*1.13,rr,12)
        T(m,n+" oxidized igniter nozzle","dark_steel",(x,z,height-.022),(x,z,height+.080),rr*.48,rr*.61,12)
    else:
        for j in range(3):
            y=height-.49*j-.24
            T(m,n+" colored distillation fraction bands","paint_cobalt",(x,z,y),(x,z,y+.123),rr*1.009,rr*1.009,18)
        curve_pipe(m,n+" external condenser return line","valve_red",
                   [(x-rr*.84,z,height-.078),(x-rr*1.47,z,height-.086),
                   (x-rr*1.47,z,.267),(x-rr*.631,z,.267)],.026,10,(1,))


def tankfarm(m):
    for j,(gx,gz) in enumerate(TANKS):
        ox,oz=gx*2,gz*2
        x,z=ox+.487,oz+.49
        n="GFX18 broad bunded white stock tank"
        B(m,n+" low catch basin concrete floor","safety_concrete",x,z,1.598,1.598,.012,.061,.044)
        for q in (-.774,.774):
            B(m,n+" containment curb","foundation",x+q,z,.057,1.596,.052,.141,.006)
            B(m,n+" containment curb","foundation",x,z+q,1.596,.057,.052,.141,.006)
        r=(.477,.508,.506,.471,.503)[j%5]
        h=(.688,.840,.780,.725,.762)[j%5]
        vessel(m,n,x,z,.146,h,r,"sterling","satin")
        T(m,n+" dark blue band at tank base","paint_cobalt",(x,z,.185),(x,z,.342),r*1.009,r*1.009,24)
        hoop(m,n+" open rooftop rim railing","sterling",x,z,h+.083,r*.885,.008,20)
        for q in range(10):
            a=q*pi/5
            xx,zz=x+r*.884*cos(a),z+r*.884*sin(a)
            T(m,n+" spaced roof rail stiles","dark_steel",(xx,zz,h-.016),(xx,zz,h+.087),.006,.006,5)
        ladder(m,n,x+r*.10,z+r+.053,.084,h+.096,.069)
        curve_pipe(m,n+" draw manifold and wheel valve path","live_pipe",
            [(x+r*.71,z+r*.63,.429),(x+r*.98,z+r*.94,.429),
             (x+r*.98,z+r*.94,.169),(x+.664,z+.664,.169)],.034,8,(1,))
        T(m,n+" red operating wheel hub","valve_red",(x+.65,z+.663,.181),(x+.65,z+.663,.226),.028,.026,9)
        hoop(m,n+" oversize orange operating valve wheel","valve_red",x+.65,z+.663,.229,.043,.009,9)


def process(m):
    for a,b in positions(19):
        x,z=2*a,2*b
        stack(m,x+.17,z+.40,2.216)
        vessel(m,"GFX19 companion fractionating condenser",x+.93,z+.64,.085,1.234,.173,"sterling","paint_cobalt")
        curve_pipe(m,"GFX19 inter-vessel process vapor run","paint_cobalt",
            [(x+.26,z+.39,1.796),(x+.62,z+.39,1.796),(x+.62,z+.59,1.796),
             (x+.62,z+.59,1.105),(x+.86,z+.59,1.105)],.047,9,(2,3))
    for x,z in ((a*2+.50,b*2+.50) for a,b in positions(21)):
        n="GFX21 open-frame exchanger building"
        B(m,n+" bolted runner foot","foundation",x,z,1.44,1.47,.008,.11,.024)
        for a in (-.54,.54):
            for b in (-.52,.52):
                B(m,n+" rust red I-beam uprights","ironoxide",x+a,z+b,.079,.079,.09,1.477,.008)
        for h in (.384,1.473):
            for a in (-.55,.55):
                T(m,n+" exposed horizontal side member","steel_umber",(x+a,z-.53,h),(x+a,z+.53,h),.038,.038,4)
                T(m,n+" exposed cross member","ironoxide",(x-.55,z+a,h),(x+.55,z+a,h),.039,.039,4)
        for a in (-.545,.545):
            T(m,n+" diagonally braced safety steel","ironoxide",(x-.54,z+a,.393),(x+.54,z+a,1.46),.021,.021,4)
            if a>0:continue
            T(m,n+" diagonally braced safety steel","ironoxide",(x+.54,z+a,.393),(x-.54,z+a,1.46),.021,.021,4)
        for b in (-.24,.23):
            T(m,n+" horizontal finned exchanger barrel","steel_blue",(x-.412,z+b,.831),(x+.412,z+b,.831),.159,.159,16)
            for a in (-.38,-.16,.15,.38):
                T(m,n+" metal fin collars","sterling",(x+a,z+b,.831),(x+a+.018,z+b,.831),.167,.167,12)
            curve_pipe(m,n+" exchanger downpipes","live_pipe",
                [(x+.411,z+b,.831),(x+.483,z+b,.831),(x+.483,z+b,.979),(x+.483,z+b+.209,.979)],.036,8)
        Q(m,n+" open grippy maintenance bridge","dark_steel",x-.507,x+.512,z-.110,z+.108,1.128)
        ladder(m,n,x-.454,z+.556,.126,1.175,.049,cage=True)
    for i,(x,z) in enumerate(((a*2+.49,b*2+.49) for a,b in positions(22)) if VARIANT else ((.49,4.49),(2.57,4.40))):
        n="GFX22 raised vapor reservoir and attached pipes"
        B(m,n+" beveled concrete engine floor","foundation",x,z,1.548,1.463,.012,.101,.024)
        for a in (-.283,.283):
            for b in (-.220,.220):
                B(m,n+" cast four-legged trestle","ironoxide",x+a,z+b,.054,.053,.081,.908,.007)
        vessel(m,n+" rounded stirred receiver",x,z,.834,1.461+.077*i,.336,"steel_blue","paint_cobalt")
        vessel(m,n+" paired small flash drum",x+.53,z-.231,.115,.625,.151,"live_pipe","sterling")
        vessel(m,n+" horizontal boiler feed",x-.52,z+.301,.118,.578,.160,"sterling","paint_cobalt")
        curve_pipe(m,n+" three runs of external welded pipe","live_pipe",[(x,z,1.49),(x+.47,z,1.49),
                   (x+.47,z,1.18),(x+.52,z-.231,1.18),(x+.52,z-.231,.61)],.041,10,(1,2))
        ladder(m,n,x,z+.353,.11,1.555,.060,cage=True)
    if VARIANT:
        for (x,z),role in LAYOUT.items():
            if role not in (18,19,21,22):continue
            for dx,dz in ((1,0),(0,1)):
                if LAYOUT.get((x+dx,z+dz)) not in (18,19,21,22):continue
                a,b=x*2+.48,z*2+.48
                curve_pipe(m,"Low transfer manifold between adjacent process cells","live_pipe",
                    [(a,b,.24),(a+dx*.37,b+dz*.37,.39),(a+dx*1.63,b+dz*1.63,.39),
                     (a+dx*2,b+dz*2,.24)],.035,10,(1,))
    else:
        curve_pipe(m,"Continuous low process transfer manifold across real tiles","live_pipe",
            [(1.18,4.67,.367),(1.43,4.67,.367),(1.43,4.06,.367),(3.52,4.06,.367),
             (3.52,4.06,.298),(4.34,4.06,.298)],.045,10,(2,4))


def officials(m):
    for i,(x,z) in enumerate(((a*2+.48,b*2+.48) for a,b in positions(23)) if VARIANT else ((4.48,.479),(6.44,2.518))):
        n="GFX23 low pump controls and passenger staff building"
        B(m,n+" small stone soubassement","foundation",x,z,1.157,.841,.012,.114,.022)
        B(m,n+" oxide wash brick and shallow wall","brick",x,z,1.073,.753,.109,.584,.015)
        A.gable(m,n+" warm blue sheet roof",x,z,1.202,.872,.577,.725,"steel_blue","z")
        S.gable_panel(m,n+" solid masonry roof end",x,z+.376,1.066,.571,.708,"dark_brick",True)
        for dx in (-.32,.313):
            A.facade_window(m,n+" lighted glass",x+dx,z+.384,.224,.267,.502)
        A.doorway(m,n+" large valve operator door",x,z+.392,.212,.102,.488,"paint_oil_green")
        A.lantern(m,x,z+.419,.527,n+" brass bulkhead light")
        B(m,n+" sign band","dark_steel",x,z+.39,.551,.033,.604,.674,.009)
        if i==0:A.lettering(m,n+" named terminal plate","TIDELAND",(x,z+.409,.638),.0087,"south","bone")
        else:A.lettering(m,n+" pump authority sign","OIL OFFICE",(x,z+.411,.639),.008,"south","bone")
        for dx in (-.735,.707):
            B(m,n+" covered service bench","timber",x+dx,z+.205,.157,.301,.112,.161,.008)
            B(m,n+" foundation legs","board",x+dx,z+.205,.107,.053,.018,.147,.007)


if __name__=="__main__":
    S.build(NAME,LAYOUT,(("Addressable refinery yard and drainage",yard),
      ("Three real tanker unloading and flare lanes",unloading),
      ("Bunded broad oil tanks and visible draw valves",tankfarm),
      ("Fractionation towers and red iron process house",process),
      ("Staff entrance and control rooms",officials)),
      "Tideland Refinery","stock_oil_refinery"+("_l1" if VARIANT else "")+".blend",(3.28,3.60,.85),(11.4,11.8,8.9),10.65,
      PAL,os.getenv("STOCK_OIL_REFINERY_RENDER"),upstream_layout=VARIANT)
