#!/usr/bin/env python3
"""Original exterior Blender models for RC1 Balogh/Uhl/Foster Armoured Trucks."""
from math import sin,cos,tau
from pathlib import Path
import os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_late_freight_art as Q
B,T,bar,f=Q.B,Q.T,Q.bar,Q.face
E="stock_balogh_armoured_truck"
U="stock_uhl_armoured_truck"
F="stock_foster_armoured_truck"
STOCK={E:(153,"Balogh Armoured Truck",(-.469,.426),.111),
       U:(154,"Uhl Armoured Truck",(-.491,.461),.120),
       F:(155,"Foster Armoured Truck",(-.511,.256,.526),.121)}
Q.ROOT=ROOT;Q.STOCK=STOCK;Q.CARGO={}
Q.CAB={
 E:((-.560,.177,.230,.488),(-.528,.209,.217,.550),(-.488,.223,.214,.594),
    (-.440,.229,.220,.603),(-.344,.227,.227,.595),(-.292,.213,.234,.549)),
 U:((-.788,.162,.192,.389),(-.766,.202,.184,.424),(-.734,.231,.186,.464),
    (-.677,.247,.191,.514),(-.621,.261,.193,.580),(-.572,.263,.195,.615),
    (-.491,.261,.204,.623),(-.380,.257,.214,.612),(-.324,.235,.225,.561)),
 F:((-.798,.211,.198,.401),(-.781,.240,.189,.452),(-.750,.260,.184,.506),(-.709,.272,.185,.559),
    (-.663,.276,.188,.608),(-.618,.272,.195,.651),(-.552,.271,.199,.669),
    (-.433,.263,.205,.669),(-.352,.251,.214,.631),(-.303,.235,.223,.558))}
ORIG=dict(Q.COL)
COMMON=dict(warm="dac7a1",label="d9d5be",cage_blue="7f9da8",vent_light="617789",vent_dark="3e5162",
    latch="82939d",alloy="94a19e",silver="b8c2c0",pale="a4b3b3",caution="c7ab73",rub="384752")
PALETTE={
 E:dict(blue="4f778b",blue_low="354d5e",blue_dark="405d6f",blue_light="779aa3",blue_ridge="668b98",glass="4f6c71",
        roof="424c55",roof_seam="53616a",cage="667d8a",floor="53656d",rim="687881",steel_cool="738993"),
 U:dict(blue="4d80a4",blue_low="355770",blue_dark="426784",blue_light="77a1bc",blue_ridge="6892ad",glass="436572",
        roof="4c6372",roof_seam="566f7e",cage="5b7f9c",floor="4f6472",rim="a6b2b4",steel_cool="749bb3"),
 F:dict(blue="3d6b93",blue_low="284b6b",blue_dark="3b6184",blue_light="698eb0",blue_ridge="5784ab",glass="3c5b6c",
        roof="344b61",roof_seam="445d74",cage="4e6d8b",vent_dark="30465d",floor="4f697d",rim="9cb0b4",steel_cool="688da6")}
# Four independent profiles: longitudinal position, deck half-width,
# armoured shin datum and shoulder/head cap. No invisible cargo load bay.
BODY={
 E:((-.332,.187,.252,.550),(-.288,.220,.249,.610),(-.215,.231,.247,.643),(.511,.235,.247,.643),
    (.655,.232,.251,.623),(.725,.207,.264,.577)),
 U:((-.317,.215,.247,.555),(-.258,.240,.239,.626),(-.199,.251,.236,.649),(.592,.252,.236,.649),
    (.708,.247,.249,.623),(.741,.217,.264,.591)),
 F:((-.322,.204,.247,.561),(-.256,.251,.239,.635),(-.176,.260,.232,.675),(.576,.260,.232,.675),
    (.673,.251,.233,.653),(.743,.225,.248,.613))}
GEOM={E:(.643,.215,.726,.551),U:(.649,.224,.743,.580),F:(.674,.229,.747,.597)}
def section(z,w,b,t):
    return [(-w*.78,z,b),(w*.78,z,b),(w,z,b+.039),(w,z,t-.066),
            (w*.85,z,t),(w*.52,z,t+.012),(-w*.52,z,t+.012),
            (-w*.85,z,t),(-w,z,t-.066),(-w,z,b+.039)]
def body(m,k):
    a=[section(*q) for q in BODY[k]]
    n="Original sealed rolled plated valuables secure transport coachwork"
    for p,q in zip(a,a[1:]):
        for i,col in enumerate(("black","blue_low","cage","steel_cool","roof","roof_seam","roof","steel_cool","cage","blue_low")):
            j=(i+1)%len(p)
            f(m,n,col,(p[j],p[i],q[i],q[j]))
    f(m,n,"floor",a[0]);f(m,n,"floor",a[-1][::-1])
    height,w,back,door=GEOM[k]
    for s in (-1,1):
        advanced=k==F
        wing=s*(.244 if k==E else .256 if k==U else .265)
        B(m,"Distinct lower perimeter reinforced plated side sill","blue_low",wing,.205,.023,.921,.259,.294,.007)
        B(m,"Fine pale steel crossbeam along safe plate shoulder","steel_cool",wing,.199,.012,.832,door-.014,door+.012,.004)
        for z in (-.142,.23,.58):
            B(m,"Main exterior individual side armour panel lines","vent_dark",wing,z,.004,.011,.302,door-.018,.001)
        if k==E:
            for z in (-.133,-.017,.108,.243,.366,.497,.612):
                for y in (.309,.526):
                    T(m,"Separate small raised steel plate dome rivets","pale",
                      (wing-s*.001,z,y),(wing+s*.005,z,y),.005,.004,8)
        else:
            for z in (-.143,.164,.562):
                B(m,"Exposed side plating structural carry strip","cage_blue",wing,z,.012,.024,.297,door-.016,.004)
        # Decorative side-facing aperture housing and a panel seam,
        # not a diagram or exposed real security device.
        B(m,"Faint original letterbox panel on secured side wall","floor",wing,.268,.018,.214,.377,.451,.007)
        B(m,"Two-tone pale trim on narrow closed valuables side panel","pale",wing+s*.010,.271,.005,.192,.386,.444,.005)
        B(m,"Individual strongly opaque rectangular side closure","vent_dark",wing+s*.014,.270,.003,.159,.395,.435,.001)
        for zz in (-.053,-.017,.019,.055):
            B(m,"Small pale vertical side closure stiffeners","steel",wing+s*.016,.270+zz,.003,.006,.394,.436,.001)
        B(m,"Neutral pale fleet identity plate no copied markings","label",wing,.480,.009,.100,.393,.423,.005)
        for dz in (-.032,-.01,.013,.034):
            B(m,"Abstract darker fleet emblem dashes","blue_dark",wing+s*.006,.480+dz,.003,.010,.401,.415,.001)
        B(m,"Side safer inlay pale reflector plate","caution",wing,.607,.016,.060,.304,.329,.004)
        # Steel closing leaves, stiffeners, and modern flush glazing along
        # the body; valuables themselves stay secluded in the locked box.
        x=s*(.108 if k==E else .114)
        B(m,"Original closed rear valuables double-door heavy steel frame","black",x,back,.211,.037,.284,door,.009)
        B(m,"Independent exterior steel rear valuables door leaves","steel_cool",x,back+.021,.190,.022,.296,door-.013,.009)
        for y in (.307,.457,door-.055):
            B(m,"Closed outward armoured cargo door anti-sag hinge pins","latch",
               s*(w-.015),back+.034,.039,.020,y,y+.030,.005)
        if advanced:
            B(m,"Deep pressed Foster rear-corner protective cheek","rub",s*.206,back+.006,.051,.050,.287,.475,.010)
            B(m,"Foster narrow rear elevated brake prism","red",s*.217,back+.032,.037,.011,.484,.540,.004)
        else:
            B(m,"Circular lower old reflective light back bracket","seal",s*.181,back+.024,.045,.015,.265,.307,.006)
            T(m,"Individual round rear red return lens","red",(s*.181,back+.034,.287),(s*.181,back+.039,.287),.014,.013,10)
        B(m,"Slim metallic raised rear door latch molding","silver",s*.058,back+.036,.013,.012,.337,door-.043,.002)
    B(m,"Fitted full-width armoured closed loading step","black",0,back+.027,.443,.052,.191,.239,.009)
    B(m,"Non-slip flush rib line rear armoured step","latch",0,back+.056,.398,.013,.212,.227,.004)
    B(m,"Small ivory blank rear fleet data plate","label",0,back+.037,.087,.014,.253,.279,.003)
    for x in (-.153,-.071,.010,.089,.159):
        B(m,"Original distinct longitudinal raised vault roof press seams","roof_seam",
          x,.195,.011,.715,height-.001 if abs(x)>.12 else height+.010,height+.007 if abs(x)>.12 else height+.015,.003)

def cab(m,k):
    Q.shell(m,k)
    if k==E:
        # The bonnet is a separate rounded front with independent pre-war
        # louver grille shoulders and round outboard lamps.

        bevelled=[(-.788,.132,.214,.377),(-.754,.174,.197,.410),(-.672,.177,.198,.432),(-.548,.182,.205,.459)]
        a=[section(z,w,l,h-.014) for z,w,l,h in bevelled]
        for p,q in zip(a,a[1:]):
            for i,c in enumerate(("black","blue_low","blue","blue_ridge","blue_light","blue_light","blue_ridge","blue","blue_low","black")):
                j=(i+1)%len(p);f(m,"Balogh independent long early rounded bonnet",c,(p[j],p[i],q[i],q[j]))
        f(m,"Balogh solid separate bonnet ends","blue",a[0]);f(m,"Balogh solid separate bonnet ends","blue",a[-1][::-1])
        B(m,"Brushed vintage nickel grille border","silver",0,-.788,.276,.029,.226,.384,.013)
        B(m,"Inset early rich black radiator face","black",0,-.805,.217,.012,.239,.378,.006)
        for x in (-.086,-.063,-.040,-.017,.006,.029,.052,.075):
            B(m,"Prewar Balogh eight nickel vertical radiator bars","alloy",x,-.813,.005,.006,.257,.363,.002)
        for s in (-1,1):
            T(m,"Independent ornate round shaped early Balogh headlights","steel",(s*.185,-.742,.299),(s*.185,-.782,.299),.046,.036,13)
            T(m,"Balogh early opaque glass headlamp lens","light",(s*.185,-.782,.299),(s*.185,-.788,.299),.032,.031,13)
            B(m,"Balogh independent double upright glazing weather seal","seal",s*.093,-.531,.173,.016,.425,.557,.011)
            B(m,"Balogh characteristic nearly vertical two original windscreen panes","glass",s*.093,-.543,.150,.011,.438,.548,.007)
            B(m,"Separate neutral early horizon sheet glass reflection","glint",s*.093,-.550,.135,.005,.526,.540,.003)
            B(m,"Separate period early balloon rounded door glass","glass",s*.229,-.405,.014,.176,.428,.540,.008)
            B(m,"Fine Balogh independent old sweeping additional low running board","blue_low",s*.236,-.029,.079,.627,.126,.164,.010)
            bar(m,"Small Balogh vintage mirror arm","silver",(s*.218,-.485,.459),(s*.274,-.486,.489),.008,.007)
            T(m,"Separate Balogh individual old round mirror head","alloy",(s*.274,-.495,.490),(s*.274,-.475,.490),.023,.022,11)
        return
    H=.625 if k==U else .67
    lo,hi=(-.688,-.578) if k==U else (-.747,-.623)
    def p(x,y,h):
        for (a,_,_,z),(b,_,_,zz) in zip(Q.CAB[k],Q.CAB[k][1:]):
            if a<=y<=b:return x,y,z+(zz-z)*(y-a)/(b-a)+h
        raise ValueError(y)
    for n,col,a,b,w,d in (("Independent rim binding of sloped two-pane truck windscreen","seal",lo-.006,hi+.007,.211,.006),
        ("Two genuinely separate dark safety windshield panes","glass",lo,hi,.200,.009),
        ("Retained narrow pane highlight on armored safety glass","glint",hi-.041,hi-.020,.195,.013)):
        zz=[a]+[i[0] for i in Q.CAB[k] if a<i[0]<b]+[b]
        for l,h in zip(zz,zz[1:]):
            for x,y in ((-w,-.006),(.006,w)):
                f(m,n,col,(p(x,l,d),p(y,l,d),p(y,h,d),p(x,h,d)))
    if k==U:
        B(m,"Boxy middle-era Uhl front intake body","black",0,-.791,.308,.027,.231,.364,.013)
        for y in (.248,.277,.306,.335):
            B(m,"Uhl separate silver midcentury radiator elements","silver",0,-.807,.281,.010,y,y+.008,.003)
        B(m,"Uhl independent corner cockpit top compressed brow","blue_ridge",0,-.516,.408,.099,.594,.634,.017)
    else:
        B(m,"Foster deep slotted extended front protective glass grille","black",0,-.793,.332,.026,.238,.388,.014)
        B(m,"Foster divided central deep molded fascia bar","blue_dark",0,-.812,.315,.009,.302,.318,.004)
        for x in (-.136,-.101,-.066,-.031,.004,.039,.074,.109,.144):
            B(m,"Foster contemporaneous lower square radiator inserts","alloy",x,-.811,.015,.009,.253,.295,.005)
        B(m,"Wide swept Foster graphite overhead canopy shade","roof",0,-.549,.438,.128,.647,.682,.018)
    for s in (-1,1):
        bar(m,"Do not overlap separate windshield wiper arms","black",p(s*.055,lo+.009,.017),p(s*.153,lo+.036,.015),.008,.009)
        B(m,"Individual later opaque front lamp panel shallow recess","seal",s*.203,-.783,.093,.029,.219,.342,.006)
        B(m,"Late molded opaque front lens strip warm bulb","light",s*.197,-.803,.060,.010,.265,.301,.004)
        B(m,"Small lower amber safety marker of boxed cab corner","amber",s*.236,-.793,.028,.012,.238,.263,.004)
        B(m,"Cab side glass dark molded protection frame","seal",s*.264,-.508,.023,.206,H-.186,H-.049,.012)
        B(m,"Clear distinct thick blue glazed later driver pane","glass",s*.279,-.511,.010,.186,H-.171,H-.058,.007)
        B(m,"Fleet sky reflection on thick cab side glass","glint",s*.286,-.509,.005,.149,H-.092,H-.077,.004)
        B(m,"Subtle trim flare around darkened steel driver opening","blue_low",s*.267,-.475,.013,.221,H-.312,H-.190,.008)
        B(m,"Separate sturdy solid late cab body panel opening","blue",s*.274,-.476,.009,.198,H-.303,H-.199,.008)
        B(m,"Small pin pull and latch of later cab","alloy",s*.283,-.413,.009,.053,H-.251,H-.231,.004)
        bar(m,"Original dark iron short hinge mirror bracket","black",(s*.256,-.642,.479),(s*.293,-.653,.488),.014,.014)
        B(m,"Heavy stubby dark close-mount coated mirror","black",s*.293,-.659,.026,.043,.461,.530,.006)
        B(m,"Closed mirror silver original rear-facing reflector","glint",s*.293,-.634,.016,.009,.471,.521,.004)

def model(k):
    m=Q.new();Q.underbody(m,k);cab(m,k);body(m,k)
    return m
def export(k,suffix,m):
    assert not suffix
    p=ROOT/"mods/luanttd_core/models"/f"bl_{k}.obj"
    Q.R.export_obj(p,Q.local_obj(m))
    p.write_text(f"# Original stock RC1 #{STOCK[k][0]} armoured transport; tools/build_stock_armoured_trucks_art.py\n"+
        p.read_text().split("\n",1)[1])
def build(k):
    Q.COL.clear();Q.COL.update(ORIG);Q.COL.update(COMMON);Q.COL.update(PALETTE[k])
    assert len(Q.COL)==64
    Q.R.COLORS[:]=Q.COL.values()
    Q.vehicle=model;Q.write=export
    Q.build(k)
if __name__=="__main__":
    stem=os.getenv("ARMOURED_TRUCK_STEM")
    for k in STOCK:
        if not stem or stem==k:build(k)
