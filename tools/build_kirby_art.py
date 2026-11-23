#!/usr/bin/env python3
"""Original early Fowler-influenced Kirby Paul 0-6-0T for LuanTTD."""
from math import cos, pi, sin, tau
import os
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as wag

bpy=wag.bpy
Vector=wag.Vector
rail=wag.rail
NAME="bl_rail_kirby_paul_tank"
AXLES=(-.269,-.051,.171)
RADIUS=.101
BOILER=(0,-.091,.470)
P={
    "Cast soot":"293131","Smokebox edge":"414849","Smokebox patina":"333b3c","Firebox":"45524b",
    "Frame charcoal":"333a38","Frame seam":"535450","Deck top":"565950","Footplate edge":"66665a",
    "Tank dark":"33544c","Tank olive":"456e59","Tank light":"5f8669","Tank shadow":"2a4740",
    "Lining black":"314839","Lining brass":"c4a162","Plate brass":"bf9b55","Plate patina":"8b7049",
    "Rod polished":"a4a59a","Rod shade":"676d66","Cylinder cover":"5d655e",
    "Wheel maroon":"803d36","Wheel maroon light":"985348","Tyre steel":"747d79","Flange dark":"505654",
    "Buffer red":"a04a3d","Buffer vermilion":"b66350","Buffer soot":"3e4543","Iron bright":"90988e",
    "Copper pipe":"a27348","Copper shadow":"754e3b","Cream glass":"d7c9a0","Glass dark":"31444a",
    "Glass mid":"63848a","Glass pale":"86a09d","Cab inside":"604738","Ash coal":"3d3933",
    "Coal black":"242927","Coal highlight":"4b4c43","Grille gap":"262d2c","Number ink":"4a4232",
    "Black slate":"465253","Cab eave":"6d7167","Tank oxide":"52715a","Cream tag":"cfbf9c",
}
wag.P={k:i for i,k in enumerate(P)}
rail.COLORS[:]=P.values()
slab=wag.slab
circle=wag.circular
face=wag.faces_xz


def profile_tube(m,n,rows,axis,center,palette,nseg=28,cap0=True,cap1=True):
    # Lathe profile along an author-space coordinate axis.
    maps={"x":lambda t,a,b:(t,a,b),"z":lambda t,a,b:(b,t,a),"h":lambda t,a,b:(a,b,t)}
    rings=[]
    for level,r in rows:
        ring=[]
        for i in range(nseg):
            a=i*tau/nseg
            ring.append(tuple(t+o for t,o in zip(maps[axis](level,r*cos(a),r*sin(a)),center)))
        rings.append(ring)
    if cap0:m.face(n,wag.P[palette[0]],rings[0][::-1])
    if cap1:m.face(n,wag.P[palette[-1]],rings[-1])
    for row,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(nseg):
            j=(i+1)%nseg
            color=palette[min(len(palette)-1,row)]
            m.face(n,wag.P[color],(a[i],a[j],b[j],b[i]))


def pipe(m,n,c,a,b,r=.008,N=10):
    a,b=Vector(a),Vector(b)
    delta=(b-a).normalized()
    u=delta.cross(Vector((0,0,1) if abs(delta.z)<.8 else (1,0,0))).normalized()
    v=delta.cross(u).normalized()
    ring=lambda p:[tuple(p+r*(u*cos(i*tau/N)+v*sin(i*tau/N))) for i in range(N)]
    l,h=ring(a),ring(b)
    m.face(n,wag.P[c],l[::-1]);m.face(n,wag.P[c],h)
    for i in range(N):
        j=(i+1)%N
        m.face(n,wag.P[c],(l[i],l[j],h[j],h[i]))


def side(m,n,c,s,z,h,w,height,x=.204,t=.008,r=.004):
    slab(m,n,c,s*x,z,t,w,h,h+height,r)


def beam(m,n,c,x,g,h,t,d):
    # Directional outside rods/spokes, plate thickness measured along X.
    za,ha=g;zb,hb=h;el=((zb-za)**2+(hb-ha)**2)**.5
    nz,nh=(ha-hb)/el*(t/2),(zb-za)/el*(t/2)
    cross=((za+nz,ha+nh),(za-nz,ha-nh),(zb-nz,hb-nh),(zb+nz,hb+nh))
    a=[(x-d/2,p,q) for p,q in cross];b=[(x+d/2,p,q) for p,q in cross]
    m.face(n,wag.P[c],a[::-1]);m.face(n,wag.P[c],b)
    for i in range(4):
        j=(i+1)%4
        m.face(n,wag.P[c],(a[i],a[j],b[j],b[i]))


def frame(m):
    body=wag.rect(0,-.004,.404,.866,.039)
    face(m,"Three-axle plate locomotive frame","Frame charcoal",body,.100,.205,"Frame seam")
    slab(m,"Continuous footplate with shaped corners","Deck top",0,-.010,.440,.871,.204,.243,.042,"Footplate edge")
    for sign in (-1,1):
        side(m,"Red-lined frame fascia","Buffer red",sign,-.005,.211,.773,.010,.220,.004)
        for z in AXLES:
            side(m,"Three axle horn-block covers","Frame seam",sign,z,.118,.077,.081,.142,.029)
            for j in range(3):
                side(m,"Laminated leaf spring","Cylinder cover",sign,z,.177+.008*j,.092+j*.010,.005,.163,.028)
        for z in (-.37,.325):
            side(m,"Engineer footstep hanger","Frame charcoal",sign,z,.115,.052,.103,.198,.018)
            side(m,"Checkerplate cab footstep","Footplate edge",sign,z,.108,.072,.014,.222,.053)
            side(m,"Lower safety cab step","Footplate edge",sign,z,.068,.058,.012,.218,.043)

    for sign in (-1,1):
        slab(m,"Red locomotive buffer beams","Buffer red",0,sign*.435,.414,.036,.135,.246,.012,"Buffer vermilion")
        slab(m,"Buffer beam identification strip","Buffer vermilion",0,sign*.454,.299,.003,.208,.215,.001)
        for x in (-.158,.158):
            profile_tube(m,"Spring buffers and polished faces",[(lo,r) for lo,r in sorted(
              [(sign*.452,.026),(sign*.461,.028),(sign*.469,.019),(sign*.473,.033),(sign*.481,.032)])],
              "z",(x,0,.174),("Buffer soot","Iron bright","Buffer soot","Cylinder cover"),18)
            for j in (-1,1):
                circle(m,"Buffer beam bolts","Iron bright",(x+j*.028,sign*.454,.216),.006,"z",-.003,.003,8)
        slab(m,"Knuckle draft gear pocket","Frame charcoal",0,sign*.441,.110,.031,.121,.187,.012)
        slab(m,"Knuckle drawbar","Buffer soot",0,sign*.466,.064,.034,.136,.180,.008)
        slab(m,"Coupler knuckles","Cylinder cover",0,sign*.483,.087,.032,.1305,.1835,.009)
        for x in (-.082,.083):
            pipe(m,"Brake hoses","Cast soot",(x,sign*.459,.165),(x+.012,sign*.474,.104),.008)
            circle(m,"Brake pipe end fittings","Copper shadow",(x+.012,sign*.474,.104),.011,"h",-.004,.003)
        for x in (-.031,.031):
            slab(m,"Headstock drawbar straps","Frame charcoal",x,sign*.455,.010,.009,.151,.204,.002)


def gear(m,phase=0):
    for z in AXLES:
        circle(m,"Forged through axles","Flange dark",(0,z,RADIUS),.018,"x",-.203,.203,12)
        for s in (-1,1):
            x=s*.212
            suffix="L" if s<0 else "R"
            # Closed annular tyres and flanges leave true open windows between spokes.
            profile_tube(m,"Rolling tread "+suffix,
                [(-.024,.080),(-.024,RADIUS),(.024,RADIUS),(.024,.080),(-.024,.080)],
                "x",(x,z,RADIUS),("Tyre steel",),24,False,False)
            a,b=sorted((-s*.040,-s*.034))
            profile_tube(m,"Inner flange lip",[(a,.078),(a,.110),(b,.110),(b,.078),(a,.078)],
                         "x",(x,z,RADIUS),("Flange dark",),24,False,False)
            # Annular inner tyre wall keeps all eleven openings visibly clear.
            for seg in range(22):
                a=seg*tau/22;b=(seg+1)*tau/22
                ring=[(x+s*.0243,z+r*cos(t),RADIUS+r*sin(t)) for t,r in (
                       (a,.081),(a,.098),(b,.098),(b,.081))]
                m.face("Rim and wheel cheek",wag.P["Wheel maroon"],ring if s>0 else ring[::-1])
            # A smaller wheel web is recessed inside the spoke volumes.
            # The openings read black only where the inboard frame actually sits.
            for i in range(11):
                t=i*tau/11+phase+(pi/2 if s>0 else 0)
                a=(z+.019*cos(t),RADIUS+.019*sin(t))
                b=(z+.084*cos(t),RADIUS+.084*sin(t))
                beam(m,"Individual spoked driver castings","Wheel maroon light" if i%3 else "Wheel maroon",
                     x+s*.018,a,b,.010,.015)
            circle(m,"Wheel center bosses","Wheel maroon",(x+s*.025,z,RADIUS),.029,"x",-.009,.009,18)
            circle(m,"Machined hub covers","Iron bright",(x+s*.031,z,RADIUS),.014,"x",-.006,.006,14)
            t=phase+(pi/2 if s>0 else 0)
            a=t+pi
            plate=[(x+s*.0245,z+radius*cos(q),RADIUS+radius*sin(q)) for q,radius in (
                (a-.65,.035),(a-.54,.084),(a-.22,.088),(a+.24,.088),(a+.58,.082),(a+.65,.035))]
            m.face("Driving wheel cranked counterweights",wag.P["Wheel maroon"],plate if s>0 else plate[::-1])
    for s in (-1,1):
        ra=.044;t=phase+(pi/2 if s>0 else 0)
        pins=[(z+ra*cos(t),RADIUS+ra*sin(t)) for z in AXLES]
        for z,h in pins:
            circle(m,"Coupling rod bronze crank pins","Plate brass",(s*.247,z,h),.018,"x",-.007,.007,12)
            circle(m,"Retaining crank pin cap","Rod shade",(s*.260,z,h),.012,"x",-.004,.004,12)
        beam(m,"Continuous 0-6-0 coupling rods","Rod polished",s*.247,pins[0],pins[-1],.024,.014)
        # Deep fluted top edge is highlighted individually, not painted on.
        a=(pins[0][0],pins[0][1]+.007);b=(pins[-1][0],pins[-1][1]+.007)
        beam(m,"Forged coupling rod top ridge","Iron bright",s*.254,a,b,.004,.003)
        start=(-.317,.148)
        px,pz=start[0]+.019*sin(t),start[1]
        beam(m,"Crosshead main piston connecting rod","Rod shade",s*.254,(px,pz),pins[1],.022,.009)
        beam(m,"Connecting rod polished web","Rod polished",s*.259,(px,pz),pins[1],.009,.005)
        pipe(m,"Exposed chrome piston rod","Iron bright",(s*.242,-.383,.148),(s*.242,px,.148),.009)
        side(m,"Crosshead guide blocks","Rod shade",s,px,.131,.037,.039,.243,.030)
        profile_tube(m,"Outboard steam cylinders",[
             (-.410,.029),(-.405,.040),(-.395,.044),(-.345,.044),(-.335,.040),(-.327,.030)],
             "z",(s*.184,0,.153),("Cylinder cover","Smokebox edge","Frame seam","Cylinder cover","Frame seam"),18)
        for i in range(6):
            a=tau*i/6
            circle(m,"Cylinder cover nuts","Iron bright",(s*.184+.027*cos(a),-.409,.153+.027*sin(a)),
                   .0048,"z",-.004,.002,8)


def boiler(m):
    # Boiler, firebox, and turned smokebox jamb. Their stepped metal flanges
    # are solid concentric profiles, with curved rather than box silhouette.
    profile_tube(m,"Rolled steel boiler barrel",[(-.280,.113),(-.276,.126),(-.231,.132),
      (.132,.132),(.145,.141),(.167,.139),(.214,.121)],"z",BOILER,
      ("Tank shadow","Tank dark","Tank olive","Firebox","Firebox","Tank dark"),36)
    for z in (-.201,-.033,.099):
        profile_tube(m,"Rolled boiler binding rings",[(z-.007,.132),(z-.004,.137),(z+.004,.137),(z+.007,.132)],
                     "z",(0,0,.470),("Firebox","Tank light","Tank dark"),32,False,False)
    profile_tube(m,"Riveted front smokebox and door dome",
       [(-.408,.064),(-.405,.089),(-.397,.113),(-.385,.130),(-.368,.136),(-.310,.135),(-.292,.131)],
       "z",(0,0,.470),("Smokebox patina","Cast soot","Smokebox edge","Cast soot","Cast soot","Smokebox edge"),36)
    profile_tube(m,"Smoke door concentric seating ring",[(-.402,.106),(-.399,.114),(-.392,.114)],
       "z",(0,0,.470),("Smokebox edge","Smokebox patina"),36,False,False)
    for i in range(18):
        a=tau*i/18
        circle(m,"Smoke door circumference rivet heads","Cylinder cover",(.115*cos(a),-.395,.470+.115*sin(a)),
               .0038,"z",-.0035,.003,8)
    for h in (.427,.515):
        slab(m,"Smokebox door hinge straps","Smokebox edge",-.081,-.405,.064,.014,h,h+.012,.003)
        pipe(m,"Door hinge barrels","Cylinder cover",(-.115,-.411,h-.004),(-.115,-.411,h+.017),.007)
    circle(m,"Central smoke door lock bonnet","Cylinder cover",(0,-.411,.470),.025,"z",-.011,.011,16)
    pipe(m,"Smokebox central lock cross handles","Iron bright",(-.034,-.424,.470),(.030,-.424,.470),.0045)
    pipe(m,"Smokebox central lock cross handles","Iron bright",(0,-.424,.445),(0,-.424,.494),.0045)
    slab(m,"Raised upper smokebox numberboard","Cast soot",0,-.409,.067,.012,.529,.554,.005)
    slab(m,"Plate numbers on smoke door","Cream tag",-.012,-.416,.006,.004,.534,.549,.001)
    slab(m,"Plate numbers on smoke door","Cream tag",.006,-.417,.010,.006,.536,.548,.001)
    profile_tube(m,"Flared cast chimney and open lip",[
        (.560,.057),(.592,.056),(.614,.040),(.648,.031),(.694,.037),(.705,.049),(.720,.050),
        (.725,.045),(.7255,.032),(.711,.030),(.700,.030)
    ],"h",(0,-.352,0),("Smokebox edge","Cast soot","Smokebox patina","Cast soot","Smokebox edge",
         "Cast soot","Smokebox edge","Cast soot","Grille gap","Grille gap"),30,True,False)
    profile_tube(m,"Embellished brass dome",[
        (.578,.055),(.599,.062),(.615,.057),(.647,.047),(.664,.035),(.673,.019),(.676,.007)
    ],"h",(0,-.110,0),("Plate patina","Plate brass","Plate patina","Plate brass","Plate brass","Lining brass"),28)
    for s in (-1,1):
        # Handrail stays along the exposed boiler shoulder.
        pipe(m,"Boiler polished handrails","Iron bright",(s*.142,-.265,.524),(s*.143,.145,.526),.004)
        for z in (-.249,-.107,.064,.133):
            pipe(m,"Handrail stay bosses","Cylinder cover",(s*.113,z,.523),(s*.142,z,.524),.005)
        pipe(m,"Feed pipe to smokebox","Copper pipe",(s*.145,-.264,.443),(s*.165,-.339,.391),.006)
        pipe(m,"Feed pipe downpipe","Copper shadow",(s*.165,-.339,.391),(s*.163,-.351,.252),.006)
    profile_tube(m,"Brass whistle base and stem",[(.630,.016),(.653,.014),(.663,.011),(.701,.010),(.706,.014)],
                 "h",(.060,.173,0),("Plate patina","Copper shadow","Plate brass","Lining brass"),14)
    for x in (-.030,.014):
        profile_tube(m,"Pair of safety valves",[(.588,.018),(.629,.015),(.644,.016),(.647,.012)],
                    "h",(x,.145,0),("Cylinder cover","Plate brass","Lining brass"),16)

DIGITS={
  "K":("1001","1010","1100","1010","1001"),"P":("1110","1001","1110","1000","1000"),
  "T":("1111","0110","0110","0110","0110"),"0":("0110","1001","1001","1001","0110"),
  "1":("0010","0110","0010","0010","0111"),
}
def mark(m,sign,letters,z,h,x=.215,sz=.0043):
    midpoint=(len(letters)*5-2)/2
    for j,l in enumerate(letters):
        for row,line in enumerate(DIGITS[l]):
            for k,p in enumerate(line):
                if p=="1":
                    c=z+(j*5+k-midpoint)*sz*sign
                    side(m,"Raised lettering cut from brass","Number ink",sign,c,h+(4-row)*sz,sz*.95,sz*.95,x,.0016,.00015)

def tank(m):
    for s in (-1,1):
        contour=wag.rect(s*.154,-.044,.116,.409,.020)
        face(m,"Paired sculpted side water tanks","Tank olive",contour,.252,.487,"Tank light")
        face(m,"Rolled and sloping tank shoulders","Tank light",wag.rect(s*.150,-.044,.108,.397,.017),
             .486,.503,"Tank light")
        for v,w,b in ((-.186,.083,.020),(-.045,.152,.020),(.090,.082,.022)):
            side(m,"Riveted water tank body panels","Tank oxide",s,v,.273,w,.189,.209,.004,b)
        # A narrow lined border, recessed below the reflective nameplate.
        for h in (.278,.457):
            side(m,"Fine brass panel lining","Lining brass",s,-.041,h,.363,.005,.213,.003)
        for z in (-.222,.139):
            side(m,"Fine brass panel lining","Tank shadow",s,z,.289,.004,.163,.213,.004)
            for j in range(7):
                circle(m,"Water tank and bunker panel rivets","Tank light",(s*.214,z,.300+.022*j),.0026,"x",-.002,.002,7)
        side(m,"Raised polished works plates","Plate patina",s,-.076,.365,.100,.048,.214,.008,.009)
        side(m,"Raised polished works plates","Lining brass",s,-.076,.368,.092,.041,.219,.003,.007)
        mark(m,s,"KPT",-.076,.377,x=.2211)
        side(m,"Small road number plaque","Plate brass",s,.077,.300,.063,.032,.215,.005)
        mark(m,s,"01",.077,.307,x=.2197,sz=.0038)
        profile_tube(m,"Tank filler inspection caps",[(.500,.022),(.510,.026),(.520,.025),(.523,.018)],
                     "h",(s*.159,.086,0),("Tank dark","Plate patina","Lining brass"),18)
        pipe(m,"Tank filler handles","Iron bright",(s*.169,.074,.525),(s*.169,.101,.525),.004)
        pipe(m,"Tank top handrails","Iron bright",(s*.198,-.217,.520),(s*.199,.050,.520),.0035)
        for z in (-.177,-.06,.029):
            pipe(m,"Tank top handrail lugs","Tank light",(s*.198,z,.501),(s*.198,z,.520),.005)


def cab(m):
    # A true hollow assembly. Jambs and roof carry the weather protection;
    # side entry and small spectacle windows are not decals on a solid box.
    slab(m,"Engineer cab floor","Cab inside",0,.244,.390,.252,.225,.246,.017)
    slab(m,"Rear cab lower apron","Tank dark",0,.337,.383,.023,.258,.548,.009)
    slab(m,"Forward cab lower wall","Tank dark",0,.138,.390,.026,.253,.495,.012)
    for s in (-1,1):
        front=.131
        for z,h,w,hei in ((.150,.467,.043,.203),(.303,.294,.040,.327),(.217,.658,.128,.016),(.228,.672,.166,.014)):
            side(m,"Molded cab frames and quarter panels","Tank dark",s,z,h,w,hei,.185,.034,.009)
        side(m,"Cab doorway reveal","Frame seam",s,.234,.654,.108,.016,.203,.008,.004)
        side(m,"Cab bottom rail","Tank light",s,.228,.238,.133,.014,.204,.007)
        side(m,"Side cab small forward glazing","Glass dark",s,.169,.550,.030,.070,.2039,.004,.006)
        side(m,"Glazing catchlights","Glass mid",s,.168,.563,.006,.043,.2064,.001,.001)
        for z in (.151,.281):
            pipe(m,"Footplate crew grab irons","Iron bright",(s*.207,z,.401),(s*.207,z,.567),.0043)
            for h in (.401,.566):
                pipe(m,"Crew handrail mounting studs","Cylinder cover",(s*.197,z,h),(s*.209,z,h),.0047)
        # Shallow front-facing spectacles above the boiler shoulder.
        x=s*.127
        for z in (front,.350):
            height=.594
            circle(m,"Brass cab spectacle frames","Plate patina",(x,z,height),.036,"z",-.010,.010,20)
            circle(m,"Cab tinted window glass","Glass dark",(x,z-.011 if z<.2 else z+.011,height),.028,
                  "z",-.001,.001,20)
            for h in (.599,.613):
                pipe(m,"Cab window thin interior rail","Glass mid",(x-.016,z-.013 if z<.2 else z+.013,h),
                     (x+.012,z-.013 if z<.2 else z+.013,h),.0017)
        slab(m,"Rear window corner steel posts","Tank dark",s*.174,.340,.049,.026,.534,.692,.012)
        slab(m,"Spectacle dinted standing seams","Tank olive",s*.113,.345,.075,.017,.633,.672,.004)
        # External chassis trim and boiler rivets are distinct native shadows.
        side(m,"Cab side panel gold waist lining","Lining brass",s,.289,.493,.077,.005,.206,.003)
        profile_tube(m,"Small floor cab lever",[(.263,.005),(.311,.004),(.339,.009),(.351,.005)],
                     "h",(s*.096,.235,0),("Cab inside","Copper pipe","Rod shade"),12)
        pipe(m,"Cab water top fittings","Copper pipe",(s*.150,.211,.279),(s*.155,.267,.279),.006)
    slab(m,"Central cab back sheet","Tank olive",0,.336,.168,.021,.536,.696,.010)
    slab(m,"Cab roof fascia","Tank light",0,.135,.378,.020,.662,.680,.014)
    points=[(.214*cos(i*pi/18),.644+.095*sin(i*pi/18)) for i in range(19)]
    for j in range(18):
        (x,h),(x1,h1)=points[j:j+2]
        # The forward roof has a curved steel header below the projecting
        # eave; use the arch against the rectangle instead of a floating roof.
        if min(h,h1)>.669:
            p=((x,.137,.667),(x1,.137,.667),(x1,.137,h1-.008),(x,.137,h-.008))
            m.face("Curved cab front steel header",wag.P["Tank dark"],p[::-1])
        clr=("Cab eave" if j in (0,17) else ("Black slate" if j in (4,10,14) else "Smokebox edge"))
        m.face("Arched zinc cab roof",wag.P[clr],((x,.364,h),(x1,.364,h1),(x1,.108,h1),(x,.108,h)))
        m.face("Inside barrel roof skin",wag.P["Cab inside"],((x,.108,h-.012),(x1,.108,h1-.012),
                    (x1,.364,h1-.012),(x,.364,h-.012)))
        for z in (.107,.366):
            pts=((x,z,h-.014),(x1,z,h1-.014),(x1,z,h1+.002),(x,z,h+.002))
            m.face("Roof rolled drip edges",wag.P["Cab eave"],pts if z>.2 else pts[::-1])
    slab(m,"Padded hinged roof vent","Smokebox edge",0,.235,.130,.110,.730,.745,.012)
    slab(m,"Brass roof vent sliders","Cab eave",0,.236,.077,.087,.744,.749,.009)
    # Open rear bunker fed from the cab floor. Coal is a loose irregular pile.
    slab(m,"Bunker bottom steel chute","Tank shadow",0,.394,.377,.110,.242,.293,.009)
    slab(m,"Bunker rear chamfered lip","Tank olive",0,.438,.389,.032,.254,.455,.010)
    slab(m,"Bunker rear top stiffening","Tank light",0,.445,.385,.012,.452,.464,.005)
    for s in (-1,1):
        slab(m,"Bunker return flank","Tank dark",s*.179,.382,.040,.132,.263,.469,.009)
        slab(m,"Humid bunker inner seams","Tank olive",s*.182,.385,.036,.125,.454,.473,.007)
        for j in range(3):
            circle(m,"Bunker perimeter rivet rows","Frame seam",(s*.195,.412,.349+.020*j),.003,"x",-.003,.003,8)
        pipe(m,"Rear engineer handrails","Iron bright",(s*.135,.451,.303),(s*.137,.451,.440),.004)
        for h in (.305,.436):
            pipe(m,"Rear rail solder seams","Cylinder cover",(s*.136,.443,h),(s*.136,.452,h),.0045)
    for i in range(23):
        x=((i*37)%79/78-.5)*.304
        z=.369+(i*19)%30/30*.054
        dome=.439+.043*(1-abs(x)/.17)*(1-abs(z-.399)/.07)
        ring=[(x+(.015+(i%4)*.004)*cos(a),z+.014*sin(a),dome-.024) for a in (0,1.2,2.42,3.7,5.0)]
        tip=(x+.007*cos(i),z+.006*sin(i),dome+(i%3)*.005)
        for j in range(len(ring)):
            k=(j+1)%len(ring)
            m.face("Visible lumps in rear coal bunker",wag.P[("Ash coal","Coal black","Coal highlight")[(i+2*j)%3]],
                   (ring[j],ring[k],tip))


def lamps(m):
    for z in (-.376,.424):
        facing=-1 if z<0 else 1
        x=0 if facing<0 else -.092
        slab(m,"Lamp iron stand and bracket","Cast soot",x,z,.071,.046,.242,.263,.009)
        slab(m,"Old sealed lantern body","Cylinder cover",x,z,.061,.041,.258,.321,.008)
        xz=(x,z+facing*.019,.288)
        circle(m,"Cab front and tail lamp brass bezel","Lining brass",xz,.024,"z",-.006,.006,18)
        circle(m,"Lamp thick bullseye lens","Cream glass" if facing<0 else "Buffer vermilion",
               (x,xz[1]+facing*.006,.288),.017,"z",-.004,.004,16)
        pipe(m,"Lamp lifting handles","Cylinder cover",(x-.015,z,.329),(x+.015,z,.329),.0033)
        for u in (-.015,.015):
            pipe(m,"Lamp lifting-handle mount","Cast soot",(x+u,z,.321),(x+u,z,.329),.0033)


def build():
    m=rail.Mesh(rail.terrain_height(0))
    frame(m)
    gear(m)
    boiler(m)
    tank(m)
    cab(m)
    lamps(m)
    def body_profile(_,x,z,h):
        # Keep the frame, tread contacts, wheel centres, and coupler
        # envelope fixed. Shrink only the envelope above the footplate.
        if h<=.246:
            return x,z,h
        width=1-.055*min(1,(h-.246)/.100)
        return x*width,z,.246+(h-.246)*.73
    return rail.reprofile(m,body_profile)


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(c)*8 for c in P.values())
    payload=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(P),8,8,2,0,0,0))
    payload+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (rail.TEXTURES/(NAME+".png")).write_bytes(payload)


def render_setup(scene,collection):
    rail.instance(scene,collection,0,0)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.016))
    m=bpy.data.materials.new("Backdrop — slate daylight")
    m.diffuse_color=(.175,.215,.205,1)
    bpy.context.object.data.materials.append(m)
    bpy.ops.object.camera_add(location=(1.45,-2.25,1.13))
    c=bpy.context.object
    c.rotation_euler=(Vector((0,.0,.355))-c.location).to_track_quat("-Z","Y").to_euler()
    c.data.type="ORTHO";c.data.ortho_scale=1.5
    scene.camera=c
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1480;scene.render.resolution_y=1000
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.24
    scene.display.shading.cavity_valley_factor=1.30
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Cool Atlantic light")
    scene.world.color=(.19,.228,.27)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Kirby Paul Tank, original 0-6-0T"
    mats=rail.materials()
    for i,name in enumerate(P):
        mats[i].name=name
    m=build()
    collection=rail.stash(m,mats,"01 Kirby Paul Tank — complete 0-6-0T")
    rail.export_obj(rail.MODELS/(NAME+".obj"),wag.local_obj(m))
    atlas()
    render_setup(scene,collection)
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art"/"kirby_paul_tank.blend"),compress=True)
    if path:=os.getenv("KIRBY_ART_RENDER"):
        scene.render.filepath=path
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()
