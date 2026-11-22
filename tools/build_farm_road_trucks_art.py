#!/usr/bin/env python3
"""Original 1935 Hereford grain lorry #141 and Talbott livestock van #135.
blender -b -t 3 --python-exit-code 1 --python tools/build_farm_road_trucks_art.py
Optional FARM_TRUCK_REVIEW=<png filename>. Mount unit .42; -Z nose and h=0.
"""
from math import cos, pi, sin, tau
import os
from pathlib import Path
from random import Random
import struct
import sys
import zlib

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_balogh_goods_truck_art as G

R,S=G.r,G.soft
ROOT=R.ROOT
GRAIN="hereford_grain_truck"
VAN="talbott_livestock_van"
PALETTE={
  "Deep blue":"304f65","Company blue":"487da0","Blue highlight":"639ab8","Van blue":"4b7390",
  "Van highlight":"6e9bb3","Bonnet nickel":"b3b7a7","Grille gunmetal":"465355",
  "Faded alloy":"7e8988","Steel bed edge":"858f91","Wet steel":"606d73",
  "Dry steel":"76828a","Recessed bed steel":"525d63","Pale steel trim":"a1a7a0",
  "Rubber seals":"2b383d","Cab glazing":"324c58","Glass sky":"658e9d","Daylight glass":"658e9d",
  "Darker door":"375d77","Cab panel shade":"456574","Frame iron":"3e4548",
  "Driveshaft":"626863","Ground tread":"383d40","Tyre sidewall":"2d3336","Road hub":"788684",
  "Hub light":"a6aaa1","Warm headlight":"f7e0a6","Red lens":"b94f45","Orange lens":"d59b58",
  "Black plate":"343c44","Plate ivory":"dbd2b4","Wheat base ochre":"bb9250","Wheat straw":"d1ab61",
  "Wheat golden":"dab76b","Wheat sunlit":"e6c780","Wheat bran":"a97f45","Wheat apricot":"c79c53",
  "Dark cured roof":"414a46","Roof slate folds":"575f55","Weathered tarp":"6c6c5e",
  "Livestock timber":"777567","Interior timber":"58584f","Horizontal rail light":"7da3b2",
  "Gate lining":"9e8d70","Recess dark floor":"4c5147","Review road":"747b7c","Review grass":"5f7458",
}
P={k:i for i,k in enumerate(PALETTE)}
R.COLORS[:]=PALETTE.values()
S.P=G.P=P
F,B,C,T,bar=G.face,S.slab,G.tube,S.circular,G.bar
AXLES=(-.454,.435)
WHEEL_X=.218
WHEEL_R=.108
BED=(-.172,.751)
BED_W=.243
TOP=.465


def mesh():
    return R.Mesh(R.terrain_height(0))


def irons(m,van):
    ink="Van blue" if van else "Company blue"
    highlight="Van highlight" if van else "Blue highlight"
    B(m,"Boxed ladder work truck chassis","Frame iron",0,.004,.401,1.439,.133,.200,.017)
    for side in (-1,1):
        B(m,"Cold drawn chassis C-section","Driveshaft",side*.163,.046,.035,1.373,.136,.187,.006)
        B(m,"Cab boot running step","Frame iron",side*.240,-.282,.073,.289,.110,.147,.008)
        for z in (-.386,-.337,-.289,-.241,-.193):
            B(m,"Raised steel step tread","Faded alloy",side*.240,z,.045,.013,.145,.152,.001)
        B(m,"Under-deck pressed fuel tank","Frame iron",side*.187,.125,.110,.240,.113,.200,.013)
        for z in (.044,.199):
            B(m,"Tank welded steel girth","Driveshaft",side*.197,z,.113,.019,.118,.209,.005)
        C(m,"Pressed welded swing shaft support","Driveshaft",(side*.163,-.445,.115),(side*.177,.429,.121),.012,.014,8)
    C(m,"Open live rear driveshaft","Driveshaft",(0,-.294,.138),(0,.424,.109),.019,.014,9)
    C(m,"Dark exhaust behind offside rear wheel","Frame iron",(.133,-.365,.102),(.166,.621,.080),.013,.012,8)
    C(m,"Dark central clutch bell housing","Frame iron",(0,-.481,.140),(0,-.174,.146),.090,.074,10)
    for i,z in enumerate(AXLES):
        T(m,"Full working axle shaft across chassis","Frame iron",(0,z,WHEEL_R),.021,"x",-.224,.224,12)
        for sign,letter in ((-1,"L"),(1,"R")):
            x=sign*WHEEL_X
            G.axle_tube(m,"Ground contact tyre "+letter,"Ground tread",[
              (-.034,.076),(-.034,.092),(-.027,WHEEL_R),(.026,WHEEL_R),
              (.034,.092),(.034,.076),(-.034,.076)],(x,z,WHEEL_R),20)
            T(m,"Separate tyre shoulder cheeks","Tyre sidewall",(x+sign*.030,z,WHEEL_R),
              .084,"x",-.009,.009,18)
            T(m,"Deep-dished painted pressed wheel rim","Road hub",(x+sign*.045,z,WHEEL_R),
              .053,"x",-.006,.006,16)
            T(m,"Spun hub protective dust cap","Hub light",(x+sign*.054,z,WHEEL_R),
              .024,"x",-.006,.006,12)
            for k in range(5):
                a=k*tau/5
                T(m,"Exposed hexagonal hand-tightened lug nuts","Hub light",
                    (x+sign*.051,z+.038*cos(a),WHEEL_R+.038*sin(a)),
                    .0045,"x",-.002,.003,6)
            if i:
                T(m,"Inboard rear paired load tyre","Tyre sidewall",(x-sign*.061,z,WHEEL_R),
                  .096,"x",-.021,.021,16)
            for h in (.131,.150):
                B(m,"Two spring pack leaf edges","Driveshaft",sign*.184,z,.029,.191-1.7*(h-.131),
                  h,h+.008,.003)
            B(m,"Heavy rubber flap aft of fender","Tyre sidewall",sign*.227,z+.134,
              .113,.018,.041,.196,.007)
            rows=[]
            for k in range(16):
                t=pi*k/15
                rows.append([(sign*d,z+r*cos(t),WHEEL_R+r*sin(t)) for d,r in (
                   (.178,.111),(.267,.111),(.287,.132),(.241,.146),(.181,.140),(.178,.111))])
            pal=("Deep blue",ink,highlight,ink,"Deep blue")
            for a,b in zip(rows,rows[1:]):
                for j,col in enumerate(pal):
                    face=a[j],b[j],b[j+1],a[j+1]
                    F(m,"Open curved front wing" if not i else "Open working steel rear spat",col,
                      face if sign>0 else face[::-1])


def enamel_letter_side(m,side,label,h,z,x,spacing=.008):
    # Sparse cast raised type, cut into small glint marks at survey distance.
    alphabet={
        "H":("101","101","111","101","101"),"G":("111","100","101","101","111"),
        "T":("111","010","010","010","010"),"L":("100","100","100","100","111"),
        "F":("111","100","110","100","100"),"1":("110","010","010","010","111"),
        "3":("110","001","110","001","110"),"4":("101","101","111","001","001"),
        "5":("111","100","110","001","110"),
    }
    for idx,c in enumerate(label):
        for row,cols in enumerate(alphabet[c]):
            for q,on in enumerate(cols):
                if on=="1":
                    yy=z+side*((idx*4+q)-len(label)*2+.9)*spacing
                    hh=h+(4-row)*spacing
                    B(m,"Original raised fleet nameplate characters","Plate ivory",side*x,yy,
                      .003,spacing*.84,hh,hh+spacing*.85,.0004)


def bound_mesh(m,names):
    verts,faces=[],[]
    for name in names:
        offset=len(verts)
        verts.extend(m.vertices[name])
        faces.extend(tuple(i+offset for i in face) for face,_ in m.parts[name])
    return BVHTree.FromPolygons(verts,faces,all_triangles=True)


def pressed_pane(m,bvh,quad,axis,sign,label):
    # Project the surround, glass, and narrow highlight to the actual cab
    # shape before exporting. Curvature stays on the metal instead of
    # leaving a straight pane partly buried under its forward dome.
    follow=lambda p: Vector(p)
    center=sum((follow(p) for p in quad),Vector((0,0)))/4
    inner=[center+(.86 if axis else .84)*(follow(p)-center) for p in quad]
    lower=lambda a,b,t: a+(b-a)*t
    glare=(lower(inner[0],inner[3],.73),lower(inner[1],inner[2],.73),
           lower(inner[1],inner[2],.88),lower(inner[0],inner[3],.89))
    def target(p,d):
        u,h=p
        origin=(u,-1.5,h) if axis else (1.5*sign,u,h)
        ray=(0,1,0) if axis else (-sign,0,0)
        v,normal,idx,length=bvh.ray_cast(origin,ray)
        if v is None:raise RuntimeError(f"{label}: absent steel behind {origin}")
        v[axis]+=sign*d
        return tuple(v)
    def set_surface(poly,name,color,d):
        n=5; v=[]
        for j in range(n+1):
            t=j/n
            A=lower(follow(poly[0]),follow(poly[3]),t)
            B=lower(follow(poly[1]),follow(poly[2]),t)
            v.append([target(lower(A,B,k/n),d) for k in range(n+1)])
        for j in range(n):
            for k in range(n):
                q=v[j][k],v[j][k+1],v[j+1][k+1],v[j+1][k]
                F(m,label+" "+name,color,q[::-1] if not axis and sign<0 else q)
    set_surface(quad,"thick rubber perimeter","Rubber seals",.0037)
    set_surface(inner,"true pressed glazing","Cab glazing",.0062)
    set_surface(glare,"soft horizon reflection","Glass sky",.0085)
    return target


def cab(m,van):
    hull=G.rolled
    ink="Van blue" if van else "Company blue"
    lit="Van highlight" if van else "Blue highlight"
    roof=.626 if van else .617
    shoulder=.549 if van else .539
    # Different cast cab crowns and short streamlined lower bonnets, built
    # as a rounded sectional body. Both look like the blue compact stock lorry.
    outer="Formed short individual coach cab, B-pillar and domed roof"
    G.panel(m,outer,[
      (-.640,hull(.201,.185,.490,roof-.060)),
      (-.592,hull(.235,.180,shoulder-.013,roof-.020)),
      (-.501,hull(.246,.179,shoulder+.006,roof)),
      (-.353,hull(.247,.179,shoulder+.013,roof+.004)),
      (-.231,hull(.229,.181,shoulder-.015,roof-.027)),
      (-.202,hull(.214,.191,.493,roof-.055)),
    ],ink,["Deep blue",ink,ink,ink,lit,lit,lit,lit,lit,ink,ink,ink,"Deep blue"])
    nose=.139 if van else .120
    G.panel(m,"Wedge swept engine bonnet with pressed ridges",[
      (-.750,hull(nose,.183,.332,.366)),
      (-.719,hull(nose+.030,.182,.354,.393)),
      (-.605,hull(.193,.181,.386,.423)),
      (-.503,hull(.202,.180,.409,.437)),
    ],ink,["Deep blue","Deep blue",ink,ink,lit,lit,lit,lit,lit,ink,ink,ink,"Deep blue"])
    B(m,"Shaped radiator surround casting","Bonnet nickel",0,-.750,.256,.036,.180,.378,.016)
    B(m,"Working recessed radiator throat","Grille gunmetal",0,-.770,.206,.020,.197,.363,.012)
    if van:
        for x in (-.076,-.054,-.032,-.010,.010,.032,.054,.076):
            B(m,"Vertical bright radiator grille flutes","Faded alloy",x,-.782,
              .006,.007,.214,.347,.001)
    else:
        for h in (.219,.241,.263,.285,.307,.329,.350):
            B(m,"Pressed horizontal radiator shutters","Faded alloy",0,-.782,
              .176,.007,h-.002,h+.003,.001)
    B(m,"Cast front rail bumper with rolled corners","Faded alloy",0,-.752,
      .439,.081,.120,.174,.013)
    B(m,"Period front road number backplate","Black plate",0,-.793,.125,.012,.129,.165,.004)
    B(m,"Engine access crown small original badge","Bonnet nickel",0,-.784,.043,.008,.346,.365,.003)
    for s in (-1,1):
        x=s*.244
        B(m,"Close pressed cab door with deep cut line","Deep blue",x,-.347,.014,.264,.188,.506,.012)
        B(m,"Blue panel inset with individually curved seam",ink,s*.253,-.348,.010,.243,.201,.488,.009)
        B(m,"Cab side bright waistline",lit,s*.257,-.347,.005,.221,.319,.333,.001)
        C(m,"Polished short bent rod door handle","Bonnet nickel",(s*.260,-.279,.348),
          (s*.263,-.241,.348),.004,.0035,6)
        side_shell=bound_mesh(m,(outer,"Close pressed cab door with deep cut line",
                                  "Blue panel inset with individually curved seam"))
        pressed_pane(m,side_shell,((-.479,.419),(-.250,.418),(-.257,.539),(-.467,.548)),
                     0,s,"Integrated side cab window")
        for yy in (-.687,-.658,-.629,-.600):
            width=.172+(yy+.640)*.39
            B(m,"Exposed sloping pressed bonnet ventilation slot","Deep blue",s*width,yy,.008,.011,.265,.334,.002)
        T(m,"Nickel individual headlight bucket","Bonnet nickel",(s*.183,-.732,.266),
          .046,"z",-.022,.010,17)
        T(m,"Warm fluted glass forward lamp","Warm headlight",(s*.183,-.757,.267),.034,
          "z",-.006,.005,15)
        for d in (-.012,.011):
            B(m,"Thin headlight molded translucent ribs","Plate ivory",s*.183+d,-.764,
              .003,.002,.246,.287,.0005)
        T(m,"Small wing amber turning glass","Orange lens",(s*.219,-.741,.202),
          .017,"z",-.012,.006,10)
        C(m,"Tiny hinged road mirror arm","Faded alloy",(s*.222,-.486,.479),
          (s*.291,-.526,.511),.006,.005,7)
        B(m,"Curved road mirror housing tucked above side","Deep blue",s*.291,-.530,
          .033,.024,.484,.550,.007)
        B(m,"Glint on real reverse-facing mirror","Bonnet nickel",s*.291,-.516,
          .027,.004,.493,.542,.005)
        enamel_letter_side(m,s,"TL 135".replace(" ","") if van else "HG141",.264,-.346,.260,.0072)
        fore=tuple((s*x,h) for x,h in ((.009,.424),(.179,.430),(.166,.521),(.010,.524)))
        if s<0:fore=fore[1],fore[0],fore[3],fore[2]
        project=pressed_pane(m,bound_mesh(m,(outer,)),fore,1,-1,"Clear divided front windscreen")
        C(m,"Fine articulated working windscreen wiper","Grille gunmetal",
          project((s*.035,.442),.011),project((s*.125,.467),.011),.0028,.0028,6)
    B(m,"Pressed rear body rail carrying period lamps","Faded alloy",0,.764,.469,.038,.133,.190,.009)
    for side in (-1,1):
        T(m,"Ruby stop lamp in grease resistant ring","Red lens",(side*.205,.766,.216),
          .030,"z",-.003,.013,12)
        T(m,"Upper amber rear direction winker","Orange lens",(side*.203,.766,.246),
          .017,"z",-.003,.014,10)
    B(m,"Period aft license plate with raised surround","Black plate",0,.779,.133,.010,.149,.178,.003)


def bed(m):
    # Grey clinker-pattern steel low open bin. Floor, front/rear frames and
    # thick sides share seams but are different editable shells. Hollow
    # all the way down until the real bottom plate at h=.275.
    front,rear=BED
    B(m,"Drawn bin bed solid floor plate","Recessed bed steel",0,
      (front+rear)/2,.434,rear-front-.020,.246,.279,.008)
    for j in range(5):
        x=(j-2)*.081
        B(m,"Metal bin floor abrasion plate strips","Wet steel" if j%2 else "Dry steel",
          x,(front+rear)/2,.078,rear-front-.037,.280,.286,.002)
    for z in (-.138,.007,.167,.348,.514,.716):
        B(m,"Structural crossbeam under grain tray floor","Wet steel",0,z,.490,.041,.214,.261,.006)
    side=[(.196,.274),(.234,.287),(.251,.344),(.248,.446),(.234,TOP),(.221,.461),
          (.226,.438),(.221,.339),(.204,.301),(.183,.293)]
    for s in (-1,1):
        for k,(a,b) in enumerate(zip(side,side[1:]+side[:1])):
            ax,h=a; bx,kH=b
            p=(s*ax,front,h),(s*ax,rear,h),(s*bx,rear,kH),(s*bx,front,kH)
            mat=("Dry steel","Wet steel","Dry steel","Steel bed edge","Pale steel trim",
                 "Pale steel trim","Wet steel","Wet steel","Recessed bed steel","Recessed bed steel")[k]
            F(m,"Open deep side wall and rolled grain bin rim",mat,p if s>0 else p[::-1])
        for yy in (-.126,.033,.216,.403,.590,.716):
            B(m,"Hot pressed grain bin exterior side rib","Steel bed edge",s*.246,yy,.022,.024,.299,.448,.004)
            B(m,"Visible dusty side rib rivet","Pale steel trim",s*.260,yy,.004,.014,.407,.419,.002)
        C(m,"Rolled steel bottom edge of grain bin","Wet steel",(s*.214,front,.278),
          (s*.214,rear,.278),.012,.010,8)
        C(m,"Wide pressed top one-piece external grain lip","Steel bed edge",
          (s*.236,front,.457),(s*.236,rear,.457),.009,.009,8)
        for yy in (-.130,.351,.711):
            B(m,"Metal adjustable grain tie bracket","Pale steel trim",s*.250,yy,
              .017,.025,.305,.325,.004)
    # Front/rear walls close four edges, not the top: rear has a dump gate.
    B(m,"Cold formed bulk head separating cab from open bay","Dry steel",0,front,
      .462,.036,.277,.461,.008)
    B(m,"Full width aft hinged grain discharge gate","Dry steel",0,rear,
      .458,.036,.278,.458,.009)
    for yy in (front,rear):
        B(m,"Continuous cold rolled end gate cap","Pale steel trim",0,yy,
          .469,.039,.452,.474,.006)
        B(m,"End gate flange protected cross ridge","Wet steel",0,yy,
          .452,.043,.295,.314,.004)
    for x in (-.174,0,.174):
        T(m,"Aft grain ring true gate hinge","Wet steel",(x,.769,.435),
          .011,"x",-.031,.031,10)
        B(m,"Aft gate perpendicular stiffener","Steel bed edge",x,.769,.025,.017,.310,.449,.005)
    for s in (-1,1):
        B(m,"Grain tailgate security lever cast pivot","Recessed bed steel",s*.192,.781,
          .043,.013,.316,.406,.004)
        C(m,"Separate rolling tailgate drop latch","Pale steel trim",
          (s*.194,.783,.387),(s*.177,.790,.316),.007,.006,8)


def grain(m):
    rng=Random(1411935)
    # Continuous closed grain surface and side walls. Origin and structural
    # bin remain byte-identical; the load never pokes through steel or rim.
    front,rear=BED[0]+.023,BED[1]-.025
    xs=[-.219,-.190,-.142,-.085,-.027,.031,.086,.145,.192,.219]
    zs=[front+(rear-front)*j/15 for j in range(16)]
    v=[]
    colors=("Wheat base ochre","Wheat straw","Wheat golden","Wheat sunlit","Wheat bran","Wheat apricot")
    for j,z in enumerate(zs):
        row=[]
        for i,x in enumerate(xs):
            e=abs(x)/.219
            f=(z-front)/(rear-front)
            bulge=sin(pi*min(1,max(0,(1-e)))) if e>.5 else 1
            lobe=.044+.106*sin(pi*f)**.55 + .012*cos(4*pi*f+.4)
            if i in (0,len(xs)-1) or j in (0,len(zs)-1):
                y=.401+.012*sin(i*.8+j*.43)
            else:
                y=.402+lobe*bulge+rng.uniform(-.009,.008)
            row.append((x,z,y))
        v.append(row)
    n=len(xs)
    for j,(a,b) in enumerate(zip(v,v[1:])):
        for i in range(n-1):
            p,q,r,s=a[i],a[i+1],b[i+1],b[i]
            q1,q2=(p,q,r),(p,r,s)
            for tr in (q1,q2):
                c=rng.choices(colors,weights=(10,15,30,18,6,14))[0]
                F(m,"Continuous faceted settled grain volume",c,tr)
    rim=v[0][:]+[row[-1] for row in v[1:]]+v[-1][-2::-1]+[row[0] for row in v[-2:0:-1]]
    for a,b in zip(rim,rim[1:]+rim[:1]):
        F(m,"Closed vertical grain volume boundary","Wheat base ochre",
          (a,(a[0],a[1],.292),(b[0],b[1],.292),b))
    F(m,"Closed dry grain base","Wheat bran",[(x,z,.292) for x,z,y in rim[::-1]])
    # Small angular kernels on the surface; sparse choice for a gentle
    # 3D grain texture, not floating gold cubes or a flat colored image.
    for j in range(2,14):
        for i in range(1,n-1):
            if rng.random()<.29:continue
            x,z,h=v[j][i]
            d=rng.uniform(.006,.012)
            w=rng.uniform(.004,.009)
            e=rng.choice((-1,1))
            roof=(x+.001*e,z,h+.0046)
            low=[(x+d,z-w*.4,h-.001),(x+.55*d,z+w*.86,h-.002),
                 (x-.69*d,z+w*.48,h-.002),(x-.83*d,z-w*.60,h-.001)]
            for k in range(4):
                F(m,"Raised faceted wheat husk details",
                  rng.choice(("Wheat straw","Wheat sunlit","Wheat golden")),
                  (low[k],low[(k+1)%4],roof))


def livestock(m):
    front,rear=BED[0]+.005,BED[1]-.002
    B(m,"Timber cattle box solid floor joists","Interior timber",0,
      (front+rear)/2,.514,rear-front+.060,.251,.285,.012)
    for i in range(7):
        x=(i-3)*.069
        B(m,"Raised individual timber livestock floor strips",
          "Livestock timber" if i%2 else "Gate lining",x,(front+rear)/2,
          .067,rear-front-.048,.285,.300,.003)
        for j in range(4):
            z=front+.120+.199*j
            B(m,"Metal non-slip transverse raised cattle floor cleat","Interior timber",x,z,
              .064,.017,.300,.311,.003)
    for z in (-.127,.041,.273,.499,.701):
        B(m,"Livestock underfloor oak joist","Livestock timber",0,z,.533,.035,.227,.270,.004)
    for s in (-1,1):
        sx=s*.259
        B(m,"Deep sill enclosing livestock floor edge","Deep blue",sx,(front+rear)/2,
          .029,rear-front+.062,.251,.297,.005)
        # Actual spacers sit around real apertures. The oncoming view can
        # see through the paired side slats instead of a black texture hole.
        for k,h in enumerate((.311,.384,.464,.544,.622)):
            B(m,"Rail ladder horizontal timber ventilation slat",
              "Van blue" if k%2 else "Horizontal rail light",sx,(front+rear)/2,
              .031,rear-front+.036,h,h+.037,.004)
            B(m,"Bright worn outside edge along open slat bottom",
              "Van highlight",s*.276,(rear+front)/2,.007,rear-front+.022,
              h+.005,h+.013,.002)
        for j,z in enumerate((front+.010,.022,.201,.390,.574,rear-.009)):
            B(m,"Complete side slat iron vertical stanchion","Van blue",s*.266,z,
              .031,.032,.263,.669,.004)
            C(m,"Lean internal brace beyond ventilation apertures","Interior timber",
              (s*.231,z,.308),(s*.225,z,.635),.0087,.0075,7)
            if j in (1,3,5):
                for h in (.330,.482,.625):
                    B(m,"Round wrought slat exterior pin button","Faded alloy",s*.284,z,
                      .009,.012,h,h+.010,.002)
        for (a,b) in ((front+.025,.201),(.392,.601)):
            bar(m,"Steel diagonal bracing in two lattice panels","Van highlight",
                (s*.279,a,.345),(s*.279,b,.595),.024,.014)
        for y in (.014,.561):
            C(m,"Internal stock deck gate hook held parked","Frame iron",(s*.230,y,.331),
              (s*.205,y,.351),.005,.004,7)
    # Real closed grid tailgate, period hardware, inside transverse gate
    # gives contrast without faking that livestock is visible at every load.
    for y in (front,rear):
        B(m,"Broad solid plank bulkhead at lower van ends","Van blue",0,y,
          .515,.035,.254,.350,.004)
        for h in (.358,.446,.534,.616):
            B(m,"Open rear and front transverse ventilation boards","Van blue",0,y,
              .513,.026,h,h+.044,.004)
        for x in (-.245,-.087,.087,.245):
            B(m,"Vertical gate frame strap","Van blue",x,y+.010,
              .026,.026,.289,.669,.004)
    for h in (.343,.513,.608):
        T(m,"Actual antique strap hinge on closed livestock gate","Faded alloy",(.222,rear+.024,h),
          .010,"x",-.024,.024,10)
    bar(m,"Closed rear gate protective diagonal locking arm","Van highlight",
      (-.217,rear+.027,.342),(.157,rear+.027,.610),.022,.012)
    B(m,"Sliding beam gate latch mounting plate","Frame iron",-.128,rear+.038,.085,.016,.460,.509,.003)
    C(m,"Steel gate sliding pin and rounded loop","Faded alloy",(-.188,rear+.050,.479),
      (-.097,rear+.050,.479),.006,.006,8)
    for n in (0,1):
        h=.284+n*.021
        B(m,"Tapered swing-out rear loading footstep folded shut","Faded alloy",0,rear+.036,
          .236,.035,h,h+.012,.003)

    # Low, cured replacement canvas stretched over real metal hoops.
    # All side vents remain open from threshold up to the sheltered roof.
    stations=(front-.025,front,.039,.227,.408,.595,rear,rear+.026)
    bands=(-.275,-.243,-.175,-.084,0,.084,.175,.243,.275)
    rows=[]
    for j,z in enumerate(stations):
        y=.664 if j in (0,len(stations)-1) else .678
        curve=[(x,z,y+.056*(1-(x/.275)**2)+.002*cos(j*1.8+i*.9)) for i,x in enumerate(bands)]
        rows.append(curve)
    for j,(a,b) in enumerate(zip(rows,rows[1:])):
        for k in range(len(bands)-1):
            p,q,r,s=a[k],a[k+1],b[k+1],b[k]
            col=("Dark cured roof","Roof slate folds","Dark cured roof","Roof slate folds",
                 "Dark cured roof","Roof slate folds","Dark cured roof","Weathered tarp")[k]
            F(m,"Physically bowed cured ventilated van roof",col,(p,q,r,s))
            F(m,"Visible inside canvas lining above cattle deck","Interior timber",
              ((s[0],s[1],s[2]-.009),(r[0],r[1],r[2]-.009),
               (q[0],q[1],q[2]-.009),(p[0],p[1],p[2]-.009)))
    for k,row in enumerate(rows[1:-1]):
        for a,b in zip(row,row[1:]):
            C(m,"Exposed curved canvas stretching hoop",
              "Faded alloy",tuple((a[0],a[1],a[2]-.014)),tuple((b[0],b[1],b[2]-.014)),
              .006,.006,7)
    for side,i in ((-1,0),(1,-1)):
        for a,b in zip(rows,rows[1:]):
            C(m,"Roof fold and separate longitudinal hem","Dark cured roof",a[i],b[i],
              .009,.009,8)
        for z in (front+.027,.034,.194,.392,.571,rear-.009):
            C(m,"Wire canvas end retention hook","Faded alloy",(side*.269,z,.652),
              (side*.269,z,.679),.003,.003,7)


def make(van=False, full=False):
    base=mesh()
    irons(base,van)
    cab(base,van)
    if van:livestock(base)
    else:
        bed(base)
        if full:grain(base)
    return base


def render_palette():
    mats=R.materials()
    for key,i in P.items():
        mat=mats[i];mat.name=key
        node=mat.node_tree.nodes["Principled BSDF"]
        node.inputs["Metallic"].default_value=.36 if "steel" in key or "nickel" in key else 0.
        node.inputs["Roughness"].default_value=.36 if key in (
          "Cab glazing","Daylight glass","Glass sky","Warm headlight") else .70
    return mats


def linked(name,m,mats,scene):
    c=bpy.data.collections.new(name)
    scene.collection.children.link(c)
    R.to_blender(m,c,mats)
    return c


def write_blend(name,body,load=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name=("LuanTTD · Hereford Grain Truck #141" if name==GRAIN else "LuanTTD · Talbott Livestock Van #135")
    sc.view_settings.view_transform="Standard"
    sc["Standing mount"]="10 OBJ units/node; .42 runtime size; -Z native nose; Y=0 ground plane"
    sc["Provenance"]="Original modeled art; OpenGFX 7.1 observed for silhouette only, no sprite image reused"
    linked("Permanent coachwork, drivetrain, axles and cargo enclosure",body,render_palette(),sc)
    if load:
        mats=[bpy.data.materials[k] for k in P]
        cargo=linked("Removable grain load · toggle off for empty",load,mats,sc)
        sc["Stock load sprite"]="Use this model state when units >= capacity/2 (10 at stock nominal capacity 20)."
    else:
        sc["Stock load sprite"]="No separate load state (stock image #4 uses full-adder zero)."
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                sp=area.spaces.active
                sp.shading.color_type="MATERIAL"
                sp.region_3d.view_location=Vector((0,0,.305))
                sp.region_3d.view_distance=2.83
                sp.region_3d.view_rotation=Vector((1.4,-2.13,1.24)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{name}.blend"),compress=True)


def atlas():
    def chunk(t,d):
        return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d))
    row=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    out=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    for key in (GRAIN,VAN):
        (R.TEXTURES/f"bl_{key}_atlas.png").write_bytes(out)


def export(name,raw):
    p=R.MODELS/f"bl_{name}.obj"
    R.export_obj(p,S.local_obj(raw))
    txt=p.read_text()
    p.write_text("# Original farm lorry art · tools/build_farm_road_trucks_art.py\n"+txt.split("\n",1)[1])


def review(empty,loaded,covered,path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene
    mats=render_palette()
    for name,m,x,y,twist in (
        ("Empty Hereford",empty,-1.14,.12,0),
        ("Filled Hereford",loaded,0,0,0),
        ("Vented Talbott",covered,1.21,.23,-.20),
    ):
        o=R.instance(sc,R.stash(m,mats,name),x,y)
        o.rotation_euler.z=twist
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002))
    bpy.context.object.data.materials.append(mats[P["Review road"]])
    bpy.ops.object.camera_add(location=(2.90,-4.46,3.65))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,.09,.29))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=3.93
    sc.camera=camera
    sc.world=bpy.data.worlds.new("Farmyard bright cloudy sky")
    sc.world.color=(.157,.177,.174)
    sc.view_settings.view_transform="Standard"
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x,sc.render.resolution_y=1530,1010
    sc.render.resolution_percentage=100
    sh=sc.display.shading
    sh.light="STUDIO"
    sh.color_type="MATERIAL"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    sh.background_type="WORLD"
    sc.render.filepath=path
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    empty,loaded,van=make(),make(full=True),make(van=True)
    cargo=mesh();grain(cargo)
    write_blend(GRAIN,empty,cargo)
    write_blend(VAN,van)
    for name,part in ((GRAIN,empty),(GRAIN+"_loaded",loaded),(VAN,van)):
        export(name,part)
    atlas()
    if path:=os.getenv("FARM_TRUCK_REVIEW"):
        review(empty,loaded,van,path)
