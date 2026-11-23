#!/usr/bin/env python3
"""Original Blender models for the RC1 MPS #126 and Perry #128 mail vans."""
from math import cos,sin,tau,pi
from pathlib import Path
from mathutils import Vector as V
import os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_late_freight_art as Q

MPS="stock_mps_mail_truck"
PERRY="stock_perry_mail_truck"
STOCK={MPS:(126,"MPS Mail Truck",(-.472,.416),.110),
       PERRY:(128,"Perry Mail Truck",(-.503,.454),.125)}
Q.ROOT=ROOT
Q.STOCK=STOCK
Q.CARGO={}
Q.CAB={
  PERRY:((-.795,.198,.201,.393),(-.780,.241,.192,.447),(-.741,.258,.186,.489),
      (-.690,.272,.189,.549),(-.628,.274,.195,.612),(-.578,.274,.199,.640),
      (-.479,.268,.205,.642),(-.344,.258,.211,.615),(-.298,.239,.223,.560))}
ORIGINAL=dict(Q.COL)
MPS_PAINT=dict(blue="903b38",blue_low="5c3033",blue_light="ad5751",blue_dark="74383b",blue_ridge="9a4643",
               steel_cool="a87a73",cage="843a38",cage_blue="a4544a",black="303033",roof="383538",
               roof_seam="454144",warm="e4c894",label="e2cb93",latch="ab956e",latch_light="b8a77f",
               floor="493c3c",rub="413939",glint="acb6b2",rim="775755",lip="9a8065",tyre="303032",
               tread="4a3f3f",frame="413638",alloy="a08e7c",silver="b2a292",woodsplit="71554c")
PERRY_PAINT=dict(blue="46749d",blue_low="2d4967",blue_light="6596b3",blue_dark="3d6382",blue_ridge="5283a7",
                 steel_cool="6d94ae",cage="4c7698",cage_blue="769bbb",black="25323a",roof="304351",
                 roof_seam="3e505e",warm="e8d9b1",label="ded8bb",latch="9dabb1",floor="4c5b60",
                 rub="394a53",glint="9cb9c2",rim="a5aaae",lip="9daeb7",tyre="252b2f",tread="40484c")
MPS_PAINT.pop("latch_light") # the shared atlas remains exactly 64 cells
B,T,bar,face=Q.B,Q.T,Q.bar,Q.face
DIGITS={
   "M":("11011","11111","10101","10001","10001","10001","10001"),
   "A":("01110","11011","10001","11111","10001","10001","10001"),
   "I":("11111","00100","00100","00100","00100","00100","11111"),
   "L":("10000","10000","10000","10000","10000","10001","11111")}
def letter_side(m,n,x,z,h,s,text,scale,c):
    for j,char in enumerate(text):
        for r,row in enumerate(DIGITS[char]):
            for i,a in enumerate(row):
                if a=="0":continue
                zz=z+s*(j*6+i-(6*len(text)-1)/2)*scale
                y=h+(3-r)*scale
                x0=x*s
                p=[(x0,zz-scale/2,y-scale*.48),(x0,zz+scale/2,y-scale*.48),
                        (x0,zz+scale/2,y+scale*.48),(x0,zz-scale/2,y+scale*.48)]
                face(m,n,c,p[::s])

def body_profile(m,n,c,stations,k=12):
    prev=None
    for z,w,l,h in stations:
        q=[(w*cos(tau*i/k),z,(h+l)/2+((h-l)/2)*sin(tau*i/k)) for i in range(k)]
        if prev:
            for i in range(k):
                j=(i+1)%k
                face(m,n,c[(i+k//4)%len(c)],(prev[i],q[i],q[j],prev[j]))
        else:face(m,n+" front",c[0],q)
        prev=q
    face(m,n+" rear",c[0],prev[::-1])

def old_undercarriage(m):
    rad=.110
    ax=STOCK[MPS][2]
    B(m,"Prewar riveted open ladder frame","frame",0,.011,.332,1.363,.104,.192,.019)
    for s in (-1,1):
        B(m,"Drawn plain-steel channel rails","black",s*.156,.006,.041,1.368,.122,.176,.007)
        B(m,"Long wheel-gap period running boards","blue_low",s*.235,-.030,.088,.645,.122,.147,.005)
        for h in (.141,.149):
            B(m,"Raised polished running board rolled edge","alloy",s*.272,-.035,.013,.618,h,h+.006,.002)
        for z in (-.273,-.094,.088,.233):
            B(m,"Original tiny studs on early footboards","lip",s*.230,z,.064,.009,.143,.151,.002)
        for z in ax:
            bar(m,"Separately forged suspension leaf brackets","steel",(s*.152,z-.127,.134),(s*.152,z+.119,.146),.026,.020)
            T(m,"Black shoulder prewar balloon tyres","tyre",(s*.205-.034,z,rad),(s*.205+.034,z,rad),rad-.004,rad-.004,18)
            side="L" if s<0 else "R"
            # A 16-sided radial contact tread exactly touches ground at Y=0.
            a=[(s*.205-.021,z+rad*cos(i*tau/16),rad+rad*sin(i*tau/16)) for i in range(16)]
            b=[(s*.205+.021,y,h) for _,y,h in a]
            face(m,"Ground contact tyre "+side,"tread",a[::-1])
            face(m,"Ground contact tyre "+side,"tread",b)
            for i in range(16):
                j=(i+1)%16
                face(m,"Ground contact tyre "+side,"tread",(a[i],a[j],b[j],b[i]))
            T(m,"Stamped dark crimson solid-era steel rim","rim",(s*.205+s*.033,z,rad),(s*.205+s*.046,z,rad),.059,.052,16)
            T(m,"Original rounded spun nickel grease cap","silver",(s*.205+s*.045,z,rad),(s*.205+s*.058,z,rad),.027,.020,14)
            for i in range(6):
                a0=i*tau/6
                y=rad+.040*sin(a0); zz=z+.040*cos(a0)
                T(m,"Spun cap individual drilled wheel nuts","lip",(s*.205+s*.043,zz,y),(s*.205+s*.049,zz,y),.005,.005,6)
            for i in range(15):
                a0=.035+i*3.04/15;a1=.035+(i+1)*3.04/15
                def p(t,d,r):return (s*(.205+d),z+r*cos(t),rad+r*sin(t))
                face(m,"Real sweeping prewar mudguard crowns","blue_low",
                    [p(a0,-.046,.139),p(a1,-.046,.139),p(a1,.065,.150),p(a0,.065,.150)][::s])
                face(m,"Rolled red outer front fender trim","blue_light",
                    [p(a0,.065,.150),p(a1,.065,.150),p(a1,.074,.141),p(a0,.074,.141)][::s])
    B(m,"Cooled narrow prewar front steel bumper","silver",0,-.760,.389,.025,.153,.187,.009)
    B(m,"Rear folded steel cargo bumper","frame",0,.738,.478,.026,.133,.174,.008)
    for s in (-1,1):
        B(m,"Round period ruby taillight bracket","black",s*.171,.727,.063,.028,.157,.224,.009)
        T(m,"Round incandescent period tail reflector","red",(s*.176,.743,.192),(s*.176,.751,.192),.025,.024,12)

def old_mail(m):
    old_undercarriage(m)
    # Individual short bonnet profile on its own chassis; the tall stamped
    # rounded-panel body begins at a fixed upright cabin bulkhead.
    bonnet=((- .778,.131,.197,.374),(-.749,.157,.197,.404),(-.675,.166,.201,.420),
           (-.594,.177,.207,.434),(-.490,.181,.210,.455))
    B(m,"Independent pre-war slab plated bonnet bottom","blue_low",0,-.609,.320,.342,.200,.275,.015)
    for j,(z,x,l,h) in enumerate(bonnet[:-1]):
        w,y,d,k=bonnet[j+1]
        ring=lambda z,x,l,h:[(-x*.87,z,l),(x*.87,z,l),(x,z,h-.061),(x*.76,z,h),
                            (-x*.76,z,h),(-x,z,h-.061)]
        a,b=ring(z,x,l,h),ring(w,y,d,k)
        for i,c in enumerate(("blue_low","blue","blue_ridge","blue_light","blue_ridge","blue_dark")):
            n=(i+1)%6;face(m,"Sculpted rounded louver bonnet separate from van",c,(a[n],a[i],b[i],b[n]))
    B(m,"Prewar upright chrome radiator surround","silver",0,-.773,.265,.034,.240,.397,.015)
    B(m,"Warm deep upright dark radiator centre","black",0,-.792,.225,.012,.253,.381,.007)
    for j in range(8):
        x=-.084+.024*j
        B(m,"Original eight separate nickel grille bars","alloy",x,-.800,.005,.007,.268,.370,.002)
    for s in (-1,1):
        for z in (-.697,-.650,-.602,-.554):
            B(m,"Stamped side bonnet cooling vents","blue_low",s*.166,z,.014,.026,.285,.355,.004)
        T(m,"Period separate headlamp body polished rim","lip",(s*.173,-.736,.314),(s*.173,-.779,.314),.049,.040,14)
        T(m,"Period separate round warm headlamp lens","light",(s*.173,-.779,.314),(s*.173,-.783,.314),.036,.035,14)
        B(m,"Separate front mud wing support radiator strut","steel",s*.204,-.727,.031,.105,.252,.280,.004)
    # Doors and body use sharp lower panel rebates against a softer roof.
    B(m,"Original short rounded deep red mail body","blue",0,.129,.442,1.184,.237,.573,.018)
    B(m,"Separate prewar base body low enamel passenger panel","blue_low",0,.129,.462,1.187,.234,.286,.016)
    B(m,"Rectangular body crown beneath rolled canvas","blue_dark",0,.129,.462,1.192,.542,.601,.018)
    body_profile(m,"Closed sloping cloth van canopy",("roof_seam","roof","roof","roof","roof_seam"),
        ((-.453,.205,.570,.595),(-.416,.235,.574,.626),(-.362,.240,.574,.636),
          (.625,.238,.574,.636),(.688,.229,.568,.625),(.724,.207,.567,.592)))
    for s in (-1,1):
        B(m,"Nearly upright separate windscreen frames","seal",s*.108,-.470,.202,.023,.435,.581,.009)
        B(m,"Split old safety glass face nearly vertical","glass",s*.107,-.485,.175,.013,.447,.566,.005)
        B(m,"Prewar windshield one horizontal reflection per window","glint",s*.107,-.495,.152,.005,.542,.556,.002)
        bar(m,"Separate small prewar wiper","black",(s*.035,-.497,.452),(s*.120,-.498,.488),.007,.009)
        B(m,"Cab side window individual original steel jamb","seal",s*.223,-.336,.021,.216,.412,.560,.012)
        B(m,"Period flat side glass pair","glass",s*.236,-.337,.012,.186,.431,.549,.008)
        B(m,"Period lower side enamel door seam","blue_low",s*.225,-.337,.012,.232,.277,.420,.006)
        B(m,"Original lower door skins","blue",s*.231,-.340,.009,.212,.291,.417,.005)
        B(m,"Brass cab door handle","lip",s*.239,-.270,.009,.035,.373,.391,.004)
        B(m,"Separated hinged postal loading side pressings","blue_dark",s*.225,.271,.015,.740,.278,.552,.008)
        B(m,"Colored early long red panel in recessed own frame","blue",s*.235,.271,.010,.700,.290,.542,.009)
        B(m,"Narrow light painted panel line below letter type","warm",s*.241,.271,.003,.628,.397,.408,.001)
        letter_side(m,"Individually painted cream postal MAIL lettering",.242,.270,.466,s,"MAIL",.013,"label")
        for z in (-.010,.559):
            B(m,"Light strip of aged aluminium on cargo shoulder","alloy",s*.238,z,.010,.034,.296,.384,.004)
        bar(m,"Small period individually screwed mirror arm","steel",(s*.209,-.448,.492),(s*.273,-.455,.511),.008,.009)
        T(m,"Small round vintage upright rear-view mirror","silver",(s*.273,-.466,.511),(s*.273,-.444,.511),.026,.025,12)
        B(m,"Crimson original postal rear twin gate leaves","blue_dark",s*.111,.722,.215,.029,.264,.557,.011)
        B(m,"Period rear pale vertical metal latch","silver",s*.031,.742,.012,.011,.302,.517,.003)
        for h in (.322,.451):
            B(m,"Visible twin brass back-door hinges","lip",s*.203,.743,.062,.015,h,h+.031,.005)
    B(m,"Neutral back registration stamped tin frame","label",0,.747,.128,.005,.223,.244,.002)

def modern_cab(m):
    Q.shell(m,PERRY)
    c=Q.CAB[PERRY]
    def p(x,z,d):
        for (a,_,_,h),(b,_,_,k) in zip(c,c[1:]):
            if a<=z<=b:return x,z,h+(k-h)*(z-a)/(b-a)+d
        raise ValueError(z)
    for n,col,lo,hi,w,d in (("Moulded aerodynamic glass collar","seal",-.747,-.588,.209,.006),
       ("Two separately split sloping Perry windscreen panes","glass",-.740,-.594,.198,.010),
       ("Slim Perry daytime windscreen horizon highlight","glint",-.638,-.601,.190,.014)):
        z=[lo]+[a[0] for a in c if lo<a[0]<hi]+[hi]
        for zl,zh in zip(z,z[1:]):
            for xl,xh in ((-w,-.006),(.006,w)):
                face(m,n,col,(p(xl,zl,d),p(xh,zl,d),p(xh,zh,d),p(xl,zh,d)))
    B(m,"Fast-raked sky-cobalt wind-cheater lid","blue_light",0,-.532,.450,.111,.616,.655,.016)
    B(m,"Five-port low air intake pressure moulding","black",0,-.794,.324,.026,.239,.367,.015)
    for j in range(5):
        h=.255+j*.022
        B(m,"Independent Perry radiator horizontal blade","steel",0,-.808,.300,.008,h,h+.006,.002)
    B(m,"Neutral front post-delivery number plate","label",0,-.815,.105,.007,.194,.220,.003)
    for s in (-1,1):
        bar(m,"Separate physically modeled windshield wiper","black",p(s*.047,-.729,.015),p(s*.157,-.706,.015),.008,.009)
        B(m,"Perry separate opaque projector lamp castings","rub",s*.200,-.778,.091,.041,.219,.337,.010)
        B(m,"Top daylight projector headlamp wing","light",s*.192,-.802,.064,.010,.272,.312,.005)
        B(m,"Low smoked spare light lens","pale",s*.193,-.802,.051,.010,.241,.266,.004)
        B(m,"Original yellow corner reflector","amber",s*.233,-.787,.024,.013,.261,.294,.004)
        B(m,"Cobalt pressed dark side opening seam","seal",s*.264,-.492,.015,.245,.314,.428,.009)
        B(m,"Heavy sheltered twin cab doors","blue",s*.274,-.491,.010,.220,.321,.420,.007)
        B(m,"Modern shaded door window seal","seal",s*.267,-.508,.019,.225,.430,.580,.010)
        B(m,"Modern blue glass with inset window side reflection","glass",s*.282,-.515,.012,.190,.446,.570,.010)
        B(m,"Late van original blue side glass angled top reflection","glint",s*.288,-.521,.004,.154,.530,.551,.005)
        B(m,"Electronic keyless fleet latch","latch",s*.282,-.419,.011,.047,.397,.418,.004)
        bar(m,"Low mirror hinge with visible mount","steel",(s*.256,-.655,.470),(s*.294,-.661,.479),.015,.015)
        B(m,"Smoked plastic rounded bulk blind spot mirrors","black",s*.294,-.662,.025,.041,.446,.515,.007)
        B(m,"Independent rear-facing late van mirror glass","glint",s*.294,-.640,.014,.008,.452,.498,.003)

def modern_mail(m):
    Q.underbody(m,PERRY);modern_cab(m)
    B(m,"Pressed steel closed rectangular main van delivery box","cage",0,.206,.500,1.062,.235,.622,.016)
    B(m,"Lower apron blue molded van-side rocker reinforcement","blue_low",0,.207,.512,1.069,.225,.280,.014)
    B(m,"Charcoal stormproof overhanging carrier van canopy","roof",0,.208,.520,1.079,.618,.670,.021)
    for x in (-.207,-.136,-.068,0,.068,.136,.207):
        B(m,"Seven real formed late van charcoal roof belts","roof_seam",x,.208,.014,.994,.667,.676,.004)
    for s in (-1,1):
        B(m,"Vivid grounded parcel van outer belt","blue_dark",s*.253,.204,.012,1.041,.304,.379,.006)
        B(m,"Original long painted post delivery stripe","warm",s*.261,.204,.005,1.012,.373,.402,.004)
        B(m,"Independent recessed carrier van cargo access panel","teal",s*.257,.315,.012,.752,.406,.581,.009)
        B(m,"Light edge lip over modern mail access panel","pale",s*.264,.315,.008,.721,.548,.565,.004)
        B(m,"Raised long van cargo stripe edge top clamps","latch",s*.268,.257,.006,.651,.399,.409,.002)
        letter_side(m,"Original plated mail fleet logotype individual areas",.266,.325,.481,s,"MAIL",.015,"label")
        for z in (-.269,-.094,.656,.717):
            B(m,"External blue vapor-formed box pilasters","cage_blue",s*.263,z,.016,.027,.271,.617,.004)
        B(m,"Interior protected rear black edge van lift rail","black",s*.228,.744,.035,.031,.286,.600,.004)
        B(m,"Modern twin back swinging mail halfdoors","ramp",s*.111,.743,.227,.029,.282,.604,.007)
        B(m,"Raised side door handle at post stop","silver",s*.058,.766,.014,.012,.313,.557,.003)
        B(m,"Late van individual folded gas hinge leaves","alloy",s*.216,.770,.042,.014,.540,.576,.004)
        B(m,"Late van individual folded gas hinge leaves","alloy",s*.216,.770,.042,.014,.343,.379,.004)
        B(m,"Raised separate ribbon LEDs at door's outer edge","red",s*.230,.770,.031,.013,.283,.350,.004)
    B(m,"Folded sprung delivery step at underbody","black",0,.786,.447,.035,.199,.253,.008)
    B(m,"Bright visible nonslip arrow-step brushed edge","latch",0,.803,.403,.009,.218,.232,.003)
    B(m,"Perry blank bulk delivery identity plate rear","label",0,.769,.128,.009,.209,.235,.003)

def export(stem,ext,m):
    assert not ext
    p=ROOT/"mods/luanttd_core/models"/f"bl_{stem}.obj"
    Q.R.export_obj(p,Q.local_obj(m))
    p.write_text(f"# Original RC1 {STOCK[stem][0]} mail van; tools/build_stock_mail_companions_art.py\n"+
       p.read_text().split("\n",1)[1])
def model(stem):
    m=Q.new()
    (old_mail if stem==MPS else modern_mail)(m)
    return m
def build(stem):
    palettes=MPS_PAINT if stem==MPS else PERRY_PAINT
    Q.COL.clear();Q.COL.update(ORIGINAL);Q.COL.update(palettes)
    assert len(Q.COL)==64
    Q.R.COLORS[:]=Q.COL.values()
    Q.vehicle=model;Q.write=export
    Q.build(stem)
if __name__=="__main__":
    for name in STOCK:build(name)
