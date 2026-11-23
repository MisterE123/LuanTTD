#!/usr/bin/env python3
"""Original 16.0-RC1 #150 Balogh, #151 Uhl and #152 Kelling steel flatbeds."""
from math import cos,sin,pi,tau
from pathlib import Path
from mathutils import Vector as V
import os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_late_freight_art as Q
B,T,bar,f=Q.B,Q.T,Q.bar,Q.face
E="stock_balogh_steel_truck"
U="stock_uhl_steel_truck"
K="stock_kelling_steel_truck"
STOCK={E:(150,"Balogh Steel Truck",(-.464,.432),.111),
       U:(151,"Uhl Steel Truck",(-.492,.466),.119),
       K:(152,"Kelling Steel Truck",(-.522,.258,.531),.121)}
Q.ROOT=ROOT;Q.STOCK=STOCK
Q.CAB={
U:((-.784,.170,.205,.355),(-.766,.212,.193,.409),(-.717,.225,.190,.445),
   (-.659,.234,.194,.476),(-.610,.250,.196,.551),(-.555,.258,.199,.603),
   (-.506,.259,.205,.623),(-.382,.258,.214,.622),(-.347,.246,.219,.578),(-.322,.228,.225,.544)),
K:((-.801,.221,.198,.411),(-.779,.251,.185,.451),(-.743,.270,.182,.490),
   (-.694,.274,.188,.540),(-.631,.274,.194,.604),(-.579,.272,.196,.653),
   (-.484,.270,.206,.670),(-.376,.265,.213,.665),(-.310,.248,.218,.622),(-.268,.223,.224,.553))}
ORIGINAL=dict(Q.COL)
CUSTOM=dict(stake="566c75",stake_light="8798a2",deck1="746351",deck2="86735d",strap="a29363",
    bark1="49545d",bark2="697880",bark3="829398",bark4="a9bbb8",
    end1="b5c3be",end2="8e9c9b",ring="596670",woodsplit="65777b",cloth="545b59",
    glove="6c7071")
CUSTOM.pop("glove")
LIVERIES={
E:dict(blue="406f88",blue_low="2c5268",blue_dark="355b71",blue_light="68939f",blue_ridge="5c8697",steel_cool="728e95",
       roof="4d575b",seal="333b40",glass="4d6b72",glint="88a5a6",rim="64808b",alloy="979c94",silver="bbc6bb"),
U:dict(blue="4a82a3",blue_low="2f5c7a",blue_dark="396d90",blue_light="669eb7",blue_ridge="548ca9",steel_cool="7fa4b5",
       roof="3e4f5e",glass="46626f",rim="9fabb1",silver="bbc5c5",pale="92b3bd"),
K:dict(blue="386b98",blue_low="274e70",blue_dark="325e83",blue_light="5486b1",blue_ridge="477da6",steel_cool="658ba7",
       roof="344957",glass="3c596e",rim="a0adb1",silver="b2c2c8",pale="a4b8c1")}
GEOM={E:(-.197,.214,.518,.441,.131,.168,.615),U:(-.233,.182,.514,.447,.145,.183,.632),
      K:(-.261,.162,.513,.452,.153,.207,.683)}

def early(m):
    # Factory-built pre-war long hood and independent upright glazed cab,
    # not the full rounded MPS mail van shell.
    for name,col,frames in (("Balogh independent pressed vintage hood","blue",
        ((-.792,.144,.203,.370),(-.753,.174,.193,.411),(-.662,.178,.194,.430),(-.540,.182,.204,.447))),
        ("Balogh upright early two-person cab and rounded crown","blue_light",
        ((-.553,.163,.238,.472),(-.526,.205,.221,.574),(-.491,.233,.217,.614),
         (-.432,.235,.218,.621),(-.322,.231,.229,.609),(-.258,.214,.233,.553)))):
        def r(z,w,a,b):return [(-w*.84,z,a),(w*.84,z,a),(w,z,a+.045),(w,z,b-.050),
                                (w*.82,z,b),(-w*.82,z,b),(-w,z,b-.050),(-w,z,a+.045)]
        a=list(map(lambda x:r(*x),frames))
        for p,q in zip(a,a[1:]):
            for j,col0 in enumerate(("blue_low","blue_low","blue","blue_ridge",col,"blue_ridge","blue","blue_low")):
                k=(j+1)%8
                f(m,name,col0,(p[k],p[j],q[j],q[k]))
        f(m,name,col,a[0]);f(m,name,col,a[-1][::-1])
    B(m,"Balogh independent brushed nickel radiator outline","silver",0,-.793,.281,.029,.254,.387,.013)
    B(m,"Deep shadowed black Balogh early cooling grille","black",0,-.809,.231,.009,.270,.373,.005)
    for x in (-.091,-.067,-.043,-.019,.005,.029,.053,.077):
        B(m,"Distinct vertically fluted Balogh radiator ribs","alloy",x,-.814,.006,.004,.277,.369,.001)
    for s in (-1,1):
        T(m,"Pre-war Balogh headlamp cylindrical barrels","blue_low",(s*.191,-.747,.308),(s*.191,-.782,.308),.043,.037,14)
        T(m,"Short warm opaque Balogh headlight neck lenses","light",(s*.191,-.783,.308),(s*.191,-.787,.308),.031,.030,14)
        B(m,"Balogh long front nickel bonnet hinge","alloy",s*.132,-.651,.010,.198,.408,.426,.005)
        for z in (-.725,-.682,-.639,-.595,-.555):
            B(m,"Small separate long hood cooling side plates","blue_low",s*.172,z,.008,.011,.289,.386,.002)
        B(m,"Upright low nearly vertical Balogh front glass pair","seal",s*.097,-.530,.181,.017,.427,.578,.008)
        B(m,"Original individual Balogh window panel dark sea glaze","glass",s*.098,-.541,.155,.008,.442,.564,.005)
        B(m,"Thin old daylight reflection cabins independent","glint",s*.099,-.546,.145,.004,.542,.553,.002)
        B(m,"Balogh original chamfered early side door pane","seal",s*.231,-.417,.018,.167,.415,.550,.011)
        B(m,"Dark separate Balogh side glass","glass",s*.239,-.419,.011,.144,.431,.540,.007)
        B(m,"Prewar brass latched lower cab pressed shape","blue_low",s*.233,-.405,.012,.178,.283,.408,.010)
        B(m,"Separate front early silver side latch","silver",s*.241,-.363,.009,.041,.379,.393,.002)
        bar(m,"Small mounted round early side mirror stem","steel",(s*.208,-.481,.473),(s*.272,-.495,.486),.010,.009)
        T(m,"Small independent vintage Balogh mirror head","silver",(s*.273,-.508,.487),(s*.273,-.485,.487),.024,.023,12)
        B(m,"Visible additional full-length prewar rolled footboard","blue_low",s*.234,-.032,.087,.556,.120,.148,.006)

def later(m,k):
    Q.shell(m,k)
    # Uhl has a squarer forward-control work cab, visibly taller
    # only at its steep rear. Kelling's glass pitches over a lower grille.
    high=.626 if k==U else .679
    lo,hi=(-.665,-.555) if k==U else (-.739,-.590)
    def p(x,z,d):
        for (a,_,_,h),(b,_,_,j) in zip(Q.CAB[k],Q.CAB[k][1:]):
            if a<=z<=b:return x,z,h+(j-h)*(z-a)/(b-a)+d
        raise ValueError(z)
    for tag,col,a,b,w,d in (("Solid double glass black rubber window surround","seal",lo-.006,hi+.006,.201,.006),
        ("Independent source-style twin windshield glass panes","glass",lo,hi,.192,.010),
        ("Thin modern overhead horizon line in glass","glint",hi-.039,hi-.022,.186,.013)):
        zs=[a]+[q[0] for q in Q.CAB[k] if a<q[0]<b]+[b]
        for zl,zh in zip(zs,zs[1:]):
            for xl,xh in ((-w,-.006),(.006,w)):
                f(m,tag,col,(p(xl,zl,d),p(xh,zl,d),p(xh,zh,d),p(xl,zh,d)))
    # Separate radiators and bumpers, not a texture on the same outline.
    if k==U:
        B(m,"Striped alloy Uhl square frontal intake","black",0,-.782,.284,.021,.255,.366,.008)
        for x in (-.106,-.077,-.048,-.019,.010,.039,.068,.097):
            B(m,"Uhl high vertical independent radiator inlay blades","alloy",x,-.797,.008,.008,.264,.357,.002)
        B(m,"Distinct square Uhl high teal top brow","blue_light",0,-.493,.408,.118,.600,.631,.017)
    else:
        B(m,"Kelling contemporary inset lower grille housing","black",0,-.794,.341,.027,.243,.371,.014)
        for h in (.260,.279,.306,.337,.352):
            B(m,"Kelling independent long bright radiator strakes","steel",0,-.812,.306,.010,h,h+.007,.002)
        B(m,"Long cobalt high swept Kelling cab roof wing","blue_ridge",0,-.545,.431,.138,.653,.683,.015)
    for s in (-1,1):
        bar(m,"Original separate slanted windscreen wipers","black",p(s*.044,lo+.009,.017),p(s*.159,lo+.032,.016),.008,.008)
        if k==U:
            T(m,"Uhl individually round middle-era lamp inlay ring","rub",
                (s*.184,-.759,.293),(s*.184,-.786,.293),.047,.040,12)
            T(m,"Uhl two bright rounded steady lenses","light",
                (s*.184,-.787,.293),(s*.184,-.790,.293),.032,.031,12)
        else:
            B(m,"Kelling narrow aerodynamic projector recess","black",s*.196,-.793,.097,.023,.227,.321,.007)
            B(m,"Kelling angular separate opaque headlights","light",s*.198,-.805,.071,.007,.267,.303,.005)
            B(m,"Kelling yellow marker separated from main headlight","amber",s*.237,-.792,.023,.018,.258,.298,.004)
        B(m,"Original driver and passenger blue side pane seals","seal",s*.267,-.510,.021,.204,high-.194,high-.058,.008)
        B(m,"Independent semirecessed automotive blue door glasses","glass",s*.279,-.510,.011,.180,high-.183,high-.068,.007)
        B(m,"Sharp controlled reflection in door glass flank","glint",s*.287,-.515,.004,.156,high-.092,high-.080,.003)
        B(m,"Recessed darker steel rolling cab door seam","blue_low",s*.267,-.483,.015,.212,high-.331,high-.197,.006)
        B(m,"Own lower painted aerodynamic cab side door","blue",s*.275,-.482,.009,.189,high-.322,high-.207,.006)
        B(m,"Separate little flat chrome driver pull","silver",s*.283,-.419,.010,.053,high-.259,high-.235,.003)
        bar(m,"Folding short mirror stem under wind","black",(s*.256,-.641,.481),(s*.293,-.652,.500),.012,.015)
        B(m,"Flat rounded modern side mirror support housing","black",s*.293,-.658,.027,.039,.458,.532,.008)
        B(m,"Independent modern original side-rear mirror glass","glint",s*.293,-.635,.017,.008,.472,.517,.004)

def platform(m,key):
    low,a,b,h,r,w,hcab=GEOM[key]
    rear=.759;mid=(low+rear)/2;length=rear-low
    B(m,"Original open flatbed underdeck steel C channel frame","stake",0,mid,.456,length,.203,.267,.011)
    for i in range(8):
        y=.249 if key==E else .252
        B(m,"Individually sawn exposed longitudinal timber flatbed slats",
            ("deck1","deck2","deck1")[i%3],(i-3.5)*.057,mid,.055,length-.018,y,y+.027,.003)
    for s in (-1,1):
        B(m,"Heavy brushed steel outer flatbed side rails","stake_light",s*.239,mid,.035,length+.004,.233,.289,.007)
        for z in (low+.025,.022,.231,.471,.685,.735):
            B(m,"Visible long-boxed outer roll restraints side load anchor mounts","stake",s*.247,z,.039,.030,.236,.342,.004)
            B(m,"Original red and yellow outer small resistance reflector strip","amber",s*.271,z,.007,.019,.254,.276,.003)
        for z in (a,b):
            for dz in (-.098,.098):
                B(m,"Native fixed side restraint ring anchor mounting plate","stake",s*.166,z+dz,.056,.043,.272,.291,.006)
                T(m,"Two fixed real tiedown eye lugs","silver",
                   (s*.178,z+dz,.283),(s*.178,z+dz,.310),.011,.011,8)
    for z in (a,b):
        for dz in (-1,1):
            # Deep V chock on timber, curved metal center restrained
            # against rolling by four actual angled fore/aft faces.
            pts=((- .143,z+dz*.050,.284),(.143,z+dz*.050,.284),(.143,z+dz*.118,.352),(-.143,z+dz*.118,.352))
            f(m,"Fixed V-faced physical coil chock fore and aft","woodsplit",pts[::dz])
            B(m,"Physical wrapped wooden and iron safety coil chocks fixed on empty and full bed",
               "deck2",0,z+dz*.127,.319,.042,.271,.349,.007)
            B(m,"Silver edged chock brace installed to bed","stake_light",0,z+dz*.149,.319,.007,.269,.342,.004)
    # Separate sturdy U-shaped steel headboard and short rolled safety band.
    for s in (-1,1):
        bar(m,"Secure full headboard welded vertical flatbed front posts","stake",(s*.215,low,.274),(s*.215,low+.012,.540),.028,.035)
    for y in (.333,.432,.527):
        B(m,"Separate braced exposed headboard transverse crosspieces","stake",0,low+.006,.457,.034,y-.013,y+.015,.006)
    B(m,"Rear flattened closed brake battery and side fixture","steel",0,.768,.508,.049,.208,.261,.008)

def coil(m,k,j,z,h,r,w):
    # Transverse coil axis, concentric winding side layers surrounding a
    # genuine open core. Modelled steel seam and through straps, no pixels.
    key=f"Coil {j}"
    n=36
    core=r*.370
    stations=((-w/2+.007,r*.956),(-w/2,r*.933),(-w/2,core*1.055),(-w/2+.009,core),
               (w/2-.009,core),(w/2,core*1.055),(w/2,r*.933),(w/2-.007,r*.956))
    rows=[]
    for x,R in stations:
        rows.append([(x,z+R*cos(tau*i/n),h+R*sin(tau*i/n)) for i in range(n)])
    for i,a in enumerate(rows):
        b=rows[(i+1)%len(rows)]
        for q in range(n):
            c=(q+1)%n
            shade=("bark3","end2","bark2","cloth","bark2","end2","bark3","bark4")[i]
            if i==7:shade=("bark2","bark3","bark4","end1","bark3")[q//3%5]
            f(m,"Closed annular rolled sheet steel load "+key,shade,(a[q],b[q],b[c],a[c]))
    for side in (-1,1):
        for l in range(8):
            R=core*1.11+l*(r*.914-core*1.11)/8+.0008
            def p(t,R0):return (side*(w/2+.0012+(l%2)*.0002),z+R0*cos(t),h+R0*sin(t))
            for q in range(n):
                left,right=q*tau/n,(q+1)*tau/n
                f(m,"Separate concentric steel sheet rolled ring ends "+key,
                 ("bark1","bark4","bark2","end1")[l%4],
                 (p(left,R),p(left,R+.0015),p(right,R+.0015),p(right,R))[::side])
        # Low steel through eye, then steering straps to both deck rails.
        x=w/2
        for tag,u in (("front",-1),("rear",1)):
            # An independently triangulated path connects the nonvisual
            # securing web directly into a fixed lashing point.
            pts=[(side*(x*.70),z+u*.034,h+.017),(side*x,z+u*.043,h+.025),
                 (side*(x+.024),z+u*.059,h+.008),(side*.161,z+u*.114,.301)]
            for a,b in zip(pts,pts[1:]):
                bar(m,f"Real tied down {tag} strap through the eye {key}","strap",a,b,.018,.011)
            B(m,"Steel strap ratchet clips near side pressure groove","stake_light",side*.148,z+u*.101,.034,.031,.309,.339,.003)
    # Two circumferential steel compression bands restrain the winding
    # itself, distinct from the added through-eye tie downs.
    for x in (-w*.29,w*.29):
        for i in range(n):
            a,b=i*tau/n,(i+1)*tau/n
            def p(t,d):return (x+d,z+(r*.958+.001)*cos(t),h+(r*.958+.001)*sin(t))
            f(m,"Strapped rolled steel circumferential bands keep coil closed "+key,"ring",
              (p(a,-.008),p(b,-.008),p(b,.008),p(a,.008)))

def cargo(key):
    def wrap(m):
        _,a,b,h,r,w,_=GEOM[key]
        coil(m,key,1,a,h,r,w)
        coil(m,key,2,b,h-.006,r-.004,w*.96)
    return wrap

def build_vehicle(key):
    m=Q.new();Q.underbody(m,key)
    early(m) if key==E else later(m,key)
    platform(m,key)
    return m
def export(key,suffix,m):
    p=ROOT/"mods/luanttd_core/models"/f"bl_{key}{suffix}.obj"
    Q.R.export_obj(p,Q.local_obj(m))
    p.write_text(f"# Original 16.0-RC1 stock steel truck #{STOCK[key][0]}; tools/build_stock_steel_trucks_art.py\n"+
                 p.read_text().split("\n",1)[1])
def build(key):
    Q.COL.clear();Q.COL.update(ORIGINAL);Q.COL.update(CUSTOM);Q.COL.update(LIVERIES[key])
    assert len(Q.COL)==64
    Q.R.COLORS[:]=Q.COL.values()
    Q.vehicle=build_vehicle;Q.write=export;Q.CARGO={k:cargo(k) for k in STOCK}
    Q.build(key)

if __name__=="__main__":
    stem=os.getenv("STEEL_TRUCK_STEM")
    for key in STOCK:
        if not stem or key==stem:build(key)
