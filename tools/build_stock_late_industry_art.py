#!/usr/bin/env python3
"""Original RC1 late Goss Goods, DW Coal and Perry Oil rigid road vehicles."""
from math import cos,sin,tau,pi
from pathlib import Path
from random import Random
import os,sys
from mathutils import Vector as V

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_late_freight_art as base

B,T,bar,face=base.B,base.T,base.bar,base.face
GOODS="stock_goss_goods_truck"
COAL="stock_dw_coal_truck"
OIL="stock_perry_oil_tanker"
stock={
    GOODS:(140,"Goss Goods Truck",(-.500,.464),.119),
    COAL:(125,"DW Coal Truck",(-.509,.268,.538),.120),
    OIL:(134,"Perry Oil Tanker",(-.493,.470),.120),
}
base.ROOT=ROOT
base.STOCK=stock
base.CAB={
GOODS:((-.797,.199,.209,.445),(-.768,.246,.198,.484),(-.731,.271,.190,.537),
        (-.693,.275,.190,.578),(-.653,.274,.193,.615),(-.593,.269,.201,.635),
        (-.402,.263,.211,.634),(-.344,.251,.215,.611),(-.302,.227,.221,.546)),
COAL:((-.790,.208,.198,.416),(-.778,.245,.183,.465),(-.754,.256,.182,.515),(-.711,.273,.189,.556),
      (-.666,.273,.196,.590),(-.590,.271,.203,.606),(-.450,.265,.209,.600),
      (-.371,.254,.218,.578),(-.329,.228,.222,.525)),
OIL:((-.803,.209,.203,.383),(-.781,.234,.189,.429),(-.749,.251,.185,.468),(-.700,.271,.190,.523),
     (-.648,.275,.198,.581),(-.593,.272,.207,.625),(-.527,.272,.209,.638),
     (-.401,.267,.214,.639),(-.338,.246,.221,.594),(-.292,.227,.234,.523)),
}
base.COL.update({
    "blue":"447096","blue_low":"2b4e6a","blue_light":"6c96b2","blue_dark":"345c7c","blue_ridge":"5a86a5",
    "steel_cool":"688da6","glass":"405d6a","pale":"9fb9c1","roof":"3a4c60","roof_seam":"2f3f50",
    "grain_wall":"778a92","grain_inner":"68777d","grain_floor":"535f68",
    # Three non-shared uses of these original palette slots.
    "bark1":"2a2d31","bark2":"383d41","bark3":"454c50","bark4":"536066",
    "woodsplit":"353a3d","end1":"b9c4c2","end2":"8b999b","ring":"768b95","strap":"77828a","cloth":"546771",
    "stake":"526f82","stake_light":"87a8b8","cage":"50799a","cage_blue":"759bb5","vent_dark":"3b5467",
    "vent_light":"8faabd","floor":"5a6a71","rub":"384959","ramp":"4d7191","latch":"9bacb0",
})
base.R.COLORS[:]=base.COL.values()
sculpture={
    GOODS:(-.746,-.650,.324,6,.628),
    COAL:(-.745,-.671,.273,4,.601),
    OIL:(-.755,-.589,.250,5,.639),
}
def cab(m,k):
    base.shell(m,k)
    win0,win1,y,n,roof=sculpture[k]
    c=base.CAB[k]
    def roof_point(x,z,d):
        for (a,_,_,h),(b,_,_,j) in zip(c,c[1:]):
            if a<=z<=b:return x,z,h+(j-h)*(z-a)/(b-a)+d
        raise ValueError(z)
    for name,paint,a,b,w,offset in (("Windscreen deep EPDM rubber gasket","seal",win0-.007,win1+.007,.211,.006),
                                         ("Two separate broad windscreen panes","glass",win0,win1,.199,.009),
                                         ("Raked long thin separate tinted glass reflection","glint",win1-.035,win1-.014,.192,.013)):
        zz=[a]+[x[0] for x in c if a<x[0]<b]+[b]
        for zl,zh in zip(zz,zz[1:]):
            for xl,xh in ((-w,-.005),(.005,w)):
                face(m,name,paint,(roof_point(xl,zl,offset),roof_point(xh,zl,offset),
                                  roof_point(xh,zh,offset),roof_point(xl,zh,offset)))
    dark="black" if k==OIL else "blue_low"
    B(m,"Cool swept brow in shade above glazing","blue_light",0,win1+.020,.437,.071,roof-.033,roof+.002,.011)
    B(m,"Wide deep intake fascia with blue plastic recess",dark,0,-.795,.337,.022,y-.012,y+.104,.014)
    for j in range(n):
        h=y+j*.015
        B(m,"Only original pressed nickel radiator blades","steel" if k==OIL else "alloy",0,-.807,.301,.010,h,h+.006,.002)
    B(m,"Small original neutral identity plate","label",0,-.818,.104,.008,.209,.228,.002)
    for s in (-1,1):
        xx=s*.208
        B(m,"Dark polycarbonate split recessed front lamp case","seal",xx,-.778,.084,.038,.232,.324,.008)
        B(m,"Separate front pressed opaque glass lamps","light",s*.201,-.798,.055,.010,.260,.300,.004)
        B(m,"Original amber side marker strip","amber",s*.238,-.785,.022,.017,.256,.302,.003)
        B(m,"Glazed molded side trim","seal",s*.269,-.519,.022,.202,roof-.190,roof-.043,.012)
        B(m,"Original separate side cab pane","glass",s*.281,-.520,.012,.174,roof-.178,roof-.061,.011)
        B(m,"Shared daylight reflected in driver door","glint",s*.287,-.521,.005,.143,roof-.093,roof-.073,.005)
        B(m,"Cab split painted front door split joint","blue_low",s*.270,-.492,.012,.235,roof-.340,roof-.200,.008)
        B(m,"Body-colored recessed lower driver door","blue",s*.276,-.495,.010,.207,roof-.320,roof-.209,.006)
        B(m,"Individual nickel cabin door latches","silver",s*.283,-.415,.010,.056,roof-.253,roof-.227,.004)
        bar(m,"Low short-set compact side mirror arm","steel",(s*.258,-.641,roof-.179),(s*.293,-.649,roof-.165),.014,.012)
        B(m,"Compact aero side mirror and protector","black",s*.293,-.650,.026,.045,roof-.203,roof-.129,.006)
        B(m,"Independent concave rear-facing mirror","glint",s*.293,-.625,.010,.007,roof-.193,roof-.141,.003)
        bar(m,"Separate short working wiper","black",roof_point(s*.043,win0+.010,.015),
            roof_point(s*.150,win0+.033,.014),.009,.008)

def goods(m):
    B(m,"Separate steel frame supporting factory van box","black",0,.220,.470,1.042,.230,.272,.012)
    B(m,"Rigid blue closed goods cargo box","cage",0,.218,.514,1.055,.259,.635,.014)
    B(m,"Dark polished rolled cargo van roof","roof",0,.218,.525,1.069,.626,.679,.014)
    B(m,"Long center blue-black roof corrugation","roof_seam",0,.218,.477,1.035,.667,.685,.009)
    for x in (-.177,-.089,0,.089,.177):
        B(m,"Discrete roof seams across the rigid cargo span","roof",x,.214,.017,1.000,.677,.687,.006)
    for s in (-1,1):
        B(m,"Three-tone low side van pressed steel panel band","blue_dark",s*.261,.218,.013,1.031,.298,.413,.006)
        for z in (-.264,-.134,-.004,.126,.256,.386,.516,.646,.715):
            B(m,"Blue outer long vertical goods-body ribs","cage_blue",s*.267,z,.024,.027,.283,.628,.005)
            B(m,"Subtle dark polished seam beside freight stiffeners","vent_dark",s*.273,z+.014,.003,.006,.321,.613,.001)
        B(m,"Blue light shallow continuous top sill","pale",s*.269,.218,.015,1.047,.606,.634,.005)
        B(m,"Original steel shadowed low box under-run rail","steel",s*.270,.223,.018,1.054,.266,.298,.009)
        B(m,"Independent hinged pressed rear cargo door leaves","ramp",s*.121,.750,.236,.030,.288,.614,.007)
        B(m,"Dark rubber doubled rear cargo door edge seals","vent_dark",s*.011,.767,.014,.010,.307,.604,.002)
        B(m,"Vertical steel van door latch rod","silver",s*.071,.773,.012,.014,.318,.587,.003)
        for h in (.332,.494,.556):
            B(m,"Three individually mounted doors hinges","alloy",s*.219,.775,.044,.020,h,h+.032,.005)
        B(m,"End latch swage and handle","silver",s*.096,.782,.069,.014,.369,.389,.003)
        B(m,"Closed freight loading platform hinge","latch",s*.191,.784,.043,.026,.213,.264,.004)
        B(m,"Cargo van lower safety glass behind door step","amber",s*.233,.779,.033,.010,.282,.303,.003)
    B(m,"Fixed upright folded rear freight lift gate","black",0,.781,.447,.039,.200,.278,.010)
    B(m,"Folded rear deck tread with slip-resistant edge","steel",0,.801,.385,.021,.222,.233,.004)
    for x in (-.152,-.060,.060,.152):
        B(m,"Folded rear platform stiffener seam","vent_dark",x,.805,.014,.003,.206,.257,.001)
    B(m,"Original enamel goods fleet plaque no logo","pale",0,.772,.128,.010,.511,.542,.003)

def coal(m):
    low,high=-.314,.741
    B(m,"Separate pivoted coal tipping frame","black",0,.218,.455,1.044,.220,.283,.014)
    B(m,"Deep bare coal tip floor visible when empty","grain_floor",0,.216,.314,1.012,.283,.323,.007)
    for s in (-1,1):
        for a,b in zip((low,-.058,.199,.457),(-.058,.199,.457,high)):
            face(m,"Industrial inward-facing thick coal bin sides","grain_inner",
                 [(s*.157,a,.322),(s*.157,b,.322),(s*.218,b,.503),(s*.218,a,.503)][::-s])
            face(m,"Inward charcoal upper vertical coal bin sheet","grain_wall",
                 [(s*.218,a,.502),(s*.218,b,.502),(s*.217,b,.584),(s*.217,a,.584)][::-s])
            face(m,"Industrial dark outer pressed coal wall","steel_cool",
                 [(s*.213,a,.317),(s*.213,b,.317),(s*.251,b,.521),(s*.251,a,.521)][::s])
            face(m,"Exposed gray heavy steel upper coal drop side","end2",
                 [(s*.251,a,.521),(s*.251,b,.521),(s*.245,b,.582),(s*.245,a,.582)][::s])
        B(m,"Long continuous cold brushed coal bin steel rim","end1",s*.233,.215,.049,1.081,.573,.600,.006)
        B(m,"Shallow outward stiffening sill stripe","vent_dark",s*.254,.213,.013,1.065,.488,.511,.005)
        for z in (-.280,-.056,.196,.453,.707):
            bar(m,"Independent structural angled hopper support blue-grey web","stake",
                (s*.218,z,.317),(s*.248,z,.577),.024,.026)
            B(m,"Three visible riveted tip attachment brackets","rim",s*.232,z,.028,.033,.294,.339,.004)
        bar(m,"Distinct nickel two-stage coal tip large hydraulic rams","rim",(s*.174,-.238,.216),
            (s*.175,-.056,.315),.029,.038)
    B(m,"Protected forward coal bulkhead keeps cab clean","grain_wall",0,low,.464,.040,.323,.608,.007)
    B(m,"Stock higher false pressure panel headboard rim","silver",0,low,.489,.046,.588,.615,.006)
    B(m,"Closed heavy coal tailgate until unloading","grain_wall",0,high,.472,.033,.318,.588,.005)
    B(m,"Rear tipped gate door under pressure yellow tab","caution",0,high+.023,.135,.011,.476,.553,.004)
    for s in (-1,1):
        B(m,"Individual tail latches dark blue","stake",s*.195,high+.031,.035,.018,.352,.473,.006)
        B(m,"Two hardened top tailgate hinge brackets","alloy",s*.199,high+.026,.058,.024,.542,.582,.005)

def coal_load(m):
    rng=Random(125_35_28)
    zset=[-.286+i*(.973/14) for i in range(15)]
    xset=[-.211+i*(.422/10) for i in range(11)]
    r=[]
    for j,z in enumerate(zset):
        row=[]
        for i,x in enumerate(xset):
            t=(1-abs(x)/.219)
            h=.504+.066*t+.011*cos(11*z+3*x)+rng.uniform(-.008,.008)
            row.append((x+(rng.uniform(-.008,.008) if 0<i<10 else 0),z+(rng.uniform(-.008,.008) if 0<j<14 else 0),h))
        r.append(row)
    fs=[]
    for j in range(14):
        for i in range(10):
            a,b,c,d=r[j][i],r[j][i+1],r[j+1][i+1],r[j+1][i]
            fs.extend(((a,b,d),(b,c,d)) if (i+j)%2 else ((a,b,c),(a,c,d)))
    for f in fs:
        face(m,"Actual faceted black coal mound surface",rng.choice(("bark1","bark2","bark2","bark3","woodsplit")),f)
    edge=r[0]+[row[-1] for row in r[1:]]+list(r[-1][-2::-1])+[row[0] for row in r[-2:0:-1]]
    for a,b in zip(edge,edge[1:]+edge[:1]):
        a1=(a[0]*.707,a[1],.324);b1=(b[0]*.707,b[1],.324)
        face(m,"Closed faceted coal cargo vertical boundary","bark2",(a,a1,b1,b))
        face(m,"Coal bulk bottom makes closed full volume","bark1",((0,.21,.324),b1,a1))
    for j,f in enumerate(rng.sample(fs,154)):
        a,b,c=map(V,f)
        u,v=rng.uniform(.18,.38),rng.uniform(.18,.38)
        x,z,h=a+u*(b-a)+v*(c-a);rad=rng.uniform(.003,.009)
        w=rng.randrange(6)
        rr=[(x+rad*cos(j0*tau/6),z+rad*sin(j0*tau/6),h-.001) for j0 in range(6)]
        peak=(x+rad*.201,z+rad*.091,h+rad*.81)
        for j0 in range(6):
            face(m,"Individual modelled angular coal granules",("bark1","bark2","bark3","bark4")[(j+w+j0)%4],(rr[j0],rr[(j0+1)%6],peak))

def oil(m):
    # Original longitudinal visible ellipsoidal pressure vessel with domed
    # ends, deep blue paint, contrasting dull-metal straps and pipework.
    center=.451
    rings=[]
    prof=((- .291,.111,.111),(-.274,.171,.159),(-.232,.207,.197),(-.182,.224,.208),
          (-.107,.226,.213),(.550,.226,.213),(.628,.222,.208),(.680,.208,.197),
          (.718,.175,.161),(.741,.112,.110))
    seg=28
    for z,x,y in prof:
        rings.append([(x*cos(tau*i/seg),z,center+y*sin(tau*i/seg)) for i in range(seg)])
    cols=("vent_dark","ramp","teal","steel_cool","blue_light","pale","blue_light","steel_cool")
    for j,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(seg):
            n=(i+1)%seg
            c=cols[(int((sin((i+.5)*tau/seg)+1)*3.8))]
            face(m,"Pressure tanker rolled welded barrel and domed ends",c,(a[i],b[i],b[n],a[n]))
    for side,ring in enumerate((rings[0],rings[-1])):
        face(m,"True sealed closure pressure plates","steel_cool",ring if side==0 else ring[::-1])
    # These outward sheet steel loops do not sit coplanar with the vessel.
    for z in (-.108,.107,.341,.548):
        for i in range(seg):
            a,b=i*tau/seg,(i+1)*tau/seg
            def p(t,zz):return (.229*cos(t),zz,center+.216*sin(t))
            face(m,"Full wrap silver tank strap locking hoop","end1" if z in (.107,.341) else "iron",
                 (p(a,z-.018),p(a,z+.018),p(b,z+.018),p(b,z-.018)))
    for z in (-.091,.512):
        B(m,"Steel support cradles physically bear tank","black",0,z,.428,.123,.231,.286,.014)
        for s in (-1,1):
            bar(m,"Pressure tank hold-down diagonal support feet","iron",(s*.185,z,.251),(s*.209,z,.351),.022,.039)
    for z in (.042,.392):
        T(m,"Independent raised manhole alloy flange","iron",(0,z,.658),(0,z,.676),.067,.065,16)
        T(m,"Capped chrome refilling hatch","silver",(0,z,.676),(0,z,.687),.051,.047,16)
        B(m,"Narrow manhole sprung lock across cap","latch",0,z,.105,.013,.682,.689,.003)
    B(m,"Silver rear recessed valve cabinet","steel",0,.738,.303,.041,.236,.365,.009)
    B(m,"Blue rear valve cabinet door","vent_dark",0,.767,.280,.024,.251,.351,.007)
    B(m,"Cabinet shoulder chrome latch","silver",.112,.782,.032,.010,.282,.306,.003)
    for s in (-1,1):
        B(m,"Original oil tanker painted side hazard placard","amber",s*.228,.294,.006,.128,.404,.473,.002)
        for z in (-.164,.643):
            B(m,"Tanker lower side reflective marker","warm",s*.212,z,.009,.068,.248,.267,.002)
        T(m,"Continuous anodized hose conduit below tanker rim","iron",(s*.208,-.103,.267),(s*.209,.715,.270),.021,.021,10)
        T(m,"Capped discharge service ports","end1",(s*.166,.738,.270),(s*.173,.780,.270),.028,.030,10)
    for h in (.302,.395,.481,.564,.620):
        T(m,"Permanent rear access step polished grab rails","silver",(.084,.760,h),(.197,.760,h),.009,.009,8)
    for x in (.084,.197):
        T(m,"Rear ladder true long support posts","iron",(x,.757,.295),(x*.92,.737,.643),.013,.013,10)

def vehicle(stem):
    m=base.new()
    base.underbody(m,stem)
    cab(m,stem)
    {GOODS:goods,COAL:coal,OIL:oil}[stem](m)
    return m

def write(stem,extension,m):
    p=ROOT/"mods/luanttd_core/models"/f"bl_{stem}{extension}.obj"
    base.R.export_obj(p,base.local_obj(m))
    head=f"# Original stock {stock[stem][0]} vehicle; rebuild with tools/build_stock_late_industry_art.py"
    p.write_text(head+"\n"+p.read_text().split("\n",1)[1])

base.vehicle=vehicle
base.write=write
base.CARGO={COAL:coal_load}
if __name__=="__main__":
    for stem in stock:base.build(stem)
