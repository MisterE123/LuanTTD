#!/usr/bin/env python3
"""Model the stock #9 Ginzu A4, an original Gresley Pacific interpretation.

Blender +Y is rear, +Z up. Entity -Z nose, rail crown Y=0, native scale 1.
Set GINZU_A4_REVIEW to an optional two-angle Workbench PNG.
"""
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_chaney_jubilee_art as J
R,W=J.R,J.W
B,D=J.B,J.Disk
Pipe,Lathe,Beam=J.Pipe,J.Lathe,J.Beam
ROOT=R.ROOT
NAME="bl_rail_ginzu_a4"
PALETTE={
  "Garter blue":"22628e","Crown enamel blue":"377fa6","Blue sunlight":"5a94b3",
  "Deep blue shadow":"20435f","Creased blue":"2b5370","Tender recessed blue":"295875",
  "Black heat-resistant casing":"303c44","Slate nosing":"45535a",
  "Blue-black smoke seam":"252f39","Driver red":"78392f","Spoke red highlights":"a24d42",
  "Underframe graphite":"384346","Blackened tender wheel":"3b4348",
  "Forged rod steel":"8a9693","Nickel running edge":"98a69f","Flange steel":"435151",
  "Dull pin brass":"aa9263","Bright oiled nickel":"c2c7b3",
  "Boiler pipe copper":"a17755","Pressed hairline ledge":"bfb2a0",
  "Painted silver rim rule":"a8b4b2","Red beam":"984c43","Red paint lip":"ad5c51",
  "Warm lamp face":"f3e1ab","Red rear lamp":"ba5145","Coal deepest":"242d32",
  "Coal matt":"323b3e","Coal cool sheen":"4d5756","Firebrick":"55413a",
  "Firelight amber":"d88a52","Glass deep":"314c5b","Horizon glass":"729aa8",
  "Cream numbers":"e9d8a3","Brass border":"b6995e","Sign black":"463930",
  "Cab roof graphite":"3b4a52","Cab upright inner":"465b5e",
  "Corridor wood tread":"796757","Weathered valve steel":"697d80","Review ballast":"827d71",
}
P={k:i for i,k in enumerate(PALETTE)}
R.COLORS[:]=PALETTE.values()
J.P=W.P=P

BOGIE=(-.320,-.255)
DRIVER=(-.172,-.053,.066)
TRAIL=(.155,)
TENDER=(.207,.253,.299,.344)
DR=.059
GAUGE=.424
PHASE=.45
FRAMES=64
WHEELS=(("Pilot bogie",BOGIE,.030,.055,.028),("Main driver",DRIVER,DR,.030,.031),
        ("Trailing truck",TRAIL,.0295,.048,.023),("Tender",TENDER,.0215,.055,.029))


def mesh():
    return R.Mesh(R.terrain_height(0))


def F(m,n,c,v):
    m.face(n,P[c],v)


def shell(m,n,sections,caps,col):
    # Original CCW cross-sections in X/elevation. Native Z runs front to rear.
    npoints=len(sections[0][1])
    for z,r,index in ((sections[0][0],sections[0][1],0),
                      (sections[-1][0],sections[-1][1],1)):
        a=[(x,z,y) for x,y in r]
        F(m,n,caps[index],a if index==0 else a[::-1])
    for i,((a,u),(b,v)) in enumerate(zip(sections,sections[1:])):
        for k in range(npoints):
            q=(k+1)%npoints
            F(m,n,col(i,k),((u[k][0],a,u[k][1]),(v[k][0],b,v[k][1]),
                           (v[q][0],b,v[q][1]),(u[q][0],a,u[q][1])))


def barrel(w,b,t):
    h=t-b
    return [(-.75*w,b),(.75*w,b),(w,b+.095*h),(w,b+.58*h),
      (.93*w,b+.73*h),(.77*w,b+.865*h),(.56*w,b+.953*h),
      (.29*w,b+.991*h),(0,t),(-.29*w,b+.991*h),(-.56*w,b+.953*h),
      (-.77*w,b+.865*h),(-.93*w,b+.73*h),(-w,b+.58*h),(-w,b+.095*h)]

CASING=(
  (-.465,.049,.164,.259),(-.455,.098,.171,.322),(-.438,.127,.177,.392),
  (-.411,.151,.186,.456),(-.385,.166,.192,.508),(-.355,.176,.197,.545),
  (-.312,.186,.200,.565),(-.247,.194,.203,.578),(-.165,.197,.199,.584),
  (-.081,.197,.195,.582),(.006,.198,.192,.574),(.071,.192,.182,.570),
  (.111,.184,.188,.573),
)


def casing(m):
    n="Revolved sheet metal A4 shoulder and slanted wedge smokebox shroud"
    def color(i,k):
        if i<5 and k not in (0,1,13,14):
            if k in (6,7,8,9):
                return "Slate nosing" if i in (2,4) else "Black heat-resistant casing"
            return "Black heat-resistant casing" if k in (3,4,11,12) else "Deep blue shadow"
        return ("Underframe graphite","Deep blue shadow","Deep blue shadow",
             "Garter blue","Garter blue","Crown enamel blue","Crown enamel blue",
             "Blue sunlight","Blue sunlight","Crown enamel blue","Crown enamel blue",
             "Garter blue","Garter blue","Deep blue shadow","Deep blue shadow")[k]
    shell(m,n,[(z,barrel(w,b,t)) for z,w,b,t in CASING],
        ("Black heat-resistant casing","Garter blue"),color)
    # Riveted low valance follows actual curvature and narrows before the
    # buffing gear. Cutting its middle lower edge distinguishes the cab.
    SEAM=(
     (-.456,.097,.167,.214),(-.431,.131,.161,.261),
     (-.390,.172,.138,.271),(-.340,.191,.129,.263),
     (-.268,.202,.124,.248),(-.189,.221,.101,.236),
     (-.102,.218,.104,.232),(-.021,.214,.110,.230),
     (.067,.202,.125,.224),(.116,.184,.187,.225),
    )
    for s in (-1,1):
        for a,b in zip(SEAM,SEAM[1:]):
            z0,w0,l0,h0=a;z1,w1,l1,h1=b
            for t in (0,1):
                if t:
                    p=((s*w0,z0,l0),(s*w1,z1,l1),(s*(w1-.012),z1,l1-.009),(s*(w0-.012),z0,l0-.009))
                else:
                    p=((s*w0,z0,l0),(s*w1,z1,l1),(s*w1,z1,h1),(s*w0,z0,h0))
                F(m,"Tapered full-length true separate skirt sheet and cut edge",
                  "Deep blue shadow" if t else "Garter blue",p if s>0 else p[::-1])
            p,q=(s*(w0+.001),z0,h0-.007),(s*(w1+.001),z1,h1-.007)
            Pipe(m,"Struck silver sweep lining between sky plate and valance","Painted silver rim rule",p,q,.0025,7)
        for z,x,y in ((-.384,.173,.263),(-.344,.193,.254),(-.307,.197,.249),
                     (-.264,.204,.241),(-.224,.214,.236),(-.183,.223,.226),
                     (-.147,.221,.226),(-.107,.219,.225),(-.065,.218,.223)):
            D(m,"Skirt rivet and polished rivet bead","Painted silver rim rule",
                (s*x,z,y),.00225,"x",-.0015,.0015,6)
        # Physical seam joining the black slanted smokebox to the full blue
        # body. Appended nickel handrails gently follow its top shoulder.
        pairs=((-.357,.160,.499),(-.310,.160,.515),(-.246,.171,.524),
               (-.171,.177,.528),(-.090,.181,.524),(.004,.179,.518),(.080,.172,.511))
        for a,b in zip(pairs,pairs[1:]):
            Pipe(m,"Continuous steam inspection handrail follows pressed shoulder",
                 "Forged rod steel",(s*a[1],a[0],a[2]),(s*b[1],b[0],b[2]),.0031,8)
        for z,x,y in pairs[::2]:
            Pipe(m,"Separate small nickel handrail foot","Underframe graphite",
                 (s*(x-.018),z,y-.025),(s*x,z,y),.0033,7)
        for z in (-.232,-.134,-.025):
            D(m,"Round casing boiler inspection lid","Deep blue shadow",
              (s*.194,z,.396),.017,"x",-.003,.004,12)
            D(m,"Warm metal lugs in inspection lid","Dull pin brass",
              (s*.199,z,.396),.007,"x",-.001,.001,8)
        plate(m,"Front oblong original raised GINZU name plaque",s,-.254,.455,.195,"GINZU",.0042)
    # The characteristic long, low double smoke opening: both chimney
    # holes are truly open and visibly black underneath the rolled lip.
    B(m,"Double Kylchap nested bed beneath two open collars","Slate nosing",
      0,-.337,.111,.087,.530,.555,.012)
    for z in (-.355,-.316):
        Lathe(m,"Low double chimney real perforated smoke outlet",
            [(.545,.029),(.560,.031),(.581,.032),(.587,.036),(.589,.028),(.573,.023),(.562,.022)],
            "h",(0,z,0),("Black heat-resistant casing","Slate nosing","Black heat-resistant casing",
             "Slate nosing","Coal deepest","Coal deepest"),22,False,False)
    Lathe(m,"Small flush streamlined top whistle moulding",
      [(.576,.021),(.589,.020),(.596,.013),(.603,.008)],"h",(0,-.040,0),
      ("Crown enamel blue","Blue sunlight","Dull pin brass"),14)
    B(m,"Short narrow front oil hatch on sloped beak","Slate nosing",0,-.442,
      .068,.018,.325,.352,.006)
    Pipe(m,"Split centre line along hinged smokebox skin","Blue-black smoke seam",
      (0,-.462,.269),(0,-.435,.398),.0025,6)
    B(m,"Central original nose fleet plate","Sign black",0,-.463,.104,.011,.232,.266,.005)
    number(m,.247,-.470,"A 09",.0048,False)


GLYPHS={
 "G":("111","100","101","101","111"),"I":("111","010","010","010","111"),
 "N":("101","111","111","111","101"),"Z":("111","001","010","100","111"),
 "U":("101","101","101","101","111"),"A":("010","101","111","101","101"),
 "0":("111","101","101","101","111"),"9":("111","101","111","001","111"),
 "4":("101","101","111","001","001")," ":("000","000","000","000","000"),
}


def glyphs(m,name,word,h,at,s,unit,xside=None):
    for j,c in enumerate(word):
        for row,pattern in enumerate(GLYPHS[c]):
            for k,v in enumerate(pattern):
                if v=="0":continue
                along=(j*4+k-(len(word)*4-2)/2)*unit
                z0=h+(4-row)*unit
                if xside is not None:
                    B(m,name,"Cream numbers",s*xside,at+s*along,.0022,unit*.82,
                      z0,z0+unit*.89)
                else:
                    B(m,name,"Cream numbers",s*along,at,unit*.82,.0023,
                      z0,z0+unit*.90)


def number(m,h,at,word,step,back):
    glyphs(m,"Front or rear raised fleet number plates",word,h,at,-1 if back else 1,step)


def plate(m,n,s,z,h,x,word,step):
    width=len(word)*4*step+.013
    B(m,n,"Brass border",s*x,z,.008,width,h-.014,h+.033,.004)
    B(m,"Inset dark nameboard panel","Sign black",s*(x+.005),z,.004,width-.009,h-.009,h+.027,.002)
    glyphs(m,"Individual raised cast letters for locomotive nameplate",word,h-.004,z,s,step,x+.008)


def underframe(m):
    outer=[(-.110,-.449),(.110,-.449),(.175,-.396),(.194,-.321),
           (.190,.098),(.161,.175),(-.161,.175),(-.190,.098),
           (-.194,-.321),(-.175,-.396)]
    J.shaped(m,"Tapered aero locomotive footplate","Underframe graphite",outer,.109,.172,"Creased blue")
    B(m,"Pressed continuous hornbeam frames","Underframe graphite",0,-.075,.323,.585,.071,.154,.014)
    for s in (-1,1):
        for z in DRIVER:
            B(m,"Locomotive axle-box slides behind open spoke wheel","Underframe graphite",
              s*.166,z,.041,.063,.045,.090,.006)
            for h in (.076,.089,.097):
                B(m,"Curved outboard spring leaf edges","Weathered valve steel",s*.166,z,
                  .051,.067-(h-.076)*1.1,h,h+.004,.002)
        for z in BOGIE:
            B(m,"Raised pilot wheelset spring yoke","Blue-black smoke seam",s*.175,z,.061,.052,
                .042,.076,.005)
        for z in TRAIL:
            B(m,"Rear articulated trailing-truck leaf retaining cast spine","Underframe graphite",
              s*.189,z,.052,.049,.054,.090,.005)
        for h,span in ((.071,.045),(.112,.052),(.158,.055)):
            B(m,"Cab separately hung crew steps below low threshold","Underframe graphite",
               s*.189,.153,span,.036,h,h+.014,.003)
        Pipe(m,"Rear visible cab corridor pipe to drawbar connector","Boiler pipe copper",
             (s*.094,.155,.157),(s*.075,.212,.153),.0058,7)
    B(m,"Demarcated separate short A4 steam tender drawbar","Bright oiled nickel",0,.185,
      .065,.069,.103,.140,.007)
    for s in (-1,1):
        B(m,"Cab-tender steel flexible service hose mounting","Blue-black smoke seam",s*.059,
          .181,.018,.037,.116,.152,.004)
    for at in (-.428,.414):
        B(m,"Individually cast red end beam, drawn inboard","Red beam",0,at,.205,.034,
          .128,.205,.009)
        for s in (-1,1):
            x=s*.089
            q=-1 if at<0 else 1
            Lathe(m,"Drawn in turned front and tender buffer sleeves",
                  [(min(at,at+q*.021),.023),(max(at,at+q*.021),.026)],"z",(x,0,.166),
                  ("Weathered valve steel",),17)
            D(m,"Bright rubbed round railway buffer contact face","Bright oiled nickel",
              (x,at+q*.022,.166),.024,"z",-.004,.004,18)
            Pipe(m,"Curved steel coupling air hose behind central reed","Blue-black smoke seam",
                 (s*.052,at+q*.012,.150),(s*.053,at+q*.025,.114),.0046,7)
        q=1 if at>0 else -1
        B(m,"Dark sculpted coupler chassis draw guide","Underframe graphite",0,q*.450,
          .063,.045,.133,.183,.006)
        B(m,"Dark polished real coupler draw arm pin tube","Weathered valve steel",0,q*.477,
          .031,.026,.141,.174,.004)
        # The tiny central lip avoids Wagon buffer overflight on radius-1
        # turns and meets the unchanged stock-adjacent center spacing.
        B(m,"Coupler knuckles","Bright oiled nickel",0,q*.494,.0105,.010,.146,.168,.002)
    for s in (-1,1):
        Lathe(m,"Rolled side headlight pressure lamp bowl",[(-.466,.019),(-.461,.020),(-.456,.014)],
          "z",(s*.112,0,.239),("Slate nosing","Underframe graphite"),14)
        D(m,"Real warm raised twin front lamp lenses","Warm lamp face",
          (s*.112,-.468,.239),.0155,"z",-.003,.003,16)
    B(m,"Raised rear ruby lamp cast casing","Underframe graphite",
      -.073,.447,.047,.013,.281,.327,.005)
    D(m,"Exposed tail ruby lens and lamp ring","Red rear lamp",
      (-.073,.454,.303),.016,"z",-.003,.005,14)


def cab(m):
    # The tapered cab narrows toward its open corridor. Real gaps are
    # visible around separately modeled side windows and interior fittings.
    CSH=((.101,.181,.186,.440,.573),(.130,.177,.185,.436,.588),
         (.158,.163,.185,.430,.588),(.168,.155,.185,.426,.581))
    shell(m,"Tapering lower cab panel that clears the connected tender",
      [(z,[(-x,b),(x,b),(x,t),(-x,t)]) for z,x,b,t,_ in CSH],
      ("Deep blue shadow","Cab upright inner"),lambda i,k:("Creased blue","Garter blue","Deep blue shadow","Garter blue")[k])
    for s in (-1,1):
        def strut(z,x,y0,y1):
            B(m,"Sloped heavy corner pillar of actual cut-out cab","Garter blue",
              s*x,z,.018,.011,y0,y1,.003)
        for z,w,y in ((.113,.180,.556),(.133,.175,.552),(.156,.165,.552)):
            strut(z,w,.435,y)
        q=(s*.178,.113,.446),(s*.175,.130,.445),(s*.175,.130,.545),(s*.178,.113,.548)
        F(m,"Clear deeply set forward closed cabin side glazing","Glass deep",q if s>0 else q[::-1])
        q=(s*.163,.143,.456),(s*.158,.154,.454),(s*.158,.154,.539),(s*.163,.143,.544)
        F(m,"Deep aft cabin side glazing peeking past the raised gasket","Horizon glass",q if s>0 else q[::-1])
        for z,x in ((.120,.181),(.149,.168)):
            B(m,"Framed narrow silver window sill at tapered cab","Painted silver rim rule",
              s*x,z,.005,.028,.430,.436,.001)
        for x,z,w in ((.162,.149,.026),(.171,.123,.027)):
            B(m,"Tapered cab lower access lining outside","Creased blue",
             s*x,z,.012,w,.276,.373,.002)
        glyphs(m,"Tiny original 09 cab-road numeral","09",.344,.137,s,.0047,.179)
        Pipe(m,"Passenger-steam cab polished rear step guide and grip","Bright oiled nickel",
          (s*.163,.168,.248),(s*.163,.168,.494),.0036,8)
        B(m,"Cab open railway door step","Cab upright inner",s*.159,.167,.032,.025,
          .195,.216,.003)
    # True arched roof of variable width, decreasing under driver's rear seam.
    def cs(w,t):
        return [(-w,t-.053),(-w*.90,t-.024),(-w*.67,t-.008),(-w*.34,t),(0,t+.002),
               (w*.34,t),(w*.67,t-.008),(w*.90,t-.024),(w,t-.053)]
    profiles=[(z,cs(w,y)) for z,w,y in (
        (.090,.199,.580),(.113,.191,.597),(.144,.180,.606),(.167,.169,.598),(.175,.165,.592))]
    for (z,a),(z2,b) in zip(profiles,profiles[1:]):
        for i in range(len(a)-1):
            p,q=(a[i][0],z,a[i][1]),(a[i+1][0],z,a[i+1][1])
            r,s=(b[i+1][0],z2,b[i+1][1]),(b[i][0],z2,b[i][1])
            F(m,"Tapered full double-skinned cab roof outer","Cab roof graphite",(p,q,r,s))
            F(m,"Tapered full double-skinned cab roof interior","Cab upright inner",
              tuple((x,Z,y-.014) for x,Z,y in (s,r,q,p)))
    for z,row in profiles[::len(profiles)-1]:
        for a,b in zip(row,row[1:]):
            Pipe(m,"Cab roof true rounded horizontal fascia","Slate nosing",
                 (a[0],z,a[1]-.004),(b[0],z,b[1]-.004),.003,6)
    B(m,"Actual exposed internal curved firebox throne","Firebrick",0,.126,.201,.028,
      .221,.396,.012)
    B(m,"Lozenge amber regulator hatch in aft cab","Firelight amber",0,.143,.087,.008,
      .248,.302,.007)
    for s in (-1,1):
        D(m,"Driver's real circular interior steam gauge","Boiler pipe copper",
          (s*.062,.145,.366),.016,"z",-.005,.004,12)
        Pipe(m,"Curved steam line beside cab firebox","Boiler pipe copper",
          (s*.071,.136,.278),(s*.082,.145,.407),.0038,8)
        B(m,"Under-window internal driver and fireman's narrow tread","Corridor wood tread",
          s*.128,.143,.045,.056,.281,.305,.007)


def tender(m):
    outline=[(-.159,.201),(.159,.201),(.177,.238),(.173,.355),(.156,.399),(.117,.437),
             (-.117,.437),(-.156,.399),(-.173,.355),(-.177,.238)]
    J.shaped(m,"Separate narrow Pacific four-axle tenders own chassis",
             "Underframe graphite",outline,.051,.120,"Deep blue shadow")
    J.shaped(m,"Visible deep hollow separate coal tender floor",
             "Coal deepest",outline,.124,.202,"Corridor wood tread")
    for s in (-1,1):
        walls=((.201,.159,.445),(.233,.177,.454),(.312,.177,.451),(.359,.171,.438),
               (.402,.151,.420),(.436,.117,.406))
        for a,b in zip(walls,walls[1:]):
            z,x,h=a;Z,X,H=b
            p=((s*x,z,.131),(s*X,Z,.131),(s*X,Z,H),(s*x,z,h))
            F(m,"A4 tender rolled blue separate outer side plate","Garter blue",p if s>0 else p[::-1])
            F(m,"Coal tender true inner side well and thickness","Coal deepest",
              tuple((v-s*.011,u,q) for v,u,q in (p[::-1] if s>0 else p)))
            Pipe(m,"Near top true raised swaged tender metal rim",
                 "Crown enamel blue",(s*x,z,h),(s*X,Z,H),.0045,8)
            for yy in (.197,.386):
                Pipe(m,"Fine continuous silver rule on water reservoir","Painted silver rim rule",
                 (s*(x+.002),z,yy),(s*(X+.002),Z,yy),.0019,6)
        plate(m,"Original tender recessed GINZU fascia",s,.292,.293,.178,"A4",.005)
        for z in TENDER:
            B(m,"Tender four sprung axlebox housings, one each bogie center","Underframe graphite",
              s*.176,z,.052,.035,.047,.097,.005)
            B(m,"Tender steel oil cap running board access plate","Weathered valve steel",s*.188,
               z,.028,.025,.046,.069,.004)
        Pipe(m,"Tender low rear ladder rail","Bright oiled nickel",
             (s*.085,.437,.213),(s*.085,.437,.363),.004,7)
    B(m,"Tender near end blue bulkhead with small door","Tender recessed blue",0,.204,.315,.012,
      .153,.444,.003)
    B(m,"Tender rolled aft water tank end plate","Tender recessed blue",
      0,.434,.230,.013,.138,.407,.003)
    B(m,"Tender corrugated aft water lid top taper","Crown enamel blue",
      0,.388,.171,.084,.363,.404,.008)
    for s in (-1,1):
        D(m,"Separate cast screw-down tender water standpipe lid","Slate nosing",(s*.049,.393,.411),
          .020,"h",-.009,.005,15)
    B(m,"Flexible cab corridor access lowered gangway","Corridor wood tread",0,.181,.187,.063,.191,.204,.005)
    coal=( (-.149,.212,.351),(.151,.213,.373),(.153,.309,.366),(.128,.338,.341),
           (-.138,.342,.333),(-.149,.304,.352))
    for j,p in enumerate(coal):
        F(m,"Actual uneven coal pile inside separate well","Coal matt",
           (p,coal[(j+1)%len(coal)],(.02,.264,.446)))
    rng=Random(909)
    for i in range(60):
        x=rng.uniform(-.144,.144);z=rng.uniform(.231,.333)
        y=.374+.065*(1-abs(x)/.145)-abs(z-.263)*.18
        d=rng.uniform(.006,.013)
        pts=[(x+d*cos(j*tau/5),z+d*sin(j*tau/5),y-d*.37) for j in range(5)]
        for j in range(5):
            F(m,"Rock coal lumps in tapering tender bunker",
              ("Coal deepest","Coal matt","Coal cool sheen")[(i+j)%3],
              (pts[j],pts[(j+1)%len(pts)],(x+d*.11,z-d*.21,y+d*.41)))


def rolling(m,name,axles,rad,out,inner,phase):
    for z in axles:
        D(m,name+" gauge-spanning locomotive axle","Underframe graphite",
          (0,z,rad),rad*.24,"x",-.221,.221,12)
        for s,side in ((-1,"L"),(1,"R")):
            x=s*.212
            a,b=sorted((s*out,-s*inner))
            # Broad contact band is retained across the outward stock
            # curve swing. Dark finish on the supporting edge avoids a
            # chrome slab at normal game distances.
            Lathe(m,"Rolling tread "+name+" "+side,[(a,rad*.73),(a,rad),
                (-.006,rad),(.006,rad),(b,rad),(b,rad*.73),(a,rad*.73)],"x",(x,z,rad),
                ("Underframe graphite","Blackened tender wheel","Nickel running edge","Blackened tender wheel",
                "Underframe graphite","Underframe graphite"),24,False,False)
            lo,hi=sorted((-s*.042,-s*.035))
            Lathe(m,"True inward rail guiding wheel flanges",[(lo,rad*.74),(lo,rad+.009),
              (hi,rad+.009),(hi,rad*.74),(lo,rad*.74)],"x",(x,z,rad),("Flange steel",),24,False,False)
            if name=="Main driver":
                flange=x+s*.021
                D(m,"Open driving wheel red cast grease hub","Driver red",
                  (flange,z,rad),.023,"x",-.010,.010,15)
                for k in range(14):
                    t=phase+pi/2*(s>0)+tau*k/14
                    a=(z+.022*cos(t),rad+.022*sin(t))
                    b=(z+rad*.794*cos(t),rad+rad*.794*sin(t))
                    Beam(m,"Fourteen individual cast crimson A4 driver spokes",
                        "Spoke red highlights" if k%3==0 else "Driver red",flange,a,b,.0045,.011)
                for k in range(7):
                    t=phase-.36+.13*k
                    p=[(x+s*.022,z+r*cos(q),rad+r*sin(q)) for r,q in (
                        (rad*.54,t),(rad*.78,t),(rad*.79,t+.14),(rad*.54,t+.14))]
                    F(m,"Additive crescent locomotive driver static ballast faces","Driver red",
                      p if s>0 else p[::-1])
                D(m,"Screw-on red locomotive driver hub cap","Spoke red highlights",
                  (x+s*.030,z,rad),.013,"x",-.005,.005,12)
            else:
                xface=x+s*(out-.006)
                D(m,"Dark wheel plate on pilot, trailer and tender sets","Underframe graphite",
                  (xface,z,rad),rad*.79,"x",-.005,.005,16)
                for k in range(6):
                    p=tau*k/6
                    D(m,"Raised round spoke boss on smaller wheel","Weathered valve steel",
                      (xface+s*.001,z+rad*.40*cos(p),rad+rad*.40*sin(p)),.0026,"x",-.003,.004,6)
                D(m,"Screw cap on small railway axle","Forged rod steel",
                  (xface+s*.001,z,rad),rad*.235,"x",-.004,.005,10)


def cylinders(m):
    for s in (-1,1):
        Lathe(m,"Cast exposed A4 cylinder cap beneath pressed casing",
          [(-.303,.018),(-.292,.026),(-.274,.032),(-.243,.032),(-.221,.027),(-.213,.017)],
          "z",(s*.178,0,.099),("Underframe graphite","Weathered valve steel","Underframe graphite",
             "Underframe graphite","Weathered valve steel"),16)
        for j in range(6):
            t=tau*j/6
            D(m,"Raised round cylinder fastener","Weathered valve steel",
              (s*.178+.018*cos(t),-.296,.099+.017*sin(t)),.0034,"z",-.004,.002,7)


def motion(m,p):
    for s in (-1,1):
        t=p+pi/2*(s>0)
        cr=.018
        pins=[(z+cr*cos(t),DR+cr*sin(t)) for z in DRIVER]
        x=s*.243
        for z,y in pins:
            D(m,"Independent moving quartered A4 driving pin and cap","Dull pin brass",
              (x,z,y),.010,"x",-.004,.005,12)
            D(m,"Locked bright crank pin end","Bright oiled nickel",(x+s*.006,z,y),
             .0054,"x",-.003,.003,10)
        Beam(m,"Continuous external polished three-driver coupling rod","Forged rod steel",
          x,pins[0],pins[-1],.010,.008)
        Beam(m,"External split side rod with working crosshead","Bright oiled nickel",
          s*.252,(-.202+.017*cos(t),.104),pins[1],.012,.009)
        c=-.205+.017*cos(t)
        Pipe(m,"Sliding visible split A4 piston arm polished","Forged rod steel",
          (s*.224,-.269,.104),(s*.224,c,.104),.0045,8)
        B(m,"Incised locomotive moving crosshead shoe","Underframe graphite",
          s*.232,c,.028,.025,.088,.117,.003)
        Beam(m,"Motion-detail return link running between oscillating pins","Weathered valve steel",
          s*.256,(-.215+.014*cos(t),.121),(pins[1][0]-.015,pins[1][1]+.017),.006,.005)


def body():
    m=mesh()
    underframe(m);casing(m);cab(m);tender(m);cylinders(m)
    # The shared 8-unit stock length cannot admit the real locomotive's
    # long front overhang at tiny turnout radius. Press the whole forward
    # shroud, skirts and narrow lamp fittings inboard of the axle swing;
    # the fixed coupling remains at the exact existing radius/height.
    out=mesh()
    anchor=-.273
    for name,faces in m.parts.items():
        pts=[(x,anchor+(z-anchor)*.76 if z<anchor and "oupler" not in name else z,h)
                for x,z,h in m.vertices[name]]
        for ids,color in faces:out.face(name,color,[pts[i] for i in ids])
    return out


def whole():
    m=body()
    for n,z,r,a,b in WHEELS:rolling(m,n,z,r,a,b,PHASE)
    motion(m,PHASE)
    return m


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    (R.TEXTURES/(NAME+".png")).write_bytes(
      b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
      +chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b""))


def colors():
    m=R.materials()
    for key,j in P.items():
        mat=m[j];mat.name=key
        n=mat.node_tree.nodes.get("Principled BSDF")
        n.inputs["Metallic"].default_value=.44 if any(r in key.lower() for r in ("nickel","steel","metal")) else .05
        n.inputs["Roughness"].default_value=.37 if "blue" in key.lower() else .71
    return m


def rig(sc,mats):
    sc.frame_start=1
    sc.frame_end=FRAMES+1
    J.geometry(sc,"Separate A4 nose, skirt, cab, footboards and coal tender",body(),mats)
    grp=bpy.data.collections.new("Ten editable locomotive and tender axle assemblies")
    sc.collection.children.link(grp)
    for name,axles,rad,out,inner in WHEELS:
        for i,z in enumerate(axles,1):
            c=bpy.data.collections.new(f"{name} wheelset {i}")
            grp.children.link(c)
            m=mesh()
            rolling(m,name,(z,),rad,out,inner,PHASE)
            R.to_blender(m,c,mats)
            pivot=bpy.data.objects.new(f"{name} {i} · working X axle pivot",None)
            pivot.empty_display_type="CIRCLE"
            pivot.empty_display_size=rad+.021
            grp.objects.link(pivot)
            pivot.location=(0,z,rad)
            for x in c.objects:x.parent=pivot;x.location=(0,-z,-rad)
            for frame,t in ((1,0),(FRAMES+1,tau*DR/rad)):
                pivot.rotation_euler.x=t
                pivot.keyframe_insert(data_path="rotation_euler",index=0,frame=frame)
            J.linear(pivot.animation_data.action.fcurves)
    first=mesh()
    motion(first,PHASE)
    group=J.geometry(sc,"Quartered articulated driver pins, rods, crossheads and visible valve motion",first,mats)
    steps=[]
    for i in range(1,16):
        m=mesh()
        motion(m,PHASE+tau*i/16)
        steps.append(m)
    for ob in group.objects:
        name=ob.name
        ob.shape_key_add(name="Frame one baked position")
        for i,m in enumerate(steps,1):
            key=ob.shape_key_add(name=f"Quartered A4 motion phase {i:02d}")
            pts=m.vertices[name]
            if len(pts)!=len(key.data):raise RuntimeError((name,len(key.data),len(pts)))
            for v,p in zip(key.data,pts):v.co=p
            for t,x in ((1+4*(i-1),0),(1+4*i,1),(1+4*(i+1),0)):
                key.value=x
                key.keyframe_insert(data_path="value",frame=t)
        J.linear(ob.data.shape_keys.animation_data.action.fcurves)
    sc.frame_set(1)


def blend():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · Ginzu A4 #9 stock express 4-6-2 Pacific"
    sc.view_settings.view_transform="Standard"
    sc["Width/scale"]="Native standard .424 rail centers. Mount at +.614 in flat track. Local -Z nose."
    sc["Authoring track gauge"]="10 export units per native. Wheels independent; set action frames 1–65."
    sc["Model provenance"]="Original meshes inspired by Science Museum Group A4 and CC photos (see art/rail_ginzu_a4.md). No shipped reference paint."
    sc["Tender"]="Four axles separate geometry; train controller sees one generic-length stock head."
    rig(sc,colors())
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                sp=area.spaces.active
                sp.shading.color_type="MATERIAL"
                sp.region_3d.view_location=Vector((0,0,.298))
                sp.region_3d.view_rotation=Vector((.72,-.84,.41)).to_track_quat("Z","Y")
                sp.region_3d.view_distance=1.85
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/rail_ginzu_a4.blend"),compress=True)


def review(m,path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene
    mats=colors()
    sc.view_settings.view_transform="Standard"
    J.render(sc,R.stash(m,mats,"Original Ginzu A4 dual-view preview"),path)


if __name__=="__main__":
    m=whole()
    out=R.MODELS/(NAME+".obj")
    R.export_obj(out,W.local_obj(m))
    raw=out.read_text()
    out.write_text("# Original Ginzu A4 steam tender express; tools/build_ginzu_a4_art.py\n"+raw.split("\n",1)[1])
    atlas()
    blend()
    if path:=os.getenv("GINZU_A4_REVIEW"):
        review(m,path)
