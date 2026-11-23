#!/usr/bin/env python3
"""Blender source for #146 Moreland Wood, #143 Goss Grain, #137 Foster Livestock."""
from math import cos,sin,pi,tau
from pathlib import Path
from random import Random
import bpy
from mathutils import Vector as V
import os,sys,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_ship_facility_art as H
from build_rail_wagon_art import local_obj
B,T,R=H.box,H.tube,H.rail
COL=dict(steel="4c565d",frame="354047",black="263139",tyre="262b2f",tread="40484c",rim="95a4a8",lug="65717a",
    blue="38678e",blue_low="284f71",blue_light="5f8fb1",blue_ridge="4d7fa4",blue_dark="3d6583",steel_cool="6c91a8",
    glass="425c6b",glint="8fadb7",glass_high="648492",seal="283b47",silver="adbfc5",alloy="8d9ea2",
    light="eee6d4",red="ba5148",amber="d08d45",tan="d4bf85",teal="5f8297",pale="8ea9b2",
    lip="aab7b7",grain_wall="82929c",grain_inner="626f79",grain_floor="57656a",grain1="d0a751",
    grain2="ddba61",grain3="c0994d",grain4="c39f56",grain5="e6c773",grain_depth="9f7836",
    stake="526976",stake_light="8c9da2",deck1="726252",deck2="887761",bark1="4d3a33",bark2="604839",
    bark3="755b4a",bark4="8b6a50",end1="cda471",end2="bd8e59",ring="9d7449",woodsplit="775742",strap="a89368",
    cloth="6e6050",roof="3c5062",roof_seam="304658",cage="658dad",cage_blue="7ba6c2",vent_dark="4b6c84",
    vent_light="87aac0",floor="4f5a60",rub="354654",ramp="537a96",latch="809aa8",warm="e0d1b5",
    caution="c9a35e",paint="b6c9c7",label="e0e0cf",iron="586a74")
P={k:i for i,k in enumerate(COL)}
H.P=P
R.COLORS[:]=COL.values()
assert len(P)==64
M="stock_moreland_wood_truck"
G="stock_goss_grain_truck"
F="stock_foster_livestock_van"
STOCK={M:(146,"Moreland Wood Truck",(-.535,.264,.536),.122),
       G:(143,"Goss Grain Truck",(-.485,.459),.119),
       F:(137,"Foster Livestock Van",(-.491,.451),.120)}
# Eight profile points to a section; three body silhouettes are distinct,
# from modern sloping Moreland to the short bluff hard square Goss shell.
CAB={
M:((-.805,.207,.200,.381),(-.781,.235,.195,.420),(-.739,.260,.194,.466),(-.680,.274,.190,.535),
   (-.609,.277,.191,.622),(-.563,.275,.190,.658),(-.477,.273,.196,.679),(-.364,.269,.205,.678),
   (-.301,.262,.209,.649),(-.271,.235,.216,.570)),
G:((-.786,.208,.197,.437),(-.770,.251,.188,.475),(-.733,.260,.184,.496),(-.692,.273,.188,.542),
   (-.660,.272,.192,.568),(-.599,.273,.194,.575),(-.419,.268,.209,.574),
   (-.365,.250,.211,.549),(-.343,.229,.220,.512)),
F:((-.797,.209,.199,.398),(-.781,.239,.189,.462),(-.753,.260,.184,.521),(-.710,.271,.194,.566),
   (-.652,.272,.202,.604),(-.607,.271,.206,.625),(-.514,.269,.207,.632),
   (-.400,.263,.214,.626),(-.355,.248,.223,.582),(-.326,.226,.232,.541))}
def face(m,n,c,pts):m.face(n,P[c],pts)
def new():return R.Mesh(R.terrain_height(0))
def bar(m,n,c,a,b,w=.021,d=.020):
    av,bv=V(a),V(b)
    axis=(bv-av).normalized()
    u=axis.cross(V((1,0,0)) if abs(axis.x)<.8 else V((0,0,1))).normalized()*w/2
    v=axis.cross(u).normalized()*d/2
    ring=lambda p:[tuple(p+u+v),tuple(p-u+v),tuple(p-u-v),tuple(p+u-v)]
    aa,bb=ring(av),ring(bv)
    face(m,n,c,aa[::-1]);face(m,n,c,bb)
    for i in range(4):
        j=(i+1)%4
        face(m,n,c,(aa[i],aa[j],bb[j],bb[i]))
def shell(m,stock):
    rings=[]
    for z,x,l,h in CAB[stock]:
        q=[(-x*.76,z,l),(x*.76,z,l),(x,z,l+.054),(x,z,h-.047),(x*.88,z,h),
           (-x*.88,z,h),(-x,z,h-.047),(-x,z,l+.054)]
        rings.append(q)
    for a,b in zip(rings,rings[1:]):
        for j,c in enumerate(("blue_low","blue_low","blue_dark","blue_ridge","blue_light","blue_ridge","blue","blue_low")):
            k=(j+1)%8
            face(m,"Independent sculpted steel cab pressings",c,(a[k],a[j],b[j],b[k]))
    face(m,"Closed front and back cab ends","blue",rings[0])
    face(m,"Closed front and back cab ends","blue",rings[-1][::-1])
def wind(m,stock):
    ranges={M:(-.724,-.574),G:(-.740,-.651),F:(-.752,-.624)}
    lo,hi=ranges[stock]
    def p(x,z,d):
        for (a,_,_,h),(b,_,_,k) in zip(CAB[stock],CAB[stock][1:]):
            if a<=z<=b:
                return (x,z,h+(k-h)*(z-a)/(b-a)+d)
        raise ValueError(z)
    for name,c,a,b,w,d in (("Deep windscreen rubber collar","seal",lo-.006,hi+.006,.204,.006),
            ("Two separate broad windscreen panes","glass",lo,hi,.194,.009),
            ("Thin high windshield sky reflection","glint",hi-.045,hi-.020,.188,.012)):
        zz=[a]+[q[0] for q in CAB[stock] if a<q[0]<b]+[b]
        for x0,x1 in ((-w,-.006),(.006,w)):
            for e,f in zip(zz,zz[1:]):
                face(m,name,c,(p(x0,e,d),p(x1,e,d),p(x1,f,d),p(x0,f,d)))
    for s in (-1,1):
        bar(m,"Two independent windscreen wiper arms","black",p(s*.045,lo+.010,.015),p(s*.154,lo+.034,.014),.009,.008)

def underbody(m,stock):
    _,_,ax,radius=STOCK[stock]
    B(m,"Separate lower boxed ladder frame","frame",0,.006,.390,1.48,.111,.219,.019)
    for side in (-1,1):
        x=side*.183
        B(m,"Pressed steel chassis side spar","iron",x,0,.038,1.483,.142,.204,.005)
        B(m,"Saddle diesel and compressed air tank","alloy",side*.190,-.007,.114,.261,.124,.212,.019)
        for z in (-.074,.083):B(m,"Restrained tank fastening band","black",side*.190,z,.120,.016,.122,.217,.004)
        B(m,"Shallow cabin steps safe behind steer axle","silver",side*.250,-.343,.047,.059,.145,.164,.005)
        B(m,"Shallow cabin steps safe behind steer axle","alloy",side*.248,-.324,.052,.066,.186,.203,.005)
        B(m,"Fixed tread corrugated rear anti-spray mud flap","black",side*.222,ax[-1]+radius+.017,.095,.024,.064,.200,.006)
        B(m,"Side protection rib steel runners","steel",side*.225,.118,.069,.435,.175,.202,.008)
        for z in (-.11,.294):B(m,"Vertical frame retention and recovery brackets","iron",side*.226,z,.033,.039,.125,.175,.004)
    for i,z in enumerate(ax):
        T(m,"Transverse actual road axle","steel",(-.218,z,radius),(.218,z,radius),.021,.021,10)
        for s,side in ((-1,"L"),(1,"R")):
            x=s*.218
            def axle(n,c,l,r,k=16,yy=radius,zz=z):
                T(m,n,c,(x+l,zz,yy),(x+r,zz,yy),k/1000,k/1000,16)
            # Segmented circumferential radius with exactly placed mirrored Y0 contacts.
            def tire(r,n,c,lo,hi):
                a=[(x+lo,z+r*cos(tau*j/16),radius+r*sin(tau*j/16)) for j in range(16)]
                b=[(x+hi,p[1],p[2]) for p in a]
                face(m,n,c,a[::-1]);face(m,n,c,b)
                for k in range(16):
                    j=(k+1)%16
                    face(m,n,c,(a[k],a[j],b[j],b[k]))
            tire(radius,"Ground contact tyre "+side,"tread",-.023,.023)
            tire(radius-.005,"Bulging flexible textured tyre shoulders","tyre",-.035,.035)
            axle("Stamped alloy driving discs","rim",s*.035-.005,s*.035+.005,65)
            axle("Machined convex central wheel hubs","lug",s*.042-.005,s*.042+.006,30)
            if i:axle("Inward tandem drive tyre","tyre",-s*.059-.015,-s*.059+.015,round((radius-.009)*1000))
            for j in range(5):
                a=tau*j/5
                axle("Small independent pressed steel rim fasteners","silver",s*.044-.003,s*.044+.003,
                     5,radius+sin(a)*.046,z+cos(a)*.046)
            outer=radius+.020;inner=radius+.010
            for j in range(12):
                def p(ang,r,d):return (x+d,z+r*cos(ang),radius+r*sin(ang))
                a=.062+j*pi*.953/12;b=.062+(j+1)*pi*.953/12
                face(m,"Curved road splash guards","rub",(p(a,outer,-.045),p(b,outer,-.045),p(b,outer,.046),p(a,outer,.046)))
                for dx in (-.045,.046):
                    face(m,"Rolled wheel arch return flange","steel",(p(a,outer,dx),p(a,inner,dx),p(b,inner,dx),p(b,outer,dx))[::(-1 if dx<0 else 1)])
    B(m,"Hard low front impact bumper","black",0,-.783,.513,.050,.181,.226,.012)
    B(m,"Front brushed bumper stripe","silver",0,-.810,.420,.009,.186,.200,.004)
    B(m,"Rear steel underslung underrun bumper","steel",0,.769,.498,.044,.132,.188,.011)
    for s in (-1,1):
        B(m,"One ruby rear lens each side","red",s*.198,.786,.066,.013,.171,.191,.004)
        B(m,"Amber rear fleet indicator","amber",s*.241,.786,.015,.011,.174,.190,.003)

def cab(m,stock):
    shell(m,stock);wind(m,stock)
    high={M:.689,G:.584,F:.639}[stock]
    B(m,"Forward aerodynamic shade visor","blue_ridge",0,-.525 if stock==M else -.616,.430,.139,high-.028,high,.013)
    low={M:.238,G:.271,F:.246}[stock]
    B(m,"Real recessed dark radiator face","black",0,-.792,.315,.027,low,low+.132,.015)
    for i in range(6):
        y=low+.012+i*.019
        B(m,"Individual pressings across radiator slots","steel",0,-.808,.289,.008,y,y+.006,.002)
    B(m,"Rear identity plate above cabin deck","label",0,-.819,.101,.006,.206,.224,.002)
    for s in (-1,1):
        x=s*.201
        B(m,"Stock independent inset headlamp blocks","seal",x,-.775,.089,.044,.217,.322,.010)
        B(m,"Warm white headlamp glass","light",x,-.799,.064,.010,.271,.304,.004)
        B(m,"Smoked headlamp lower reflector","pale",x,-.799,.054,.009,.227,.254,.003)
        B(m,"Outer amber parking marker glass","amber",s*.236,-.781,.023,.016,.255,.299,.004)
        roof=max(q[3] for q in CAB[stock])
        B(m,"Driver and passenger tinted side glass trim","seal",s*.269,-.520,.022,.201,roof-.190,roof-.046,.013)
        B(m,"Deep inset original driver and mate window glass","glass",s*.282,-.519,.012,.176,roof-.173,roof-.066,.010)
        B(m,"Painted top edge sky wash in door glass","glint",s*.288,-.520,.005,.151,roof-.095,roof-.077,.006)
        B(m,"Pressed lower side door skin seams","blue_low",s*.268,-.491,.011,.228,roof-.330,roof-.201,.008)
        B(m,"Painted low flat door panel","blue",s*.274,-.491,.009,.213,roof-.324,roof-.206,.009)
        B(m,"Nickel latch below glass","silver",s*.281,-.418,.009,.049,roof-.243,roof-.220,.004)
        bar(m,"Cab mirror support","black",(s*.260,-.641,roof-.164),(s*.293,-.652,roof-.157),.016,.014)
        B(m,"Short-set road legal mirror pod","black",s*.293,-.653,.027,.045,roof-.186,roof-.117,.007)
        B(m,"Independent mirror reflector","glint",s*.293,-.629,.018,.008,roof-.177,roof-.126,.004)
        if stock==M:
            for z in (-.426,-.355):
                B(m,"Low Forestry amber roof hazard","amber",s*.178,z,.042,.054,.672,.688,.006)

def timber(m):
    B(m,"Long solid open timber bed frame","stake",0,.260,.477,.974,.219,.265,.014)
    for i in range(7):
        B(m,"Separate longitudinal oak deck slats","deck1" if i%3 else "deck2",(i-3)*.060,.258,.056,.947,.260,.282,.004)
    for z in (-.188,.130,.370,.662):
        B(m,"Visible transverse lumber bunk bases","stake_light",0,z,.501,.059,.280,.311,.009)
        for s in (-1,1):
            bar(m,"Real inward-raked steel timber stakes","stake",(s*.240,z,.283),(s*.221,z-.014,.630),.032,.034)
            B(m,"Upper worn nickel timber stake protector","stake_light",s*.222,z-.014,.036,.041,.617,.647,.004)
            B(m,"Independent orange reflectors on each stake","amber",s*.246,z-.013,.007,.025,.594,.622,.002)
            B(m,"Load rope attachment and rocking steel foot","steel",s*.242,z,.036,.047,.279,.333,.005)
    for x in (-.189,-.102,0,.102,.189):
        bar(m,"Headboard protective vertical steel rail","stake_light",(x,-.232,.263),(x*.93,-.217,.605),.030,.033)
    for h in (.343,.452,.604):
        B(m,"Road safe protective steel headboard rails","stake",0,-.221,.413,.038,h-.015,h+.015,.006)

def logs(m):
    rng=Random(146208200)
    for k,(sta,end,straps) in enumerate(((-.206,.240,(-.085,.140)),(.257,.746,(.366,.621))),1):
        for i,(x,h,r) in enumerate(((-.143,.333,.054),(-.049,.337,.056),(.047,.334,.053),(.141,.332,.055),
          (-.107,.424,.055),(-.007,.424,.061),(.102,.427,.054),(-.062,.510,.052),(.046,.518,.053),(-.008,.585,.042)),1):
            name=f"bundle {k} log {i}"
            loops=[]
            z0,z1=sta+rng.uniform(0,.026),end-rng.uniform(0,.042)
            variation=[rng.uniform(.955,1.05) for _ in range(10)]
            arr=[rng.choice(("bark1","bark2","bark3","bark4","bark3")) for _ in range(10)]
            for t in (0,.24,.52,.75,1):
                plane=[]
                for j in range(10):
                    a=j*tau/10+.062*(i%3)
                    rr=r*(1.047-.105*t+.019*sin(t*pi))*variation[j]
                    plane.append((x+rr*cos(a)+.004*sin(t*pi),z0+t*(z1-z0)+.0015*t*sin(a),h+rr*sin(a)))
                loops.append(plane)
            for a,b in zip(loops,loops[1:]):
                for j in range(10):
                    n=(j+1)%10
                    face(m,"Tapered timber bark "+name,arr[j],(a[j],b[j],b[n],a[n]))
            for j,outer in enumerate((loops[0],loops[-1])):
                z=z0 if j==0 else z1
                old=outer
                for s,c in ((.91,"end1"),(.72,"end2"),(.65,"ring"),(.41,"end1"),(.34,"ring")):
                    inner=[(x+(xx-x)*s,z+(.0014 if j else -.0014)*(1-s),h+(yy-h)*s) for xx,_,yy in outer]
                    for i0 in range(10):
                        n=(i0+1)%10
                        p=(old[i0],old[n],inner[n],inner[i0])
                        face(m,"Distinct sawn timber growth rings "+name,c,p[::-1] if j else p)
                    old=inner
                face(m,"Sapwood cut core "+name,"end2",old[::-1] if j else old)
        for j,z in enumerate(straps,1):
            ends=((- .237,.294),(-.210,.377),(-.171,.461),(-.119,.535),(-.066,.599),(-.015,.631),(.040,.610),
                  (.098,.563),(.159,.499),(.193,.435),(.224,.341),(.239,.291))
            for (a,b),(c,d) in zip(ends,ends[1:]):
                bar(m,f"Actual fitted load cinch bundle {k} binder {j}","strap",(a,z,b),(c,z,d),.013,.020)
            for s in (-1,1):
                B(m,"Visible load restraint ratchet buckles","stake_light",s*.231,z,.029,.042,.297,.345,.005)

def hopper(m):
    l,u=-.312,.742
    B(m,"Separate structural tipping subframe","frame",0,.227,.484,1.063,.226,.284,.011)
    B(m,"Rolled nickel underbody boot leading to hinges","silver",0,.229,.528,1.072,.273,.297,.008)
    B(m,"Independent worn internal hopper bed","grain_floor",0,.216,.344,1.009,.286,.311,.006)
    for x in (-.124,-.061,0,.061,.124):
        B(m,"Five separate internal grain floor grooves","iron",x,.214,.003,.997,.311,.314,.001)
    for s in (-1,1):
        for z0,z1 in zip((l,-.067,.222,.512),(-.067,.222,.512,u)):
            face(m,"Hopper interior inward-facing steel slope","grain_inner",[(s*.170,z0,.309),(s*.170,z1,.309),(s*.214,z1,.420),(s*.214,z0,.420)][::-s])
            face(m,"Tall inward-facing hopper walls","grain_wall",[(s*.214,z0,.419),(s*.214,z1,.419),(s*.214,z1,.583),(s*.214,z0,.583)][::-s])
        for z0,z1 in zip((l,-.043,.306,.644),(-.048,.302,.640,u)):
            for h0,h1,w0,w1,c in ((.316,.423,.227,.249,"grain_inner"),(.423,.528,.249,.248,"lip"),(.528,.576,.248,.236,"grain_wall")):
                face(m,"Pressed exterior silver drop side panels",c,
                     [(s*w0,z0,h0),(s*w0,z1,h0),(s*w1,z1,h1),(s*w1,z0,h1)][::s])
        for z in (-.282,-.045,.303,.643,.709):
            B(m,"Pressed vertical hopper stiffness ribs","iron",s*.245,z,.039,.022,.333,.575,.004)
            B(m,"Outer clean rim rivet caps","silver",s*.267,z,.005,.011,.539,.559,.002)
            B(m,"Three broad hinge turns","alloy",s*.249,z,.029,.043,.326,.353,.006)
        B(m,"Rigid bright continuous dropped hopper lip","lip",s*.237,.216,.047,1.094,.571,.594,.006)
        B(m,"Continuous pressed tie rail above drop panels","pale",s*.251,.217,.015,1.062,.409,.435,.006)
        B(m,"Blue lower pressed steel grain vessel band","steel_cool",s*.245,.218,.020,1.052,.324,.357,.005)
        bar(m,"Stock visible pair of hydraulic tipping rams","steel",(s*.129,-.249,.154),(s*.178,-.120,.268),.032,.028)
        bar(m,"Separate bronze ram piston rods","strap",(s*.148,-.208,.187),(s*.181,-.119,.268),.015,.015)
    for z,n in ((l,"Front sealed grain headboard"),(u,"Rear independent grain gate")):
        B(m,n,"grain_wall",0,z,.469,.034,.326,.582,.006)
        B(m,n+" protective rim","silver",0,z,.499,.049,.567,.594,.007)
    B(m,"Discharge hatch secondary panel","steel_cool",0,.768,.238,.021,.346,.468,.009)
    B(m,"Tail gate independent silver hinge and spindle","steel",0,.779,.349,.015,.526,.547,.004)
    B(m,"Discharge slide narrow release lever","silver",.082,.782,.016,.015,.356,.465,.004)

def grain(m):
    rng=Random(143_40_30);rows=[];fs=[]
    for j,z in enumerate((-.292,-.238,-.170,-.087,-.004,.079,.158,.233,.306,.383,.459,.538,.619,.686,.721)):
        row=[]
        for i,x in enumerate((-.210,-.176,-.120,-.060,0,.061,.119,.174,.210)):
            y=.518+.004*cos(tau*z*.82+.5)+.009*cos(tau*(z-.15)*1.78)+.055*(1-(abs(x)/.225)**1.45)+rng.uniform(-.0023,.0024)
            row.append((x+(rng.uniform(-.009,.009) if 0<i<8 else 0),z+(rng.uniform(-.009,.009) if 0<j<14 else 0),y))
        rows.append(row)
    for j in range(14):
        for i in range(8):
            a,b,c,d=rows[j][i],rows[j][i+1],rows[j+1][i+1],rows[j+1][i]
            fs.extend(((a,b,d),(b,c,d)) if (i+j)%2 else ((a,b,c),(a,c,d)))
    for tri in fs:
        face(m,"Original lofted crown of golden bulk grain",rng.choice(("grain1","grain2","grain1","grain3","grain4")),tri)
    edge=rows[0]+[row[-1] for row in rows[1:]]+list(rows[-1][-2::-1])+[row[0] for row in rows[-2:0:-1]]
    for a,b in zip(edge,edge[1:]+edge[:1]):
        a0=(a[0],a[1],.425);b0=(b[0],b[1],.425)
        a1=(a[0]*.78,a[1],.317);b1=(b[0]*.78,b[1],.317)
        face(m,"Actual grain volume below surface","grain_depth",(a,a0,b0,b))
        face(m,"Actual grain volume below surface","grain_depth",(a0,a1,b1,b0))
        face(m,"Bounded bottom face of grain volume","grain_depth",((0,.217,.317),b1,a1))
    for tri in rng.sample(fs,132):
        a,b,c=(V(p) for p in tri)
        x,z,y=a+(b-a)*rng.uniform(.16,.43)+(c-a)*rng.uniform(.14,.43)
        rr=rng.uniform(.0025,.0049);phi=rng.uniform(0,tau)
        pts=[(x+rr*cos(k*tau/6+phi),z+.66*rr*sin(k*tau/6+phi),y+.0007) for k in range(6)]
        col=rng.choice(("grain1","grain2","grain5"))
        for k in range(6):face(m,"Individual scattered raised grain kernels",col,(pts[k],pts[(k+1)%6],(x,z,y+.0019)))

def cattle(m):
    lo,hi=-.316,.741
    bays=(-.290,-.104,.083,.270,.457,.644,.721)
    mid=(lo+hi)/2;l=hi-lo
    B(m,"Closed dark ribbed livestock canopy","roof",0,mid,.510,l+.018,.608,.660,.015)
    for x in (-.156,0,.156):
        B(m,"Distinct lengthwise raised canopy pressings","roof_seam",x,mid,.028,l-.027,.652,.667,.006)
    B(m,"Functional sealed inner livestock bed","floor",0,mid,.451,l-.006,.253,.309,.009)
    for i in range(19):
        B(m,"Internal transverse molded floor grip","floor",0,-.292+i*.055,.435,.012,.307,.315,.003)
    B(m,"Independent full fixed animal protection headboard","vent_dark",0,lo,.496,.037,.304,.639,.007)
    B(m,"Rear hatch landing sill under animal load","steel_cool",0,hi-.024,.495,.034,.278,.336,.005)
    for s,side in ((-1,"L"),(1,"R")):
        B(m,"Continuous external livestock waist beam","cage_blue",s*.243,mid,.039,l+.017,.487,.522,.007)
        B(m,"Continuous lower enclosure panel","cage",s*.243,mid,.045,l+.012,.317,.399,.008)
        B(m,"Long rolled cage roof fascia edge","roof_seam",s*.245,mid,.036,l+.014,.600,.641,.007)
        for z in bays:
            B(m,"Separate raised structural livestock posts","cage_blue",s*.253,z,.027,.031,.355,.620,.005)
            B(m,"Beveled interior structural post web for cage","vent_dark",s*.227,z,.030,.033,.320,.620,.005)
            for h in (.378,.506,.599):
                B(m,"Raised pressed cage fasteners","latch",s*.268,z,.005,.009,h-.005,h+.005,.0015)
        for i,(a,b) in enumerate(zip(bays,bays[1:]),1):
            for j,(low,up) in enumerate(((.398,.500),(.522,.604)),1):
                y=(low+up)/2;dy=.0135 if j==1 else .0115
                k=(a+b)/2;half=(b-a-.028)/2
                v=[(s*.253,k-half,y-dy),(s*.253,k+half,y-dy),(s*.231,k+half,y+dy),(s*.231,k-half,y+dy)][::s]
                back=[(x-s*.008,z,h-.004) for x,z,h in v]
                key=f"Real slot slat {side} bay {i} row {j}"
                face(m,key,"vent_light",v);face(m,key,"vent_dark",back[::-1])
                for e in range(4):
                    n=(e+1)%4
                    face(m,key,"cage_blue",(v[n],v[e],back[e],back[n]))
                for t in ((.32,.68) if b-a>.12 else (.32,)):
                    B(m,"Individual thin vertical vent deflectors","vent_dark",s*.225,a+(b-a)*t,.017,.012,low+.011,up-.010,.003)
        T(m,"Independently fixed tubular pen supports","silver",(s*.189,lo+.025,.550),(s*.189,hi-.047,.550),.013,.013,10)
        for z in (-.254,.055,.367,.681):
            B(m,"Inner restraint horizontal rail cleats","vent_dark",s*.197,z,.060,.018,.526,.571,.004)
        B(m,"Original livestock caution plate without logo","label",s*.271,-.219,.004,.068,.325,.350,.003)
    B(m,"Reinforced closed ramp underside load-latch panel","ramp",0,hi,.463,.035,.314,.506,.005)
    B(m,"Recessed lower ramp panel sheet","vent_dark",0,hi+.018,.401,.012,.339,.478,.008)
    B(m,"Padded inner gate and step cover","rub",0,hi-.022,.457,.019,.320,.503,.004)
    for x in (-.163,-.081,0,.081,.163):
        B(m,"Deep ribbed reinstatement press in door","cage",x,hi+.025,.022,.016,.342,.475,.005)
    for s in (-1,1):
        x=s*.190
        B(m,"Ramp perimeter reinforcement frame","silver",s*.217,hi+.023,.022,.023,.328,.482,.005)
        B(m,"Separate ramp gas strut extrusion","latch",s*.223,hi+.017,.039,.020,.319,.524,.008)
        T(m,"Tail ramp silver double wall pivot bars","alloy",(s*.151,hi+.028,.325),(s*.223,hi+.028,.325),.017,.017,12)
        B(m,"Two separate upper cattle access hatch door wings","ramp",s*.114,hi,.218,.035,.506,.621,.006)
        B(m,"Upper recessed rear vent plenum","roof",s*.115,hi+.018,.184,.008,.533,.589,.005)
        for y in (.537,.565):
            B(m,"Individual physically raised rear hatch louvres","cage_blue",s*.115,hi+.025,.181,.015,y,y+.011,.004)
        B(m,"Tall upper door actuating rod","silver",s*.059,hi+.029,.015,.016,.497,.605,.004)
        T(m,"Separate upper hatch visible hinge spring","alloy",(x-.029,hi+.026,.585),(x+.028,hi+.026,.585),.013,.013,10)
        B(m,"Classic rust golden traffic reflector","caution",s*.188,hi+.035,.042,.010,.475,.493,.002)
    B(m,"Central two-way lock and pull","silver",0,hi+.042,.072,.019,.481,.508,.006)

CONTENT={M:timber,G:hopper,F:cattle}
CARGO={M:logs,G:grain}
def atlas(stem):
    def chunk(n,p):return struct.pack(">I",len(p))+n+p+struct.pack(">I",zlib.crc32(n+p))
    row=b"".join(bytes.fromhex(c)*16 for c in COL.values())
    (ROOT/"mods/luanttd_core/textures"/f"bl_{stem}_atlas.png").write_bytes(b"\x89PNG\r\n\x1a\n"+
        chunk(b"IHDR",struct.pack(">IIBBBBB",1024,16,8,2,0,0,0))+chunk(b"IDAT",zlib.compress((b"\0"+row)*16,9))+chunk(b"IEND",b""))
def vehicle(stem):
    m=new();underbody(m,stem);cab(m,stem);CONTENT[stem](m)
    return m
def write(stem,ext,m):
    p=ROOT/"mods/luanttd_core/models"/f"bl_{stem}{ext}.obj"
    R.export_obj(p,local_obj(m))
    p.write_text(f"# Original stock {STOCK[stem][0]} vehicle; rebuild with tools/build_stock_late_freight_art.py\n"+p.read_text().split("\n",1)[1])
def build(stem):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    n,desc,ax,r=STOCK[stem]
    scene.name=f"LuanTTD | #{n} {desc}"
    scene["source"]="OpenTTD 16.0-RC1 engines table; original native 3D art inspired by OpenGFX."
    scene["pose"]="Luanti native local -Z nose; tire floor Y=0; visual scale .42."
    scene.world=bpy.data.worlds.new("Outdoor slate")
    mats=R.materials()
    for name,ma in zip(COL,mats):ma.name=name
    def col(m,label):
        c=bpy.data.collections.new(label);scene.collection.children.link(c);R.to_blender(m,c,mats)
        return c
    m=vehicle(stem);write(stem,"",m);col(m,"01 Original drive chassis, coachwork and fixed cargo fixtures")
    load=None
    if fn:=CARGO.get(stem):
        combined=vehicle(stem);fn(combined);write(stem,"_loaded",combined)
        cargo=new();fn(cargo);load=col(cargo,"02 Detached reversible cargo volume")
    atlas(stem)
    for screen in bpy.data.screens:
        for ar in screen.areas:
            if ar.type=="VIEW_3D":
                v=ar.spaces.active
                v.region_3d.view_location=V((0,0,.30));v.region_3d.view_distance=2.46
                v.region_3d.view_rotation=V((.74,-.93,.60)).to_track_quat("Z","Y")
                v.shading.color_type="MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{stem}.blend"),compress=True)
    if dest:=os.getenv("LATE_FREIGHT_REVIEW"):
        scene.render.engine="BLENDER_WORKBENCH"
        sh=scene.display.shading;sh.light="STUDIO";sh.studio_light="paint.sl"
        sh.color_type="MATERIAL";sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type="BOTH"
        sh.background_type="WORLD";scene.world.color=(.12,.16,.18)
        scene.view_settings.view_transform="Standard"
        scene.render.image_settings.file_format="JPEG"
        scene.render.resolution_x=740;scene.render.resolution_y=510;scene.render.resolution_percentage=100
        cam=bpy.data.cameras.new("Road stock studio");obj=bpy.data.objects.new("Road stock studio",cam)
        scene.collection.objects.link(obj);scene.camera=obj;cam.type="ORTHO";cam.ortho_scale=1.97
        for name,pos,on in (("front",(2.3,-2.7,1.65),False),("rear",(-2.5,2.75,1.72),True)):
            obj.location=pos
            obj.rotation_euler=(V((0,0,.3))-obj.location).to_track_quat("-Z","Y").to_euler()
            if load:load.hide_render=not on
            scene.render.filepath=str(Path(dest)/f"{stem}_{name}.jpg")
            bpy.ops.render.render(write_still=True)
if __name__=="__main__":
    for stem in STOCK:build(stem)
