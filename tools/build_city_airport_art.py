#!/usr/bin/env python3
"""Original native stock 16.0-RC1 City Airport, reconstructed after staged disk loss."""
from math import cos,sin,tau,hypot
from pathlib import Path
import os,sys,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_small_airport_art as S
import bpy
from mathutils import Vector as V

R,H=S.RAIL,S.H
B,T=H.box,H.tube
PAL=dict(foundation="7d837f", slate="425667", dark_slate="304350", slate_rib="637381",
    glazed="698e99", glass_light="a9c0bf", glass_dark="3a5d6e", ochre="b5966d",board="d4c8a8",
    bone="f4e8ce", wood="6b5949", timber="887761",brick="a37462",dark_brick="996a59",pale_brick="b88b78",
    mortar="b9a999", jamb="566a68", dark_green="455c5b",teal="507c79",bright_teal="7da39a",steel="82999f",
    dark_metal="494f57",bench="936c59",concrete="a29e91",concrete_l="aaa79e",concrete_d="97958d",
    concrete_seal="797e77", gravel="888678",gravel_l="a09d8b",gravel_d="727468",runway="4e5357",
    runway_l="55595e",runway_d="4a5054",asphalt_joint="41494d",paint="e9e7d9",paint_shadow="cac8b6",
    yellow="dbc05b",red="ad4e48",rose="c47d58",orange="de9458",flag_bone="e4d8bf",chalk="a0b4aa",equipment="586b72",
    gauge="9babac",limestone="b2ad9b",stucco="d1cbbc",apron_blue="718793",white_metal="c2c9c5",ivory_band="e0d6b8",
    silver_fence="879e9a",green_glass="5f898f",roof_zinc="536976",concrete_shade="888d87",controlled_blue="365e7a",
    amber="dcb86a",burnt_taxi="a78a56",taxi_charcoal="646968",red_fixed="aa413d",radar_white="bdc6ba",
    radar_gold="998259",grass_low="798667",forecourt="b0aba0",paving_dark="6f7979",copper="627e79")
S.PAL=H.PALETTE=PAL
S.P=H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
face,rect,line=S.face,S.rect,S.line
S.DIGITS.update({"3":("11110","00001","00001","01110","00001","00001","11110"),
                 "P":("11110","11011","11011","11110","11000","11000","11000"),
                 "T":("11111","00100","00100","00100","00100","00100","00100")})
M=(("BUILDING_1","APRON_FENCE_NW","STAND_1","APRON_FENCE_NW","APRON_FENCE_NW","DEPOT_SE"),
   ("BUILDING_2","PIER","ROUND_TERMINAL","STAND_PIER_NE","APRON","APRON_FENCE_SW"),
   ("BUILDING_3","STAND","PIER_NW_NE","APRON_S","APRON_HOR","APRON_N_FENCE_SW"),
   ("RADIO_TOWER_FENCE_NE","APRON_W","APRON_VER_CROSSING_S","APRON_HOR_CROSSING_E","ARPON_N","TOWER_FENCE_SW"),
   ("EMPTY_FENCE_NE","APRON_S","APRON_HOR_CROSSING_W","APRON_VER_CROSSING_N","APRON_E","RADAR_GRASS_FENCE_SW"),
   ("RUNWAY_END_FENCE_SE","RUNWAY_1","RUNWAY_2","RUNWAY_3","RUNWAY_4","RUNWAY_END_FENCE_SE"))
def pos(x,z):return x/8-.5,z/8-.5
HANGAR=pos(85,3)[0]
STANDS={1:pos(26,41),2:pos(56,22),3:pos(38,8)}
RW0,RW1=9.535,11.375
PAV,MARK=.006,.016
PORTAL=(8.890,11.350)

def drum(m,n,c,x,z,a,b,y0,y1,k=20,top=None):
    p=[(x+a*cos(tau*i/k),z+a*sin(tau*i/k),y0) for i in range(k)]
    q=[(x+b*cos(tau*i/k),z+b*sin(tau*i/k),y1) for i in range(k)]
    for i in range(k):
        j=(i+1)%k
        face(m,n,c,[p[i],p[j],q[j],q[i]])
        if top:face(m,n+" cap",top,[(x,z,y1),q[i],q[j]])

def ring(m,n,c,x,z,r,y,w=.027,k=30):
    for i in range(k):
        a,b=[tau*j/k for j in (i,i+1)]
        face(m,n,c,[(x+r*cos(a),z+r*sin(a),y),(x+r*cos(b),z+r*sin(b),y),
                     (x+(r-w)*cos(b),z+(r-w)*sin(b),y),(x+(r-w)*cos(a),z+(r-w)*sin(a),y)])

def dashed(m,n,c,a,b,width=.036,seg=.19,gap=.117,h=MARK):
    d=hypot(a[0]-b[0],a[1]-b[1])
    if d<1e-8:return
    for i in range(max(1,int(d/(seg+gap)))):
        length=min(seg,d*.72)
        start=min((seg+gap)*i+gap*.3,d-length)
        move=lambda t:tuple(x+(y-x)*t/d for x,y in zip(a,b))
        line(m,n,c,[move(start),move(start+length)],width,h)

def groundwork(m):
    for z in range(5):
        for x in range(6):
            a,b=2*x-.5,2*z-.5
            k=M[z][x]
            if k.startswith(("EMPTY","RADIO","RADAR")):continue
            kind="Landside stone forecourt slabs" if k.startswith("BUILDING") else "City stock concrete apron and taxi slabs"
            rect(m,kind,"forecourt" if k.startswith("BUILDING") else "concrete",a,a+2,b,b+2,PAV)
            for s in (0,.5,1,1.5):
                rect(m,"Fine transverse scored apron expansion joints","concrete_seal",a+s+.002,a+s+.007,b,b+2,.008)
            for s in (.5,1,1.5):
                rect(m,"Fine longitudinal scored apron expansion joints","concrete_seal",a,a+2,b+s+.001,b+s+.007,.0081)
    hub=pos(44,63);branch=pos(58,71);entry=pos(72,85);inbound=pos(36,71)
    e=pos(85,22);east=pos(80,27);north=pos(65,6)
    paths=((hub,branch,entry),(pos(20,87),inbound,hub),(hub,e,(HANGAR,1.15)),
            (hub,STANDS[1]),(hub,east,north,STANDS[3]),(east,STANDS[2]),(e,east))
    for i,path in enumerate(paths):
        for j,(a,b) in enumerate(zip(path,path[1:])):
            dashed(m,"Separate stock taxi branches flush painted","yellow",a,b,h=MARK+i*.00010+j*.00001)
    for i,(x,z) in STANDS.items():
        rect(m,f"Exact stand {i} golden stop bar","yellow",x-.237,x+.237,z-.022,z+.022,MARK+.001)
        for dx in (-.86,.86):
            rect(m,f"Stand {i} white side envelopes","paint_shadow",x+dx-.012,x+dx+.012,z-.53,z+.53,MARK)
            rect(m,f"Stand {i} dashed airside equipment guides","burnt_taxi",x+dx-.072,x+dx+.072,z+.70,z+.74,MARK)
        S.lettering(m,f"Flat painted stand numeral {i}",str(i),(x,z+.55,MARK+.0005),.046,"north","yellow")
        for d in (-.49,.49):
            rect(m,"Short local keep-clear markings","burnt_taxi",x+d-.03,x+d+.03,z+.59,z+.91,MARK)
    x,z=pos(28,74)
    ring(m,"Helicopter touchdown ring at stock hold","paint_shadow",x,z,.39,MARK)
    S.lettering(m,"Helicopter touchdown H","H",(x,z,MARK+.0008),.055,"north","paint")
    ring(m,"City taxi hub maneuver courtesy ring","paint_shadow",*hub,.63,MARK+.0002,.011)
    rect(m,"Flush runway aggregate shoulders","gravel_l",-.5,11.5,9.5,11.5,.003)
    rect(m,"Continuous City runway wearing course","runway",-.5,11.5,RW0,RW1,.010)
    for i in range(1,16):
        x=-.5+i*.75
        rect(m,"Narrow transverse runway expansion score","asphalt_joint",x-.0025,x+.0025,RW0,RW1,.011)
    for z in (RW0+.081,RW1-.081):
        rect(m,"Continuous flush runway outer white trim","paint_shadow",-.474,11.474,z-.013,z+.013,.014)
    for i in range(15):
        x=.99+i*.644
        rect(m,"Broken center landing field line","paint",x,x+.297,10.238,10.262,MARK)
    for x,xt,course,rot in ((-.093,.325,"09","east"),(11.077,10.658,"27","west")):
        for z in (9.825,9.967,10.100,10.399,10.531,10.674):
            rect(m,"City threshold piano bars","paint",x-.185,x+.185,z-.026,z+.026,MARK)
        S.lettering(m,"Physically painted runway ordinals",course,(xt,10.25,MARK+.0003),.070,rot,"paint")
    for i in range(21):
        x=-.382+i*.588
        for z in (9.507,11.446):
            rect(m,"Flush inset edge light carrier","equipment",x-.021,x+.021,z-.013,z+.013,.0128)
            rect(m,"Inlaid lamp lens not a physical obstacle","bone",x-.010,x+.010,z-.009,z+.009,.013)
    for z in (8.993,9.169):
        rect(m,"Amber interrupted departure hold bars","yellow",entry[0]-.435,entry[0]+.435,z-.018,z+.018,MARK)
    for x in (-.453,11.453):
        for z in (11.440,11.478):
            rect(m,"Runway end fence recess safely flush","steel",x-.039,x+.039,z-.008,z+.008,.015)

def lamp(m,tag,x,z,h):
    B(m,tag+" shaded housing","dark_slate",x,z,.065,.064,h-.026,h+.035,.008)
    B(m,tag+" ivory deflector","bone",x,z,.048,.045,h-.032,h-.006,.004)

def terminal(m):
    for i,z in enumerate((.44,2.39,4.33)):
        x=.448
        h=(.865,.734,.823)[i]
        B(m,f"Civic terminal block {i+1} molded footing","foundation",x,z,1.617,1.49,.010,.125,.045)
        B(m,f"Civic terminal block {i+1} sandstone panels","limestone",x,z,1.465,1.424,.104,h,.044)
        for y in (.208,.438,.694):
            if y+.041<h:B(m,f"Terminal {i+1} horizontal tile reveal bands","ivory_band",x,z,1.507,1.464,y,y+.037,.017)
        for y in (.272,.493):
            for j in range(5):
                dz=-.511+.259*j
                for s in (-1,1):
                    xx=x+s*.736
                    B(m,"Original cream stone studio window surround","dark_slate",xx,z+dz,.019,.193,y,y+.156,.008)
                    B(m,"Original flush tinted terminal window panes","glazed",xx+s*.013,z+dz,.016,.166,y+.025,y+.139,.005)
                    B(m,"Original terminal blue overlapping window highlight","glass_light",xx+s*.025,z+dz,.009,.154,y+.108,y+.128,.005)
                    B(m,"Slim cream terminal window mullion","board",xx+s*.023,z+dz,.015,.012,y+.026,y+.137,.002)
            for dx in (-.49,-.238,.015,.267,.504):
                for s in (-1,1):
                    zz=z+s*.717
                    B(m,"Air terminal curtain glazing below cap","glazed",x+dx,zz,.185,.023,y,y+.136,.008)
                    B(m,"Art Deco facade window top bright reflection","glass_light",x+dx,zz+s*.017,.159,.010,y+.105,y+.129,.003)
        B(m,"Broad accent trim and terminal flat concrete overhang","ivory_band",x,z,1.555,1.523,h-.017,h+.046,.043)
        B(m,"Pitched-looking cobalt roof block with outline berm","roof_zinc",x,z,1.374,1.332,h+.03,h+.108,.031)
        B(m,"Original rectangular raised central bronze clerestory","teal",x+.04,z+.018,.53,.627,h+.093,h+.161,.026)
        B(m,"Diffuse frosted top glazing roof monitor","glass_dark",x+.04,z+.018,.439,.529,h+.153,h+.171,.011)
        B(m,"West covered entrance awning facing landside curb","teal",x-.674,z,.354,.684,.316,.377,.012)
        B(m,"Frosted street-level original double door cutout","glass_dark",x-.747,z,.013,.434,.102,.312,.003)
        B(m,"Street threshold and trim","concrete_shade",x-.807,z,.164,.496,.024,.074,.011)
        for dz in (-.315,.315):
            B(m,"Terminal support lintel columns","board",x-.769,z+dz,.048,.053,.059,.341,.006)
        for dz in (-.525,.525):lamp(m,"Vintage forecourt sconces",x-.747,z+dz,.304)
    rect(m,"Landside discrete asphalt surface outside airplane lanes","paving_dark",-.5,-.337,-.5,5.45,.014)
    B(m,"Low continuous outer curb along concourse","concrete_l",-.314,2.46,.045,5.78,.009,.049,.008)
    for z in (-.092,.075,1.44,1.61,3.55,3.72,4.97,5.14):
        rect(m,"Painted urban terminal pedestrian forecourt crossing","paint",-.5,-.329,z-.026,z+.026,.016)
    for name,x,z,dx,dz in (("West concourse boarding piers",2.46,2.365,2.56,.585),
                          ("South split twin enclosed boarding piers",4.606,3.588,.417,.750)):
        B(m,name+" low structural plinth","foundation",x,z,dx,dz,.009,.163,.020)
        B(m,name+" light blue panoramic windows","glazed",x,z,dx-.039,dz-.045,.139,.454,.020)
        B(m,name+" ivory roof overhang","ivory_band",x,z,dx+.038,dz+.042,.417,.483,.024)
        if dx>=dz:
            for i in range(1,int(dx/.205)+1):
                for zz in (z-dz*.5,z+dz*.5):
                    B(m,"Cream concourse curtain-wall mullion","ivory_band",x-dx/2+i*.205,zz,.025,.028,.128,.459,.003)
        else:
            for zz in (z-.255,z,z+.255):
                for xx in (x-dx*.5,x+dx*.5):
                    B(m,"Cream concourse curtain-wall mullion","ivory_band",xx,zz,.025,.021,.128,.457,.003)
        B(m,name+" brushed seam flashing","roof_zinc",x,z,dx*.963,dz*.965,.481,.501,.010)
    # Elevated east bridge clears the longest tail and the stock T2 turn.
    x,z=5.493,3.193
    B(m,"East cantilever protected passenger bridge underside","slate",x,z,.655,.442,.753,.799,.027)
    B(m,"East enclosed raised boarding pier green windows","glazed",x,z,.640,.430,.794,1.022,.023)
    B(m,"East protected passenger boarding pier cream roof","ivory_band",x,z,.690,.469,1.013,1.063,.016)
    for xx in (5.242,5.406,5.567,5.734):
        for zz in (z-.215,z+.215):
            B(m,"East elevated curtain wall mullion","ivory_band",xx,zz,.022,.021,.789,1.031,.003)
    B(m,"East jetty root supports on terminal side of taxi","limestone",5.151,z,.154,.388,.225,.794,.011)
    for yy in (.806,.834,.863):
        B(m,"Dedicated original jetty door framing","board",5.822,z,.018,.182,yy,yy+.023,.006)
    B(m,"Dedicated City passenger terrace slab","forecourt",2.014,.406,1.631,1.198,.009,.026,.032)
    rect(m,"Link from city lobby through paved terrace","forecourt",1.192,1.452,.188,.615,.026)
    B(m,"City terrace pedestrian canopy outside crowd frame","roof_zinc",1.353,.411,.364,.576,.373,.422,.025)
    B(m,"City terrace air terminal door","glass_dark",1.194,.412,.026,.312,.112,.340,.005)
    B(m,"City terrace door white lintel","ivory_band",1.220,.414,.049,.420,.321,.357,.005)
    for zz in (.145,.675):
        B(m,"Two shallow City lobby canopy supports","slate",1.510,zz,.038,.035,.025,.374,.006)
    for xx in (1.844,2.389):
        B(m,"City passenger waiting benches south of crowd frame","bench",xx,.928,.372,.104,.100,.133,.006)
        B(m,"City passenger waiting bench shade planks","copper",xx,.977,.378,.023,.125,.211,.004)
        for d in (-.133,.133):
            B(m,"City terrace dark metal bench foot","slate",xx+d,.933,.025,.087,.026,.108,.005)
    rect(m,"City terrace golden painted keep-clear bordering edge","yellow",2.712,2.728,-.091,.948,.027)
    x,z=4.404,2.390
    drum(m,"Round terminal lowest exposed foundation","foundation",x,z,.792,.792,.006,.084,24,"foundation")
    drum(m,"City round terminal cream perimeter pediment","ivory_band",x,z,.745,.736,.077,.188,24)
    for radius,a,b in ((.719,.192,.489),(.563,.513,.738),(.397,.761,.936)):
        drum(m,"Round terminal tint-wrapped stacked glass floors","glass_dark",x,z,radius,radius,a,b,28)
        for j in range(28):
            t=tau*j/28
            p=lambda ang,rr,yy:(x+rr*cos(ang),z+rr*sin(ang),yy)
            face(m,"Curved concourse inset glass highlights",("glazed","green_glass","glass_light")[(j%10)//4],
                [p(t+.025,radius+.005,a+.026),p(t+.113,radius+.005,a+.026),p(t+.113,radius+.005,b-.054),p(t+.025,radius+.005,b-.054)])
            xx,zz,_=p(t,radius,a+.008)
            B(m,"Fully vertical ivory pilasters between glass","board",xx,zz,.021,.021,a+.008,b-.009,.003)
        drum(m,"Stepped round terminal cream cap cornice","ivory_band",x,z,radius+.057,radius+.057,b-.014,b+.044,28,"limestone")
        drum(m,"Original blue bronze riveted parapet ring","roof_zinc",x,z,radius+.047,radius+.047,b+.021,b+.049,28)
    drum(m,"Round terminal copper dome cupola","copper",x,z,.250,.178,.982,1.105,20)
    drum(m,"Round terminal flattened blue cupola cap","teal",x,z,.178,.094,1.104,1.144,20,"roof_zinc")
    lamp(m,"Cupola building marker light",x,z,1.169)
    B(m,"Round terminal main station plate","controlled_blue",x,z+.745,.684,.043,.199,.299,.009)
    S.lettering(m,"Distinct facade CITY AIRPORT board","AIRPORT",(x,z+.769,.246),.016,"south","bone")
    B(m,"Short red safety cabinet beside concourse","red",4.041,3.094,.134,.087,.025,.197,.006)
    B(m,"Wall mounted apron directional plaque","ivory_band",4.041,3.142,.105,.011,.076,.120,.004)

def hangar(m):
    a,b=PORTAL
    x=(a+b)/2;z=.445
    for s,edge in ((-1,a),(1,b)):
        xx=edge+s*.043
        low=-.418
        high=.495 if s<0 else 1.30
        l=high-low;zz0=(low+high)/2
        B(m,"City hangar concrete side footings","foundation",xx,zz0,.106,l,.010,.096,.012)
        B(m,"City hangar opaque corrugated steel side walls","concrete_l",xx,zz0,.095,l-.012,.085,.918,.006)
        for i in range(int(l/.083)):
            zz=low+.04+i*.083
            for off in (-.049,.049):
                B(m,"City hangar embossed exterior corrugation","limestone",xx+off,zz,.006,.015,.101,.903,.002)
        for zz in (v for v in (-.369,-.03,.316,.668,1.044,1.28) if v<high-.014):
            B(m,"City hangar wall steel ribs","slate",xx,zz,.122,.034,.074,.965,.007)
        for zz in (v for v in (-.275,.20,.674,1.155) if v<high-.13):
            B(m,"Upper industrial clerestory side glazing","glazed",xx,zz,.106,.279,.674,.839,.005)
            B(m,"Outer narrow hangar silver window sill","white_metal",xx,zz,.112,.306,.653,.677,.004)
        zz=high-.053
        B(m,"Stowed split sliding steel door against flank","roof_zinc",xx,zz,.112,.079,.020,.849,.006)
        B(m,"Constant raised hangar corner yellow side abutment","yellow",xx,zz+.027,.116,.037,.083,.197,.003)
        if s<0:
            B(m,"West roof cantilever longitudinal steel girder","roof_zinc",xx,.873,.098,.863,.868,.958,.007)
            T(m,"West roof cantilever diagonal high web","slate",(xx,.488,.889),(xx,1.279,.937),.015,.014,6)
    for end in (-1,1):
        zz=z+end*.850
        B(m,"High City hangar open portal steel lintel","slate",x,zz,b-a+.19,.066,.855,.953,.009)
        B(m,"High City hangar gantry track","dark_metal",x,zz-end*.031,b-a+.18,.022,.844,.875,.004)
        S.gable_end(m,"City hangar original slate triangular gable",x,zz,2.666,.951,1.386,"limestone",end)
    S.gable(m,"Late art deco city airport hangar roof metal",x,z,2.692,1.82,.952,1.415,"slate","z")
    for i in range(11):
        zz=-.35+i*.158
        for side in (-1,1):
            def roof(x0,x1,z0,z1,h):
                def p(rx,rz):return (x+side*rx,rz,1.417-.456*rx/1.346+h)
                return [p(x0,z0),p(x1,z0),p(x1,z1),p(x0,z1)][::side]
            face(m,"Flush hangar standing seam roof press","white_metal",roof(.10,1.212,zz,zz+.018,0))
            if i in (1,3,5,7,9):face(m,"Alternating blue factory roof skylight panes","glazed",roof(.19,.922,zz+.037,zz+.124,.003))
    for zz in (-.29,.122,.534,.917,1.255):
        B(m,"Above-clearance visible portal tie truss","white_metal",x,zz,b-a+.082,.025,.826,.868,.004)
        for dx in (-1,1):
            T(m,"Diagonal roof joists with visible supports","roof_zinc",(x,zz,1.387),(x+dx*1.254,zz,.890),.015,.013,6)
    for xx in (x-.64,x+.64):lamp(m,"Under portal warm service lamp",xx,1.278,.822)
    B(m,"Porcelain hangar identity panel above portal","bone",x,1.317,.833,.030,1.026,1.194,.012)
    S.lettering(m,"Hangar white physical data badge","HANGAR",(x,1.336,1.110),.021,"south","slate")
    rect(m,"Flush recessed City hangar interior engine bay slab","concrete_shade",a,b,-.48,1.43,.0103)
    for xx in (a+.115,b-.115):
        rect(m,"Two low flattened City hangar guide bars","burnt_taxi",xx-.020,xx+.020,-.43,1.41,.015)
    for xx in (a+.045,b-.045):
        rect(m,"Painted pedestrian apron boundary hanger leads","paint_shadow",xx-.010,xx+.010,1.39,1.489,.0162)

def services(m):
    x,z=10.605,6.43
    B(m,"City air control tower broad deco square podium","foundation",x,z,.866,.839,.006,.137,.033)
    B(m,"Tower tinted glass ground service level","glass_dark",x,z,.756,.734,.103,.301,.021)
    for d in (-.277,-.092,.092,.277):
        for s in (-1,1):
            B(m,"Tower podium pilasters reveal","board",x+s*.381,z+d,.024,.030,.100,.304,.004)
            B(m,"Tower podium pilasters reveal","board",x+d,z+s*.367,.034,.023,.100,.304,.004)
    B(m,"Square tower cream plinth drip","ivory_band",x,z,.838,.820,.278,.332,.026)
    for name,c,a,b,y,f,k,top in (
        ("Tapered tall stock airport tower column","stucco",.224,.156,.311,1.080,12,None),
        ("Lower distinctive hexagonal tower cone","limestone",.190,.478,1.054,1.451,12,None),
        ("Tower bronze ring at control level","ivory_band",.492,.499,1.440,1.502,12,None),
        ("Panoramic high stock tower blue cockpit glass","glass_dark",.472,.455,1.497,1.817,12,None),
        ("Tall control cab mushroom roof","roof_zinc",.493,.447,1.810,1.901,12,"roof_zinc"),
        ("Layered upper cab mechanical penthouse","limestone",.322,.284,1.894,2.004,10,"roof_zinc")):
        drum(m,name,c,x,z,a,b,y,f,k,top)
    for i in range(12):
        a=tau*i/12;b=tau*(i+1)/12
        def q(t,r,h):return (x+r*cos(t),z+r*sin(t),h)
        face(m,"Control tower original glazing strips",("glass_light","glazed","green_glass")[i%3],
          [q(a+.041,.478,1.548),q(b-.041,.478,1.548),q(b-.041,.456,1.763),q(a+.041,.456,1.763)])
        T(m,"Slender metallic tower perimeter strut","slate",q(a,.481,1.493),q(a,.463,1.820),.012,.010,6)
    T(m,"Control tower surface radio mast","dark_metal",(x,z,1.998),(x,z,2.239),.017,.012,8)
    lamp(m,"Affixed fixed crimson tower beacon",x,z,2.243)
    for dx,dz in ((-.250,0),(.250,.105),(.044,-.196)):
        T(m,"Air traffic radio antenna pins","white_metal",(x+dx,z+dz,1.901),(x+dx,z+dz,2.097),.007,.006,6)
    x,z=10.72,8.397
    B(m,"East radar concrete service pad","concrete_d",x,z,.936,.879,.006,.062,.028)
    B(m,"Radar iron clipped equipment cabinet","equipment",x,z,.537,.452,.060,.339,.028)
    T(m,"Radar azimuth pivot post","white_metal",(x,z,.26),(x,z,1.008),.041,.045,10)
    for d in (-.235,-.141,-.047,.047,.141,.235):
        zz=z+.183-1.62*d*d
        T(m,"Individual vertical lattice radar dish hooped members","radar_white",(x+d,zz,.870),(x+d,zz+.041,1.154),.014,.013,6)
    for k in range(7):
        a=(k-3)*.076;b=a+.076
        for h in (.892,.957,1.023,1.088,1.149):
            T(m,"Each horizontal formed radar dish metal grid","radar_gold",
                (x+a,z+.194-1.62*a*a+(h-.892)*.13,h),(x+b,z+.194-1.62*b*b+(h-.892)*.13,h),.010,.009,6)
    T(m,"Pinned radar emitter upper feed","white_metal",(x,z-.057,1.029),(x,z+.288,1.031),.017,.010,8)
    x,z=.47,6.38
    B(m,"West stock radio mast concrete base","foundation",x,z,.601,.580,.006,.071,.023)
    for s in (-1,1):
        for dz in (-1,1):
            T(m,"Original radio mast independent tapered original supports","red_fixed",(x+s*.166,z+dz*.172,.055),
              (x+s*.044,z+dz*.039,1.587),.017,.011,8)
    for i in range(5):
        h=.17+.285*i;h2=h+.262
        w=.166-(h/1.6)*.116;ww=.166-(h2/1.6)*.116
        for s in (-1,1):
            for dz in (-1,1):
                T(m,"Paint alternating crossed radio mast wind bracing","white_metal" if i%2 else "red_fixed",
                  (x+s*w,z+dz*w,h),(x-s*ww,z+dz*ww,h2),.011,.007,6)
    T(m,"Radio mast lightning rod","white_metal",(x,z,1.57),(x,z,1.818),.013,.010,8)
    lamp(m,"Radio mast visibility marker",x,z,1.823)
    for side,x in (("West",-.374),("East",11.338)):
        for z0,z1 in ((5.632,7.40),(7.56,9.14)):
            for i in range(6):
                zz=z0+(z1-z0)*i/5
                B(m,side+" perimeter transport fence stanchions","steel",x,zz,.032,.042,.007,.244,.005)
            for h in (.078,.155,.213):
                B(m,side+" perimeter three understated guard rails","silver_fence",x,(z0+z1)*.5,.015,z1-z0+.011,h,h+.016,.003)
    for x0,x1 in ((1.56,3.44),(5.56,7.40),(7.56,8.84)):
        rect(m,"North stock inset fence shadow safe for wing overhang","steel",x0,x1,-.435,-.416,.012)
    for x,z in ((.415,8.94),(10.421,8.96)):
        B(m,"Small far-edge ground service power cabinet","equipment",x,z,.267,.165,.007,.212,.017)
        B(m,"Original equipment warning placard","yellow",x,z+.082,.183,.008,.127,.178,.004)

def tile(m,tx,tz):
    out=S.mesh()
    x,z=2*tx-.5,2*tz-.5
    for label,fs in m.parts.items():
        for ids,k in fs:
            poly=[m.vertices[label][i] for i in ids]
            for ax,at,sign in ((0,x,1),(0,x+2,-1),(1,z,1),(1,z+2,-1)):
                if not poly:break
                if sign<0 and (tx if ax==0 else tz)<5 and all(abs(p[ax]-at)<1.e-9 for p in poly):
                    poly=[];break
                poly=S.clip(poly,ax,at,sign)
            out.face(label,k,[(a-x-1,b-z-1,h) for a,b,h in poly])
    return out

def atlas():
    def chunk(t,p):return struct.pack(">I",len(p))+t+p+struct.pack(">I",zlib.crc32(t+p))
    c=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    (ROOT/"mods/luanttd_core/textures/bl_city_airport_atlas.png").write_bytes(b"\x89PNG\r\n\x1a\n"+
      chunk(b"IHDR",struct.pack(">IIBBBBB",len(PAL)*8,8,8,2,0,0,0))+
      chunk(b"IDAT",zlib.compress((b"\0"+c)*8,9))+chunk(b"IEND",b""))

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    s=bpy.context.scene;s.name="LuanTTD | Stock City Airport 6×6"
    s["datum"]="Grass top zero, overlay instance world ground+1, adjacent anchors 2 nodes."
    s["source"]="OpenTTD 16.0-RC1 _tile_table_city_0 and _airport_moving_data_city."
    s["hangar"]="Exact FTA H=(10.125,-.125), portal opens +Z; west roof cantilever spans apron beside 5,0."
    s["stands"]="T1=(2.75,4.625); T2=(6.5,2.25); T3=(4.25,.5)."
    s["waiting"]="Flat terrace +.026, local rectangle x 1.78–2.55 z .04–.78."
    s["tile_types"]="N at top; "+" / ".join(",".join(row) for row in M)
    m=S.mesh();mats=R.materials()
    for name,ma in zip(PAL,mats):ma.name=name.replace("_"," ").title()
    for name,fn in (("01 Apron slabs and flush runway paint",groundwork),("02 Land offices, rotunda and three gate branches",terminal),
                    ("03 Real open and cantilevered maintenance hangar",hangar),("04 ATC, mast, safety fences and service radar",services)):
        c=bpy.data.collections.new(name);s.collection.children.link(c)
        x=S.mesh();fn(x);fn(m);R.to_blender(x,c,mats)
    for z,row in enumerate(M):
        for x,kind in enumerate(row):
            p=ROOT/"mods/luanttd_core/models"/f"bl_city_airport_{x}_{z}.obj"
            R.export_obj(p,tile(m,x,z))
            p.write_text(f"# Original City Airport art tile {x},{z} APT_{kind}; tools/build_city_airport_art.py\n"+p.read_text().split("\n",1)[1])
    atlas()
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                a.spaces.active.shading.color_type="MATERIAL"
                v=a.spaces.active.region_3d
                v.view_location=V((5.5,5.3,.18));v.view_distance=17.5
                v.view_rotation=(V((5.5,5.3,.18))-V((14,16,11))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/city_airport.blend"),compress=True)
    if path:=os.getenv("CITY_AIRPORT_REVIEW"):review(s,Path(path))

def review(s,path):
    bpy.ops.mesh.primitive_plane_add(size=160,location=(5.5,5.5,-.006))
    grass=bpy.data.materials.new("Review only existing ground");grass.diffuse_color=(.178,.276,.107,1)
    bpy.context.object.data.materials.append(grass)
    cam=bpy.data.cameras.new("City survey");obj=bpy.data.objects.new("City survey",cam)
    s.collection.objects.link(obj);s.camera=obj;cam.type="ORTHO"
    s.render.engine="BLENDER_WORKBENCH"
    sh=s.display.shading
    sh.light="STUDIO";sh.studio_light="paint.sl";sh.color_type="MATERIAL";sh.show_shadows=True
    sh.show_cavity=True;sh.cavity_type="BOTH";sh.show_object_outline=False;sh.background_type="WORLD"
    s.world=bpy.data.worlds.new("City blue daylight");s.world.color=(.185,.228,.270)
    s.view_settings.view_transform="Standard";s.render.image_settings.file_format="JPEG"
    s.render.resolution_x=1152;s.render.resolution_y=880;s.render.resolution_percentage=100
    for label,start,look,scale in (("overhead",(5.5,5.5,19),(5.5,5.5,0),16.4),
         ("approach",(14.5,16.7,12.2),(5.5,5.5,.2),16.8),("apron",(12.2,4.63,1.62),(8.15,.7,.43),7.7),
         ("terminal",(8.65,6.93,1.82),(2.92,2.63,.33),8.25)):
        obj.location=start
        obj.rotation_euler=(0,0,0) if label=="overhead" else (V(look)-obj.location).to_track_quat("-Z","Y").to_euler()
        cam.ortho_scale=scale;s.render.filepath=str(path/f"city_{label}.jpg")
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":build()
