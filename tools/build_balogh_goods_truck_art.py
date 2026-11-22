#!/usr/bin/env python3
"""Original period Balogh Goods Truck (OpenTTD 14.1 #138 and road row 22)."""
from math import cos, pi, sin, tau
from pathlib import Path
import os
import struct
import sys
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as soft

r=soft.rail
bpy=soft.bpy
Vector=soft.Vector
NAME="bl_balogh_goods_truck"
PAL={
    "Deep blue firewall":"334e62","Dark azure enamel":"365d79","Blue coachwork":"497fa3",
    "Sky blue wing highlights":"5b8eb0","Raised cured blue trim":"6496b5","High sky blue":"77a9c0",
    "Cab interior":"53574d","Rubber seals":"333b3d","Cab glazing":"344d59","Daylight glass":"5c8694","Glass glint":"8ab1b5",
    "Frame":"383e40","Cast seams":"545d5b","Gear steel":"677674","Dark tyre":"353439",
    "Tread graphite":"47494b","Hub enamel":"819493","Bright nickel":"b1b8aa","Brush primed iron":"626459",
    "Brass rivet":"a8a088","Headlamp glass":"f7e2a9","Rear ruby":"be4a43","Road amber":"d79a56","Offwhite paint":"d6ceb2",
    "Cured canvas":"404745","Canvas weathering":"4b514c","Canvas grazing light":"595f54","Canvas shade":"393f3e",
    "Dust in folds":"505348","Rope tan":"968971","Cord dark":"6d6458","Greased canvas buckle":"7a7e6c",
    "Floor timber":"716b58","Weathered plank end":"90907a","Small badge ochre":"c5af70","Night radiator grille":"343f44",
    "Sea blue plate":"33495a","Plate ivory":"e1d5b6","Bumper rust":"766858",
}
P={k:i for i,k in enumerate(PAL)}
r.COLORS[:]=PAL.values()
soft.P=P
B,T,R=soft.slab,soft.circular,soft.faces_xz
AXLES=(-.464,.442)
WHEEL_X=.222
WHEEL_R=.103


def face(m,name,mat,v):
    m.face(name,P[mat],v)


def axle_tube(m,name,mat,points,origin,segments=24):
    xc,zc,hc=origin
    rings=[]
    for d,r1 in points:
        rings.append([(xc+d,zc+cos(i*tau/segments)*r1,hc+sin(i*tau/segments)*r1) for i in range(segments)])
    for a,b in zip(rings,rings[1:]):
        for i in range(segments):
            j=(i+1)%segments
            face(m,name,mat,(a[i],a[j],b[j],b[i]))


def tube(m,name,mat,a,b,rad,other=None,steps=10):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    axis=d.cross(Vector((0,0,1) if abs(d.z)<.84 else (0,1,0))).normalized()
    cross=d.cross(axis)
    def rr(p,r):
        return [tuple(p+r*(axis*cos(i*tau/steps)+cross*sin(i*tau/steps))) for i in range(steps)]
    lo,hi=rr(a,rad),rr(b,rad if other is None else other)
    face(m,name,mat,lo[::-1]);face(m,name,mat,hi)
    for i in range(steps):
        j=(i+1)%steps
        face(m,name,mat,(lo[i],lo[j],hi[j],hi[i]))


def bar(m,name,mat,a,b,width,depth):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,0,1) if abs(d.z)<.86 else (0,1,0))).normalized()*width/2
    v=d.cross(u).normalized()*depth/2
    ps=(u+v,-u+v,-u-v,u-v)
    f,g=([tuple(q+p) for p in ps] for q in (a,b))
    face(m,name,mat,f[::-1]);face(m,name,mat,g)
    for i in range(4):
        j=(i+1)%4
        face(m,name,mat,(f[i],f[j],g[j],g[i]))


def panel(m,name,cross_sections,mat,bands):
    # Each section is a CCW X/elevation outline, with +Z order longitudinal.
    # Cab and bonnet use unique section silhouettes, not a slab painted blue.
    z,a=cross_sections[0];z1,b=cross_sections[-1]
    face(m,name,mat,[(x,z,h) for x,h in a])
    face(m,name,mat,[(x,z1,h) for x,h in b[::-1]])
    n=len(a)
    for (v,a),(w,b) in zip(cross_sections,cross_sections[1:]):
        for i in range(n):
            j=(i+1)%n
            face(m,name,bands[i%len(bands)],((a[i][0],v,a[i][1]),(b[i][0],w,b[i][1]),
                    (b[j][0],w,b[j][1]),(a[j][0],v,a[j][1])))


def rolled(w,lo,shoulder,hi):
    return [(-.85*w,lo),(.85*w,lo),(w,lo+.025),(w,shoulder-.035),
            (.89*w,shoulder),(.72*w,hi-.010),(.36*w,hi),(0,hi+.004),
            (-.36*w,hi),(-.72*w,hi-.010),(-.89*w,shoulder),(-w,shoulder-.035),(-w,lo+.025)]


def wheels(m):
    for i,z in enumerate(AXLES):
        T(m,"Working full width road axles","Frame",(0,z,WHEEL_R),.021,"x",-.224,.224,12)
        for s in (-1,1):
            x=s*WHEEL_X
            suffix="L" if s<0 else "R"
            axle_tube(m,"Ground contact tyre "+suffix,"Tread graphite",[
               (-.035,.076),(-.035,.091),(-.028,WHEEL_R),(.026,WHEEL_R),(.034,.091),(.034,.076),(-.035,.076)],
               (x,z,WHEEL_R))
            T(m,"Convex pressed wheel centre","Dark tyre",(x+s*.027,z,WHEEL_R),.082,"x",-.010,.010,22)
            T(m,"Painted dished hub pressing","Hub enamel",(x+s*.042,z,WHEEL_R),.054,"x",-.008,.008,20)
            T(m,"Grease hub cap","Bright nickel",(x+s*.051,z,WHEEL_R),.025,"x",-.006,.006,16)
            for j in range(6):
                t=tau*j/6
                T(m,"Visible road wheel nuts","Brass rivet",(x+s*.052,z+.036*cos(t),WHEEL_R+.036*sin(t)),
                  .005,"x",-.003,.004,8)
            if i==1:
                T(m,"Rear paired load tyres inboard of visible wheel","Dark tyre",(x-s*.061,z,WHEEL_R),
                  .095,"x",-.022,.022,22)
            # Real open rolled arches connect to wing without filling wheel hole.
            rows=[]
            for k in range(19):
                t=pi*k/18
                rows.append([(s*xw,z+(rr+.113)*cos(t),WHEEL_R+(rr+.113)*sin(t)) for xw,rr in (
                    (.168,.002),(.272,0),(.289,.025),(.239,.042),(.179,.034),(.168,.002))])
            colors=("Dark azure enamel","Blue coachwork","Sky blue wing highlights","Blue coachwork","Dark azure enamel")
            for a,b in zip(rows,rows[1:]):
                for j in range(5):
                    q=(a[j],b[j],b[j+1],a[j+1])
                    face(m,("Rounded front steel wheel wing" if not i else "Separate rear wheel spat"),colors[j],
                        q if s>0 else q[::-1])
            for h in (.130,.151,.173):
                B(m,"Forged wheel spring leaves","Gear steel",s*.174,z,.035,.191-(h-.130)*1.8,h,h+.005,.004)
            B(m,"Flexible mudflaps behind axle","Dark tyre",s*.218,z+.128,.143,.017,.035,.191,.006)


def chassis(m):
    R(m,"Heavy ladder chassis crossweb","Frame",soft.rect(0,-.030,.363,1.397,.037),.121,.194,"Cast seams")
    for s in (-1,1):
        B(m,"Long separate chassis C-section","Cast seams",s*.156,-.012,.043,1.396,.133,.198,.009)
        for z in (-.465,-.185,.262,.472):
            B(m,"Damped crossmember bolts","Brush primed iron",s*.179,z,.012,.018,.143,.187,.004)
        B(m,"Cab running board","Brush primed iron",s*.241,-.246,.083,.315,.120,.147,.008)
        for z in (-.370,-.319,-.268,-.217,-.166):
            B(m,"Cab running-board raised tread","Tread graphite",s*.243,z,.057,.012,.145,.152,.002)
    B(m,"Engine sump and gearbox","Cast seams",0,-.375,.214,.313,.107,.185,.013)
    T(m,"Rear differential spring housing","Frame",(0,.441,.113),.071,"x",-.081,.081,16)
    tube(m,"Exposed driveshaft below cargo","Gear steel",(0,-.224,.139),(0,.423,.116),.021,.014,14)
    tube(m,"Low old steel exhaust with curled tip","Cast seams",(.151,-.352,.101),(.174,.626,.084),.011,.012)
    for h in (.127,.150):
        B(m,"Rear load support leaf bracket","Brush primed iron",0,.599,.338,.043,h,h+.027,.009)
    for s in (-1,1):
        B(m,"Offset fuel side tank","Frame",s*.171,.170,.141,.237,.119,.222,.010)
        B(m,"Under-deck fuel tank straps","Gear steel",s*.180,.132,.127,.023,.121,.218,.007)


def angled_glass(m,s,p0,p1,p2,p3):
    outer=(p0,p1,p2,p3)
    face(m,"Vehicle window rubber moulding","Rubber seals",outer if s>0 else outer[::-1])
    cx,cz,ch=(sum(p[i] for p in outer)/4 for i in range(3))
    def scale(src,u,v=.0015):
        x,z,h=src
        return (cx+(x-cx)*u+s*v,cz+(z-cz)*u,ch+(h-ch)*u)
    inner=[scale(p,.81) for p in outer]
    face(m,"Raised inset side window glazing","Cab glazing",inner if s>0 else inner[::-1])
    band=[tuple(a+(b-a)*q for a,b in zip(inner[j],inner[3-j]))
          for j,q in ((0,.68),(1,.69),(1,.88),(0,.88))]
    face(m,"Sky reflection at top of side glass","Daylight glass",[(x+s*.001,z,h) for x,z,h in
           (band if s>0 else band[::-1])])


def bonnet(m):
    panel(m,"Crowned individually tapered engine bonnet",[
        (-.713,rolled(.112,.183,.337,.364)),
        (-.687,rolled(.139,.184,.357,.389)),
        (-.548,rolled(.149,.180,.377,.410)),
        (-.422,rolled(.175,.178,.389,.418))
    ],"Blue coachwork",["Dark azure enamel","Dark azure enamel","Blue coachwork","Blue coachwork",
         "Sky blue wing highlights","Sky blue wing highlights","Raised cured blue trim","Sky blue wing highlights",
         "Sky blue wing highlights","Blue coachwork","Blue coachwork","Dark azure enamel","Dark azure enamel"])
    for s in (-1,1):
        B(m,"Short side-valve bonnet ventilation pressed panel","Dark azure enamel",
          s*.147,-.588,.019,.165,.225,.336,.008)
        for z in (-.647,-.622,-.598,-.574,-.549,-.524):
            B(m,"Separate metal bonnet airflow louvers","Deep blue firewall",s*.157,z,.012,.008,.245,.318,.002)
            B(m,"Vent cap steel ridge","Sky blue wing highlights",s*.163,z+.004,.005,.006,.255,.310,.001)
        B(m,"Cab cowl moulding","Sky blue wing highlights",s*.174,-.436,.032,.031,.289,.373,.004)
        B(m,"Low extra bonnet stabilizer bracket","Brush primed iron",s*.172,-.575,.042,.037,.169,.217,.005)
    # Curved radiator face, pressed surround, dark throat and different fins.
    B(m,"Raised nickel nose radiator shell","Bright nickel",0,-.720,.221,.031,.195,.364,.016)
    B(m,"Machined recessed radiator air intake","Night radiator grille",0,-.740,.181,.018,.215,.346,.012)
    for i in range(8):
        x=(i-3.5)*.019
        B(m,"Stamped radiator horizontal slat backing","Cast seams",x,-.750,.005,.006,.230,.332,.001)
    for h in (.242,.268,.294,.320):
        B(m,"Separate nickel grille trim rails","Gear steel",0,-.754,.151,.006,h-.003,h+.003,.001)
    for s in (-1,1):
        x=s*.197
        tube(m,"Separate headlamp shell on curved wing",( "Blue coachwork"),
          (x,-.657,.254),(x,-.693,.254),.034,.029,18)
        T(m,"Lamp pressure nickel bezel","Bright nickel",(x,-.697,.253),.032,"z",-.010,.002,18)
        T(m,"Warm individual fluted headlamp lens","Headlamp glass",(x,-.711,.253),.024,"z",-.004,.002,18)
        for d in (-.009,.008):
            B(m,"Fluted lens retaining rods","Offwhite paint",x+d,-.715,.003,.003,.238,.268,.001)
    B(m,"Pressed chrome front bumper","Gear steel",0,-.748,.477,.065,.132,.169,.014)
    B(m,"Central black plate holder","Sea blue plate",0,-.783,.151,.012,.132,.165,.005)
    B(m,"Original lozenge over radiator","Small badge ochre",0,-.757,.041,.009,.335,.353,.006)


LETTERS={
 "B":("110","101","110","101","110"),"G":("111","100","101","101","111"),
 "D":("110","101","101","101","110"),"O":("010","101","101","101","010"),
 "S":("011","100","010","001","110"),"1":("010","110","010","010","111"),
 "3":("110","001","010","001","110"),"8":("010","101","010","101","010"),
 "A":("010","101","111","101","101"),"L":("100","100","100","100","111"),
}
def lettering_side(m,s,label,z,h,x,size):
    c=(len(label)*4-1)/2
    for j,character in enumerate(label):
        for row,seq in enumerate(LETTERS[character]):
            for i,on in enumerate(seq):
                if on=="0":continue
                z0=z+s*(j*4+i-c+.5)*size
                y=h+(4-row)*size
                B(m,"Genuine raised enamel side legend","Plate ivory",s*x,z0,.0018,.87*size,y,y+.93*size,.0003)

def little_numbers(m,label,y,z):
    for j,letter in enumerate(label):
        for row,seq in enumerate(LETTERS[letter]):
            for i,on in enumerate(seq):
                if on=="0":continue
                x=(j*4+i-5)*.004*(1 if z<0 else -1)
                h=y+(4-row)*.004
                B(m,"Raised vehicle number on historic road plate","Plate ivory",x,z,.0034,.0019,h,h+.0035,.0002)

def cab(m):
    points=[(-.456,rolled(.186,.190,.499,.555)),(-.412,rolled(.223,.181,.543,.593)),
            (-.313,rolled(.238,.181,.556,.607)),(-.160,rolled(.237,.181,.558,.607)),
            (-.116,rolled(.205,.190,.528,.578))]
    panel(m,"Rolled profile of pressed cab and rounded roof crown",points,
       "Blue coachwork",["Deep blue firewall","Dark azure enamel","Blue coachwork",
       "Blue coachwork","Sky blue wing highlights","Raised cured blue trim","Sky blue wing highlights",
       "Raised cured blue trim","Raised cured blue trim","Sky blue wing highlights","Blue coachwork","Blue coachwork",
       "Deep blue firewall"])
    for s in (-1,1):
        B(m,"Dark welded cab door perimeter","Dark azure enamel",s*.234,-.267,.019,.258,.224,.412,.012)
        B(m,"Painted lower cab door inset","Blue coachwork",s*.245,-.260,.008,.220,.240,.399,.010)
        B(m,"Small under-door bright blue flashing","Sky blue wing highlights",s*.250,-.265,.004,.212,.239,.245,.001)
        angled_glass(m,s,(s*.242,-.383,.411),(s*.244,-.153,.411),(s*.239,-.165,.535),(s*.224,-.374,.522))
        tube(m,"Thin cab split-light stile","Bright nickel",(s*.241,-.336,.413),(s*.231,-.336,.527),.0033)
        B(m,"Pressed chrome cab latch handle","Bright nickel",s*.251,-.211,.012,.043,.391,.405,.003)
        B(m,"Yellowed original Balogh chassis badge mount","Sea blue plate",s*.254,-.273,.010,.067,.279,.320,.005)
        lettering_side(m,s,"B",-.274,.289,.260,.004)
        tube(m,"Spring mirror stalks","Gear steel",(s*.233,-.390,.451),(s*.274,-.408,.477),.0065,steps=7)
        tube(m,"Mirror back stem to mount","Gear steel",(s*.274,-.408,.477),(s*.275,-.412,.503),.0057,steps=8)
        T(m,"Oval auxiliary exterior road mirror","Blue coachwork",(s*.276,-.414,.500),.021,"z",-.010,.007,16)
        T(m,"Road mirror polished front","Bright nickel",(s*.276,-.409,.500),.016,"z",0,.004,16)
        # Separate slanted, two-piece curved front glass against cowl.
        a,b=s*.010,s*.167
        # All panes and their supporting frame are ahead of the closed
        # cab's first plane, with conventional slight rearward tilt.
        outline=((a,-.478,.416),(b,-.476,.418),(s*.149,-.465,.530),(s*.010,-.464,.541))
        order=outline if s>0 else outline[::-1]
        face(m,"Split windscreen black rubber and posts","Rubber seals",order)
        cx,cz,ch=(sum(v[i] for v in outline)/4 for i in range(3))
        screen=[(cx+(x-cx)*.87,cz+(z-cz)*.87-.004,ch+(y-ch)*.87) for x,z,y in outline]
        face(m,"Pressed double windscreen glass","Cab glazing",screen if s>0 else screen[::-1])
        sky=[tuple(p+(q-p)*k for p,q in zip(screen[i],screen[3-i]))
             for i,k in ((0,.65),(1,.68),(1,.88),(0,.88))]
        face(m,"Broad reflected sky on windshield","Daylight glass",[(x,z-.0015,y) for x,z,y in (sky if s>0 else sky[::-1])])
        bar(m,"Windscreen blades","Bright nickel",(s*.035,-.481,.434),(s*.106,-.478,.459),.006,.006)
        bar(m,"Windscreen wiper spring arms","Rubber seals",(s*.084,-.485,.416),(s*.090,-.481,.440),.005,.005)
        bar(m,"Pressed body-colour windshield surround","Raised cured blue trim",
            (s*.177,-.471,.415),(s*.156,-.463,.530),.011,.014)
    bar(m,"Split windshield central painted mullion","Sky blue wing highlights",(0,-.474,.411),(0,-.462,.548),.014,.015)
    B(m,"Pitched cab rear molded glass surround","Rubber seals",0,-.108,.219,.014,.437,.538,.011)
    B(m,"Rear glass behind goods cab","Cab glazing",0,-.100,.191,.011,.449,.525,.009)
    B(m,"Thin vehicle rear glass reflection","Daylight glass",0,-.093,.166,.004,.499,.514,.003)


def cover(m):
    # Genuine crate compartment, enclosed by laced canvas and lower blue
    # boarding. No external payload as stock image 5 has no loaded sprite.
    R(m,"Hardwood cargo floor recessed from rails","Floor timber",soft.rect(0,.304,.499,.819,.033),
      .212,.253,"Weathered plank end")
    for z in (-.031,.057,.146,.231,.316,.402,.491,.576,.657):
        B(m,"Individual board seams inside cargo compartment","Floor timber",0,z,.439,.013,.253,.260,.002)
    for s in (-1,1):
        B(m,"Box body strengthened sill","Deep blue firewall",s*.241,.312,.051,.836,.222,.258,.006)
        B(m,"Blue lower enclosed flat panel","Blue coachwork",s*.243,.312,.031,.835,.255,.458,.016)
        for h,col in ((.267,"Dark azure enamel"),(.324,"Deep blue firewall"),(.381,"Dark azure enamel"),(.444,"High sky blue")):
            B(m,"Horizontal cargo coachwork boarding seam",col,s*.259,.311,.006,.812,h,h+.007,.001)
        for j,z in enumerate((-.075,.061,.200,.337,.467,.596,.706)):
            B(m,"Genuine blue vertical pressed freight ribs","Dark azure enamel" if j%2 else "Sky blue wing highlights",
              s*.265,z,.015,.025,.248,.463,.005)
            B(m,"Front edge reflection of loaded body ribs","Raised cured blue trim",
              s*.274,z-.007,.003,.008,.260,.413,.001)
            T(m,"Lorry board stave rivets","Brass rivet",(s*.274,z,.425),.0048,"x",0,.003,8)
        B(m,"Company-blue side nameplate mount","Sea blue plate",s*.276,.321,.010,.289,.326,.396,.007)
        B(m,"Freight fleet side sign thin bevel","Blue coachwork",s*.282,.321,.002,.277,.331,.391,.006)
        lettering_side(m,s,"GOODS",.321,.344,.284,.0102)
    B(m,"Forward cargo body blue bulkhead","Blue coachwork",0,-.098,.477,.027,.234,.459,.011)
    # OpenGFX dark goods silhouette, sculpted canvas on five visible bows.
    zs=(-.108,-.089,-.013,.085,.182,.292,.408,.514,.607,.686,.727)
    fa=(.944,.985,1.00,1.006,.991,1.010,1.001,.988,1.003,.974,.926)
    top=((-.260,.436),(-.261,.492),(-.254,.551),(-.227,.605),(-.174,.648),(-.084,.665),
         (0,.668),(.084,.665),(.174,.648),(.227,.605),(.254,.551),(.261,.492),(.260,.436))
    rings=[]
    for j,z in enumerate(zs):
        for_i=[]
        for i,(x,h) in enumerate(top):
            hand=(1 if i>6 else -1)
            wrinkle=.010*cos((i-6)*2.13+j*1.04)*(1 if abs(x)>.22 or i in (2,10) else .51)
            xx=x*fa[j]+(hand*.0029*sin(j*1.47+i*.91) if abs(x)>.24 else 0)
            z1=z+(.004*cos(i*1.36+j) if j not in (0,len(zs)-1) else 0)
            hh=.439+(h-.439)*fa[j]+wrinkle*.38
            for_i.append((xx,z1,hh))
        rings.append(for_i)
    for j,(lo,hi) in enumerate(zip(rings,rings[1:])):
        for i in range(len(lo)-1):
            p=(lo[i],hi[i],hi[i+1],lo[i+1])
            # Orient each panel outwards. Gentle color bands and narrow bow
            # seams retain a soft, taut outline rather than a cube.
            c=("Canvas shade" if i in (0,11) else ("Canvas grazing light" if (i in (3,8) and j%3==1)
                else "Cured canvas" if (i+j//3)%4 else "Canvas weathering"))
            face(m,"Wrapped steel hoop weathered canvas surfaces",c,p[::-1])
    for j in (1,3,5,7,9):
        ps=rings[j]
        for i in range(12):
            a,b=ps[i],ps[i+1]
            off=lambda q:(q[0]+.0019*(1 if q[0]>0 else -1),q[1],q[2]+.0035)
            tube(m,"Raised stitched hoop seams along canvas",("Canvas weathering" if j%3==1 else "Canvas grazing light"),
                off(a),off(b),.0053,steps=7)
    for s in (-1,1):
        for z in (-.078,.073,.218,.369,.519,.660):
            # Rope tie points and genuinely angled tension lines down each wall.
            x=s*.264
            tube(m,"Individually tensioned lower tarp cords","Rope tan",(x,z-.023,.471),(s*.274,z,.422),.0039)
            tube(m,"Individual rolled tension cord eyelet","Greased canvas buckle",(s*.273,z-.004,.420),
                 (s*.272,z+.016,.433),.0047,steps=8)
        bar(m,"Canvas brown lower rope hem","Dust in folds",(s*.259,-.096,.441),(s*.260,.712,.442),.009,.008)
    # Closed front and pleated rear curtain, laced to the narrow steel frame.
    for j in (0,len(rings)-1):
        ps=rings[j]
        rear=j>0
        z=zs[j]
        center=(0,z+(.004 if rear else -.004),.462)
        for i in range(len(ps)-1):
            col=("Canvas weathering" if i in (2,5,8,10) else "Cured canvas")
            vertices=(center,ps[i],ps[i+1])
            face(m,"Closed cargo curtain in real cloth folds",col,vertices if rear else vertices[::-1])
        if rear:
            for j,x in enumerate((-.146,-.109,-.067,0,.064,.109,.153)):
                h=.637-.31*abs(x)
                bar(m,"Raised vertical rear cargo curtain folds","Canvas shade" if j%2 else "Canvas weathering",
                    (x,.730,.448),(x*.93,.730,h),.009,.011)
            for z2 in (.728,.731):
                tube(m,"Central lashed rear weather flap","Rope tan",(0,z2,.450),(0,z2+.001,.650),.0039)
            for k in range(7):
                h=.477+k*.022
                tube(m,"Tail cover crossed cords","Cord dark",(-.022,z+.010,h),(.022,z+.012,h+.013),.0041)
                tube(m,"Tail cover crossed cords","Rope tan",(-.022,z+.013,h+.013),(.022,z+.013,h),.0034)
    # Rear doors beneath the weather curtain, with independent latch hardware.
    for s in (-1,1):
        B(m,"True recessed blue lower tailgate","Blue coachwork",s*.117,.711,.225,.037,.248,.433,.014)
        B(m,"Rolled lower tailgate rim","Dark azure enamel",s*.116,.733,.222,.007,.257,.266,.002)
        for x in (.075,.166):
            B(m,"Stamped blue tailgate door flutes","Sky blue wing highlights",s*x,.735,.011,.009,.267,.405,.005)
        for x in (.182,.220):
            T(m,"Metal tailgate door hinge pin","Gear steel",(s*x,.737,.279),.010,"x",-.013,.013,10)
        B(m,"Low tail lamp iron wing plate","Deep blue firewall",s*.206,.731,.081,.033,.174,.240,.007)
        T(m,"Tail ruby prism and nickel ring","Rear ruby",(s*.207,.751,.218),.023,"z",0,.008,18)
        T(m,"Orange separated rear turn lamp","Road amber",(s*.209,.748,.183),.011,"z",0,.007,15)
    B(m,"Centre lifting tailgate handle","Gear steel",0,.742,.081,.015,.306,.325,.005)
    B(m,"Old rubbed rear steel bumper","Bumper rust",0,.745,.458,.049,.129,.163,.008)
    B(m,"Goods number plate holder","Sea blue plate",0,.760,.135,.014,.180,.218,.005)


def build():
    m=r.Mesh(r.terrain_height(0))
    chassis(m); wheels(m); cab(m);bonnet(m);cover(m)
    little_numbers(m,"138",.138,-.791)
    little_numbers(m,"138",.186,.769)
    return m


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    out=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(PAL),8,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (r.TEXTURES/(NAME+"_atlas.png")).write_bytes(out)


def review(scene,collection):
    for x,z,turn in ((-.64,.115,0),(.65,-.125,pi)):
        o=r.instance(scene,collection,x,z)
        o.rotation_euler[2]=turn
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.006))
    stage=bpy.data.materials.new("Blue-grey hard-packed exhibition road")
    stage.diffuse_color=(.178,.207,.207,1)
    bpy.context.object.data.materials.append(stage)
    bpy.ops.object.camera_add(location=(2.37,-5.27,3.21))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,-.04,.29))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=2.68;scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1450,1020
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.22
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Workday muted cloud")
    scene.world.color=(.163,.204,.249)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Balogh Goods Truck, dark cover over two-axle British lorry"
    mats=r.materials()
    for i,name in enumerate(PAL):
        mat=mats[i];mat.name=name
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Metallic"].default_value=.52 if any(p in name for p in ("nickel","rivets","steel","hub")) else .08
        node.inputs["Roughness"].default_value=.93 if "canvas" in name.lower() else .60
    m=build()
    special=r.stash(m,mats,"Balogh Goods Truck #138 / full editable road lorry")
    r.export_obj(r.MODELS/(NAME+".obj"),soft.local_obj(m))
    atlas()
    review(scene,special)
    bpy.ops.wm.save_as_mainfile(filepath=str(r.ROOT/"art"/"balogh_goods_truck.blend"),compress=True)
    if target:=os.getenv("BALOGH_GOODS_RENDER"):
        scene.render.filepath=target
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()
