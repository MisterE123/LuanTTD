#!/usr/bin/env python3
"""Build original Riverbend Power, stock-format 4x2 coal-fired station.

blender -b -t 4 --python-exit-code 1 --python tools/build_power_station_art.py
POWER_STATION_RENDER=/tmp/power.png blender -b -t 4 --python tools/build_power_station_art.py

Source layout: OpenTTD 14.1 src/table/build_industry.h, _tile_table_power_station_0.
Design and all geometry are ours. Blender dimensions in native nodes; native
anchor is the north-west even x/z cell at grade+1, datum .5 below anchor.
"""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_small_airport_art as A

R,H=A.RAIL,A.H
COLORS=dict(A.PAL,**{
    "brick":"9d654d","dark_brick":"824d3e","pale_brick":"b67854","mortar":"b88d73",
    "coal":"343a39","coal_gray":"4a5050","coal_shine":"5c5f52","coal_dark":"282d30",
    "clinker":"695a47","sand":"99876a","rediron":"865b49","copper":"866d53",
    "shingle":"43585b","warm_plate":"ad9b7f","chalk_numeral":"e8d6a5",
    "water_dark":"55838a","water_pale":"759ba2","silver":"aab2a1",
    "ceramic":"b5ab8c","warning":"dba857","pipes":"566e69",
    "stack_soot":"97604c","stack_ochre":"a97052","stack_joint":"97664f",
    "skyglass":"82a3a2","insulator":"565c5a","grilldark":"252f31",
})
A.PAL=COLORS; A.P=H.P={k:i for i,k in enumerate(COLORS)}
R.COLORS[:]=COLORS.values()
B,T,F,Q=A.B,A.T,A.face,A.rect
ROOT=R.ROOT
FOOTPRINT=((7,7,7,10),(9,8,8,10))
MAX_X,MAX_Z=7.5,3.5
DIGITS=A.DIGITS
DIGITS.update({
    "C":("01111","11000","11000","11000","11000","11000","01111"),
    "G":("01111","11000","11000","11011","11011","11011","01111"),
    "P":("11110","11011","11011","11110","11000","11000","11000"),
    "S":("01111","11000","11000","01110","00011","00011","11110"),
    "T":("11111","00100","00100","00100","00100","00100","00100"),
    "U":("11011","11011","11011","11011","11011","11011","01110"),
    "V":("11011","11011","11011","11011","11011","01010","00100"),
})
PORT_Z=2.50
STACKS=((2.48,2.10,3.38),(4.34,2.10,3.52))


def ground(m):
    Q(m,"Coarse hardpack industry foundation","sand",-.5,7.5,-.50,3.50,.002)
    Q(m,"Southern industrial carriage and rail service apron","concrete_d",-.5,7.5,2.99,3.50,.004)
    Q(m,"East heavy truck delivery approach","concrete",5.91,7.5,2.07,2.99,.004)
    Q(m,"North boiler concrete deck","concrete_d",-.46,5.34,-.46,1.42,.0045)
    Q(m,"Electrical yard concrete bed","gravel",5.36,7.46,-.46,2.04,.005)
    Q(m,"Coal apron concrete loader floor","concrete_l",-.42,1.61,1.38,2.91,.005)
    Q(m,"Stack access path and oil-bound paving","gravel_l",1.61,5.40,2.7,2.99,.005)
    for k in range(15):
        x=-.44+k*.53
        Q(m,"Fine slab cross joints","concrete_seal",x-.004,x+.004,3.011,3.49,.007)
    for z in (2.17,2.82):
        Q(m,"Flat ochre loading-lane edge designation","yellow",5.95,7.47,z-.012,z+.012,.010)
    for x in (6.45,6.76,7.07,7.38):
        Q(m,"Truck approach dashed center markings","paint_shadow",x-.085,x+.085,PORT_Z-.011,PORT_Z+.011,.009)
    for x in (.26,1.22,5.65):
        for k in range(4):
            z=3.06+k*.112
            Q(m,"Pedestrian crossing bars","paint_shadow",x-.168,x+.168,z-.018,z+.018,.012)
    rng=Random(1014)
    for i in range(335):
        x=rng.uniform(-.468,7.46);z=rng.uniform(-.468,3.46)
        if 5.8<x and 2.03<z<3.0:continue
        c=rng.choice(("gravel_d","sand","gravel_l","concrete_seal"))
        if z>=2.99:c=rng.choice(("concrete_d","concrete_seal","concrete"))
        w=rng.uniform(.006,.035);l=rng.uniform(.006,.026)
        Q(m,"Sparse varied aggregate chips",c,x-w/2,x+w/2,z-l/2,z+l/2,.0075)


def brick_front(m,n,xc,z,width,hmin,hmax,back=False):
    rng=Random(24+int(abs(xc)*100))
    courses=int((hmax-hmin)/.079)
    left=xc-width*.5
    for row in range(courses):
        y=hmin+row*.079
        pat=.162
        x=left-.081*(row%2)
        while x<left+width:
            a=max(left,x+.004)
            b=min(left+width,x+pat-.004)
            if b-a>.007:
                c=rng.choices(("brick","pale_brick","dark_brick"),(6,2,1))[0]
                zz=z+(-.003 if back else .003)
                # Front and upper lip only. Inner brick volume sits inside
                # the wall bulk and does not need hundreds of hidden faces.
                ps=[(a,zz,y),(b,zz,y),(b,zz,y+.067),(a,zz,y+.067)]
                F(m,n+" separate brick batts",c,ps if back else ps[::-1])
                Q(m,n+" rough surfaced brick top",c,a,b,z-.004,z+.0055,y+.067)
            x+=pat


def facade(m,n,x,z,w,height):
    # Square-brick cut piers and a real recessed, round-arched glazing bay.
    arch_r=w/2
    y0=.22; spring=height-.225
    B(m,n+" concrete slip sill","foundation",x,z+.008,w+.11,.087,y0-.033,y0+.003,.011)
    B(m,n+" dark punctured glazing bay","glass_dark",x,z+.007,w,.024,y0,spring)
    crown=[(x+arch_r*cos(pi*j/16),z+.021,spring+arch_r*sin(pi*j/16)) for j in range(17)]
    for j in range(16):
        F(m,n+" inner semicircular drain glass","glass_dark",[(x,z+.021,spring),crown[j],crown[j+1]][::-1])
        def p(k,r):
            a=pi*k/16
            return x+r*cos(a),z+.024,spring+r*sin(a)
        F(m,n+" sandstone radial voussoirs","board",[p(j,arch_r),p(j,arch_r+.032),p(j+.83,arch_r+.032),p(j+.83,arch_r)][::-1])
    for dx in (-arch_r,arch_r):
        B(m,n+" window jamb","board",x+dx,z+.016,.028,.046,y0,spring,.002)
    for i in range(6):
        dx=(i+.5)*w/6-w/2
        end=spring+(arch_r*arch_r-dx*dx)**.5-.004
        B(m,n+" foundry window frame bars","steel",x+dx,z+.024,.007,.026,y0,end)
    for yy in (y0+.09,y0+.193,spring,spring+.07):
        ww=w if yy<=spring else 2*max(.0,arch_r*arch_r-(yy-spring)**2)**.5
        B(m,n+" horizontal iron cames","steel",x,z+.022,ww,.024,yy-.005,yy+.004)
    B(m,n+" muted lower window reflection","skyglass",x+.053,z+.025,.053,.008,y0+.019,spring-.015,.003)
    B(m,n+" glazed diamond highlight","glazed",x-.060,z+.026,.058,.008,y0+.19,spring-.004,.003)


def building(m,name,x,z,w,l,h,ref):
    B(m,name+" raised chamfered plinth","foundation",x,z,w+.051,l+.058,0,.122,.019)
    B(m,name+" load-bearing walls","mortar",x,z,w,l,.121,h-.026,.009)
    brick_front(m,name,x,z+l/2,w,.128,h-.034)
    brick_front(m,name+" north",x,z-l/2,w,.128,h-.034,True)
    for dx in (-w*.48,-w*.235,w*.235,w*.48):
        B(m,name+" reinforced pilasters","brick",x+dx,z+l/2+.019,.087,.066,.119,h+.009,.006)
        B(m,name+" limestone pilaster footing","board",x+dx,z+l/2+.031,.106,.092,.119,.190,.008)
        B(m,name+" limestone spring block","board",x+dx,z+l/2+.037,.109,.104,h-.090,h-.045,.008)
    B(m,name+" corbelled water table","dark_brick",x,z,w+.048,l+.046,h-.052,h+.010,.008)
    B(m,name+" sandstone drip","board",x,z,w+.057,l+.059,h-.010,h+.029,.008)
    if ref=="boiler":
        A.gable(m,name+" shallow industrial gable",x,z,w+.096,l+.099,h+.021,h+.475,"shingle","z")
        for sign in (-1,1):
            zz=z+sign*l/2
            panel=[(x-w/2,zz,h+.021),(x+w/2,zz,h+.021),(x,zz,h+.456)]
            F(m,name+" triangular built-in masonry gable","brick",panel[::-1] if sign>0 else panel)
            for j in range(1,5):
                yy=h+.021+j*.082
                half=w*.5*(1-j*.082/.435)
                lintel=[(x-half,zz+sign*.002,yy),(x+half,zz+sign*.002,yy),
                        (x+half,zz+sign*.002,yy+.005),(x-half,zz+sign*.002,yy+.005)]
                F(m,name+" gable bed joints","mortar",lintel[::-1] if sign>0 else lintel)
        for i in (0,1,2):
            zz=z-.35+i*.35
            B(m,name+" cast roof smoke vent curb","dark_slate",x,zz,.295,.161,h+.408,h+.481,.005)
            B(m,name+" monitor ventilator grill","grilldark",x,zz,.209,.126,h+.481,h+.555,.008)
            B(m,name+" vent weather cap","shingle",x,zz,.269,.171,h+.557,h+.581,.009)
    else:
        A.gable(m,name+" standing seam roof",x,z,w+.11,l+.096,h+.02,h+.29,"shingle","x")
    for dx in (-w*.345,0,w*.345):
        if (not dx and ref=="boiler") or (ref=="pump" and dx>0):continue
        facade(m,name+" high industrial sash",x+dx,z+l/2+.016,.263 if ref=="pump" else .309,h-.113)
    if ref=="boiler":
        B(m,"Boiler freight portal brick lintel","ochre",x,z+l/2+.022,.344,.046,.662,.729,.008)
        B(m,"Boiler freight portal folded steel leaves","teal",x,z+l/2+.027,.315,.048,.108,.671,.008)
        B(m,"Boiler double doors closing joint","dark_green",x,z+l/2+.055,.012,.009,.122,.661,.002)
        for dx in (-.123,.123):
            for y in (.241,.484):
                B(m,"Riveted freight door strap","dark_slate",x+dx,z+l/2+.059,.083,.012,y-.009,y+.009,.003)
    if ref=="pump":
        A.doorway(m,"Pump workshop access door",x+w*.34,z+l/2+.022,.252,.10,.548,"teal")

def boiler(m):
    building(m,"Turbine hall",.55,.442,1.71,1.503,1.13,"turbine")
    building(m,"Coal-fired boiler house",2.52,.431,1.78,1.441,1.52,"boiler")
    building(m,"Condenser pump and control annex",4.458,.46,1.69,1.446,.964,"pump")
    for x in (.53,2.51):
        B(m,"Enamel power works fascia","dark_green",x,1.194,1.18,.050,.861,1.001,.015)
    A.lettering(m,"Raised Riverbend name","RIVERBEND",(.53,1.221,.930),.018,"south","bone")
    A.lettering(m,"Raised Power Works name","POWER", (2.51,1.222,.930),.023,"south","bone")
    # Each generating bay has its own roof monitor and solid dressed step.
    for x in (.12,.59,1.04,3.94,4.43):
        B(m,"Vent mitered cap","slate",x,.410,.181,.34,1.377 if x<1.1 else 1.21,1.425 if x<1.1 else 1.256,.009)
    for x in (.12,.50,.88):
        for z in (.35,.43,.51):
            B(m,"Turbine hall roof intake slats","dark_slate",x,z,.158,.018,1.382,1.419,.002)
    for x in (-.100,1.971,3.986,5.035):
        A.lantern(m,x,1.247,.702,"Foundry overhead porch lamps")
    for x in (1.482,3.499):
        B(m,"Flexible connector service walkway","foundation",x,.62,.22,.529,.009,.046,.016)
        T(m,"Short steam equalizing pipe run","pipes",(x-.14,.46,.77),(x+.15,.46,.77),.061,.061,12)
        T(m,"Flanged steam run junction","slate",(x-.016,.46,.77),(x+.016,.46,.77),.083,.083,12)

def ring(cx,cz,y,r,N):
    return [(cx+r*cos(i*2*pi/N),cz+r*sin(i*2*pi/N),y) for i in range(N)]

def skin(m,n,rings,col,inside=False):
    ndiv=len(rings[0])
    for idx,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(ndiv):
            j=(i+1)%ndiv
            group=[a[i],a[j],b[j],b[i]]
            F(m,n,col(idx,i) if callable(col) else col,group[::-1] if inside else group)

def stack(m,x,z,top,index):
    N=24
    B(m,"Stack bluestone foundation","foundation",x,z,.750,.769,.002,.17,.033)
    B(m,"Dressed flue foot plinth","brick",x,z,.664,.678,.16,.351,.027)
    for dy,rad in ((.330,.342),(.377,.300)):
        T(m,"Chimney foot sandstone set-off","board",(x,z,dy),(x,z,dy+.046),rad,rad,N)
    levels=[(.384,.293),(.46,.286),(.74,.265),(1.15,.249),(1.62,.232),(2.14,.215),(2.68,.195),
            (top-.295,.175),(top-.240,.180),(top-.154,.181),(top-.103,.221),(top-.041,.223),
            (top,.217)]
    # Staggered courses change hue gently under the soot zone instead of
    # repeating broad same-tint vertical stripes around the whole shaft.
    courses=[]
    for (a,ra),(b,rb) in zip(levels[:8],levels[1:8]):
        n=max(1,round((b-a)/.126))
        for j in range(n):
            t=j/n
            yt,rt=a+(b-a)*t,ra+(rb-ra)*t
            h=min(.006,(b-a)/n*.1)
            courses.append((yt,rt))
            courses.append((yt+h,rt+(rb-ra)*h/(b-a)))
    courses.extend(levels[7:])
    colors=("brick","stack_soot","stack_ochre","brick","brick","stack_soot","brick")
    def brick_color(j,i):
        if j==len(courses)-5 or j==len(courses)-3:return "board"
        if j<len(courses)-6 and j%2==0:return "stack_joint"
        return colors[(i*13+(j//2)*17+index*2)%len(colors)]
    skin(m,"Tapered patterned masonry smoke shaft",[ring(x,z,y,r,N) for y,r in courses],brick_color)
    # True open annulus and inward-facing firebrick. The dark recess is
    # visually deep but not an unlit matte wafer on top.
    for yc,ra,rb in [(top,.217,.144),(top-.47,.144,.133)]:
        a,b=ring(x,z,yc,ra,N),ring(x,z,yc,rb,N)
        for i in range(N):
            j=(i+1)%N
            F(m,"Stack open annular rim" if yc==top else "Stack recessed throat ledge",
              "board" if yc==top else "coal_dark",(a[i],a[j],b[j],b[i]))
    skin(m,"Recessed soot-lined chimney bore",[ring(x,z,top-.471,.132,N),ring(x,z,top,.144,N)],
         "coal_dark",True)
    for y,r0,r1 in ((.534,.286,.281),(.843,.267,.258),(1.42,.245,.234),(2.02,.223,.219),(2.63,.200,.194)):
        skin(m,"Lapped iron circumferential stack bond plates",[ring(x,z,y-.013,r0+.005,N),ring(x,z,y+.009,r1+.005,N)],"dark_brick")
    # Flue access rung ladder, resting landings and inspectable test port.
    sign=-1 if index==0 else 1
    for y in (.38,.44,.54,2.94):
        r=.254 if y<1 else .215
        T(m,"Stack inspection mounting strap","dark_metal",(x+sign*r,z-.089,y),(x+sign*r,z+.089,y),.017,.017,8)
    for ze in (z-.076,z+.076):
        T(m,"Taper-following steel flue ladder side rails","dark_metal",(x+sign*.300,ze,.178),(x+sign*.218,ze,2.992),.011,.009,7)
    for k in range(25):
        y=.247+k*.101
        rr=.300-(.300-.218)*(y-.178)/(2.992-.178)
        T(m,"Individual flue ladder rungs","steel",(x+sign*rr,z-.083,y),(x+sign*rr,z+.083,y),.009,.009,7)
    B(m,"Stack bronze datum plate","ochre",x,z+.324,.103,.016,.219,.300,.006)
    A.lettering(m,"Stack unit number",str(index+1),(x,z+.334,.261),.011,"south","chalk_numeral")
    # Short sealed, differentiated masonry breeching from the boiler to flue.
    T(m,"Exposed cast iron boiler exhaust breeching","coal_gray",(x,1.112,.690),(x,1.54,.566),.109,.132,14)
    T(m,"Exposed cast iron boiler exhaust breeching","coal_gray",(x,1.531,.566),(x,z-.19,.555),.133,.133,14)
    for dz in (1.27,1.525,z-.217):
        T(m,"Riveted flue union collar","steel",(x,dz-.023,.564),(x,dz+.023,.564),.153,.153,14)
    for dz in (1.47,1.72):
        B(m,"Concrete exhaust conduit bracket","foundation",x,dz,.135,.119,.005,.451,.013)

def steam_loop(m):
    # An original two-cell induced-draft rooftop cooling house. The pumps,
    # external return risers, louvers, fan barrels, grilles and actual blades
    # can all be inspected independently, not one cooling-tower silhouette.
    xc,zc=4.42,.413
    B(m,"Concrete cooling plant rooftop grillage","foundation",xc,zc,1.29,1.058,1.233,1.306,.040)
    for x in (3.930,4.895):
        for z in (.056,.806):
            B(m,"Cooling steel support pedestal","dark_slate",x,z,.096,.095,1.095,1.244,.007)
    B(m,"Twin-cell zinc cooling basin","steel",xc,zc,1.166,.925,1.305,1.393,.018)
    B(m,"Visible cooling basin water","water_dark",xc,zc,1.138,.893,1.390,1.411,.014)
    for x in (xc-.550,xc,xc+.550):
        for z in (zc-.404,zc+.404):
            B(m,"Cedar tower galvanized corner stanchion","teal",x,z,.050,.064,1.369,1.775,.004)
    for z in (zc-.413,zc+.413):
        inset=z-.020 if z>zc else z+.020
        B(m,"Shadow visible through tower intake louvres","grilldark",xc,inset,1.10,.035,1.393,1.725,.007)
        for n in range(7):
            y=1.409+n*.046
            for x in (xc-.282,xc+.282):
                a,b=z-.031,z+.031
                ringz=a if z>zc else b
                F(m,"Shaped cooling-tower side louvres","timber",[(x-.248,a,y),(x+.248,a,y),(x+.248,b,y+.026),(x-.248,b,y+.026)])
                B(m,"Cedar louvre outer noses","wood",x,ringz,.502,.022,y+.008,y+.025,.002)
    for x in (xc-.552,xc+.552):
        B(m,"Cooling tower return louvers housing","dark_green",x,zc,.041,.785,1.394,1.742,.006)
        for k in range(7):
            y=1.413+k*.046
            B(m,"Cooling tower visible return slat","timber",x,zc,.058,.773,y,y+.020,.005)
    # True hollow top rings and separated five-blade fan assemblies.
    for x in (xc-.28,xc+.28):
        B(m,"Cooling cell upper motor platform","slate",x,zc,.543,.817,1.726,1.758,.026)
        for j,(y,r) in enumerate(((1.742,.222),(1.791,.218),(1.823,.210))):
            if j:skin(m,"Cooling fan outward barrel",[ring(x,zc,py,pr,24),ring(x,zc,y,r,24)],"teal")
            py,pr=y,r
        inside=.181
        a,b=ring(x,zc,1.823,.210,24),ring(x,zc,1.823,inside,24)
        for j in range(24):
            k=(j+1)%24
            F(m,"Cooling fan open collar annulus","silver",(a[j],a[k],b[k],b[j]))
        skin(m,"Cooling fan recessed throat",[ring(x,zc,1.759,.18,24),ring(x,zc,1.823,.181,24)],"coal_dark",True)
        T(m,"Visible cooling fan turned central hub","steel",(x,zc,1.765),(x,zc,1.810),.052,.044,14)
        for j in range(5):
            q=j*2*pi/5
            def blade(r,t,y):return x+cos(t+q)*r,zc+sin(t+q)*r,y
            p=[blade(.040,-.36,1.789),blade(.157,-.18,1.798),
               blade(.164,.155,1.781),blade(.043,.215,1.771)]
            F(m,"Independent curved cooling fan rotor blade","silver",p)
            F(m,"Independent curved cooling fan rotor blade","steel",p[::-1])
        for j in (-1,0,1):
            dz=.056*j;xoff=(inside*inside-dz*dz)**.5
            T(m,"Open protective cooling fan grate","dark_metal",(x-xoff,zc+dz,1.820),
              (x+xoff,zc+dz,1.820),.006,.006,6)
    for x,sg in ((3.78,-1),(5.22,1)):
        T(m,"Low-level cooling loop galvanized drain","pipes",(x,.12,.224),(x,-.17,.224),.051,.051,12)
        T(m,"Twin tall cooling return risers","pipes",(x,-.17,.210),(x,-.17,1.491),.051,.049,12)
        T(m,"Cooling tower pipe turned elbow","pipes",(x,-.17,1.49),(x-.088*sg,-.043,1.49),.051,.054,12)
        for y in (.476,.972,1.389):
            T(m,"Visible cooling return union","silver",(x,-.17,y-.012),(x,-.17,y+.011),.060,.060,12)
        T(m,"Red cooling loop hand-wheel","red",(x,-.223,.474),(x,-.224,.474),.075,.075,12)

def switchgear(m):
    # The two stock gfx 10 transformer tiles each have hardware, not a
    # cooling-tower substitution. Each carries its own high-voltage bushings.
    for q,z in enumerate((.44,1.768)):
        x=6.54
        l=.679 if q==0 else .455
        B(m,"Switchyard drain-lined equipment foundation","foundation",x,z,1.391,l+.079,.004,.054,.026)
        for xx in (x-.338,x+.338):
            B(m,"Transformer cast skid shoes","dark_slate",xx,z,.55,l-.072,.045,.132,.015)
            B(m,"Riveted transformer tank","pipes",xx,z,.452,l-.117,.118,.466,.034)
            B(m,"Removable warm gray transformer lid","steel",xx,z,.486,l-.095,.441,.488,.018)
            for d in (-1,1):
                for p in range(5):
                    x2=xx+(.188 if d>0 else -.188)
                    zz=z+(-.155+p*.077)*(1 if q==0 else .56)
                    B(m,"Transformer deep cooling radiator fins","dark_green",x2+d*.037,zz,.134,.017,.166,.403,.004)
            for i,xx2 in enumerate((xx-.105,xx,xx+.105)):
                if i==1:zz=z-.038
                else:zz=z+.018
                T(m,"Transformer porcelain live bushing cores","ceramic",(xx2,zz,.472),(xx2,zz,.674),.021,.017,10)
                for j in range(5):
                    yy=.495+j*.031
                    T(m,"Porcelain bushing ribs","ceramic",(xx2,zz,yy),(xx2,zz,yy+.012),.040-j*.0025,.034-j*.0025,10)
                T(m,"Brass terminal contact plates","copper",(xx2,zz,.669),(xx2,zz,.691),.025,.021,10)
            B(m,"Black enamel voltage plate","coal_gray",xx,z+l*.37,.129,.013,.278,.349,.003)
            # A fine service conduit, not live access into truck approach.
            T(m,"Transformer side service elbow","copper",(xx+.226,z,.322),(xx+.257,z-.117,.322),.018,.018,8)
    for x in (5.81,7.25):
        z=.109
        B(m,"Porcelain rack concrete foot","foundation",x,z,.140,.151,0,.087,.015)
        B(m,"Switch frame lattice poppet","teal",x,z,.040,.064,.079,1.207,.009)
        B(m,"Switch frame bolted column base","dark_slate",x,z,.099,.102,.083,.126,.009)
        T(m,"Electric metal rack diagonal buttress","steel",(x,z,.175),
          (x,.32,.462),.013,.013,8)
    for y in (.984,1.175):
        B(m,"Electrical isolator painted cross arm","teal",6.53,.109,1.489,.050,y-.025,y+.025,.006)
    for x in (5.974,6.247,6.53,6.81,7.064):
        for n in range(4):
            y=1.179+n*.026
            T(m,"Switchyard bank ceramic stacked insulators","ceramic",(x,.110,y),(x,.110,y+.018),.036,.029,8)
        T(m,"Switch bank live red copper switch link","copper",(x-.059,.11,1.288),(x+.079,.179,1.291),.009,.009,7)
    for x in (5.95,6.54,7.09):
        T(m,"Hanging overhead jumper to transformers","dark_metal",(x,.125,1.27),(x+.027,.356,.688),.008,.008,6)
    for z in (-.16,.13,.42,.72,1.02,1.31,1.61,1.9):
        x=7.418
        B(m,"Switchyard isolated fence pier","foundation",x,z,.070,.066,.004,.060,.005)
        B(m,"Switchyard fence posts with bus-side clear opening","dark_green",x,z,.019,.023,.043,.453,.002)
    for h in (.123,.409):
        B(m,"Electrical safety continuous wire rail","insulator",7.419,.865,.011,2.09,h-.009,h+.009,.003)
    for n in range(18):
        z=-.078+n*.111
        for d in (-1,1):
            T(m,"Separate galvanized chainlink fence strands","steel",(7.419,z,.108 if d>0 else .409),
              (7.419,z+.108,.409 if d>0 else .108),.003,.003,5)
    B(m,"Switchyard enameled warning plate","warning",7.409,1.108,.017,.220,.264,.382,.007)

def stockpile(m,xc,zc,rx,rz,top,seed):
    rng=Random(seed)
    angles=[2*pi*j/15 for j in range(15)]
    def make(s,y):
        return [(xc+s*rx*cos(q)*rng.uniform(.88,1.10),zc+s*rz*sin(q)*rng.uniform(.88,1.10),
                 y*rng.uniform(.79,1.12)) for q in angles]
    slices=[make(.97,.023),make(.70,top*.49),make(.35,top*.82)]
    colors=("coal","coal","coal_gray","coal_dark","coal_shine")
    skin(m,"Individual irregular coal stockpile faces",slices,lambda j,i:colors[(i*13+j*3)%len(colors)])
    apex=(xc+.046,zc-.091,top)
    for j,p in enumerate(slices[-1]):
        F(m,"Coal stockpile irregular ragged top",colors[(j*13+seed)%len(colors)],
          (p,slices[-1][(j+1)%len(angles)],apex))
    for j in range(34):
        t=2*pi*rng.random()
        r=rng.uniform(.69,1.12)
        xx=xc+r*rx*cos(t)
        zz=zc+r*rz*sin(t)
        w=rng.uniform(.015,.049)
        h=rng.uniform(.012,.052)
        B(m,"Scattered lumps of coal below bunkers",rng.choice(colors),xx,zz,w,w*rng.uniform(.74,1.35),.012,.012+h,w*.25)

def receiving(m):
    # Low structure on stock gfx 9. Keep the frontage open for a separately
    # owned station next to the industry site rather than drawing an inert
    # rail line on its tile. Surface aprons don't consume more world tiles.
    B(m,"Low ash and weighing shop bluestone plinth","foundation",.241,1.824,.994,.445,.001,.079,.020)
    B(m,"Coal delivery weigh house red brick","brick",.241,1.824,.938,.402,.076,.518,.027)
    A.gable(m,"Weigh house low weathered roof",.242,1.822,1.057,.497,.516,.711,"shingle")
    A.facade_window(m,"Occupied weigh-office sash",.421,2.028,.252,.210,.437)
    A.doorway(m,"Weigh house open air stoop",.03,2.034,.177,.055,.408,"teal")
    A.lantern(m,.28,2.061,.458,"Weigh house caged lamp")
    B(m,"Formed coal pile containment wall","foundation",.925,2.18,1.079,.078,.004,.199,.008)
    B(m,"Short guarded coal bunker curb","foundation",1.508,2.47,.058,.635,.003,.169,.007)
    stockpile(m,.90,2.48,.47,.294,.285,1887)
    stockpile(m,1.079,2.592,.306,.245,.201,3149)
    B(m,"Ash hopper ground girder","dark_slate",1.154,1.842,.417,.48,.015,.077,.008)
    for x in (.962,1.338):
        for z in (1.639,2.04):
            B(m,"Ash hopper load-bearing legs","rediron",x,z,.047,.047,.064,.436,.007)
            T(m,"Ash hopper triangulated knee joints","dark_metal",(x,z,.077),(x+(.058 if x<1.0 else -.058),z,.284),.010,.010,7)
    lower=[(.989,1.727,.180),(1.330,1.727,.180),(1.33,1.932,.180),(.989,1.932,.180)]
    upper=[(.929,1.592,.510),(1.392,1.592,.510),(1.392,2.074,.510),(.929,2.074,.510)]
    skin(m,"Four-seamed steel ash surge bin",[lower,upper],"dark_green")
    skin(m,"Genuinely open inside of tapered ash surge bin",[[(x+(.018 if x<1.1 else -.018),
        z+(.018 if z<1.8 else -.018),h-.004) for x,z,h in a] for a in (lower,upper)],"coal_dark",True)
    for p,q in zip(upper,upper[1:]+upper[:1]):
        T(m,"Hopper outer steel angle trim","dark_slate",p,q,.014,.014,7)
    stockpile(m,1.165,1.833,.173,.151,.451,9375)
    for z in (2.238,2.70):
        B(m,"Coal receiving protective guard posts","warning",5.895,z,.036,.042,.013,.215,.005)
        B(m,"Coal receiving black guard bands","coal_dark",5.895,z,.037,.043,.138,.176,.005)
    # Flush roadside dump grate: no tall equipment in the final .31 node
    # of either lane even when a heavy truck occupies the full pull-in.
    Q(m,"Flush lipped coal receiving grate shadow","grilldark",5.95,6.367,2.25,2.744,.0078)
    for j in range(12):
        x=5.959+j*.036
        Q(m,"Visible recessed coal chute grate bars","steel",x-.006,x+.006,2.256,2.735,.012)
    for z in (2.254,2.736):
        Q(m,"Coal chute cast-lined flush frame","dark_slate",5.949,6.369,z-.008,z+.009,.013)
    # Slatted continuous belt, steel angles, and separate flanged rollers.
    a=(5.776,2.526,.253)
    b=(3.207,1.122,1.211)
    v=Vector(b)-Vector(a)
    N=Vector((-v.y,v.x,0)).normalized()
    def line(t,n=0,y=0):
        return tuple(Vector(a)+v*t+N*n+Vector((0,0,y)))
    for s in (-1,1):
        ns=s*.139
        T(m,"Coal conveyor paired continuous steel stringer","dark_green",line(0,ns,-.029),line(1,ns,-.029),.026,.023,9)
        T(m,"Coal conveyor lower steel web","dark_slate",line(0,ns,-.202),line(1,ns,-.202),.017,.015,8)
        for j in range(12):
            dx=1/12
            q=j*dx
            T(m,"Open triangular conveyor truss webs","rediron",line(q,ns,-.026),line(q+dx,ns,-.2),.012,.012,7)
            T(m,"Open triangular conveyor truss webs","rediron",line(q,ns,-.2),line(q+dx,ns,-.026),.012,.012,7)
    for j in range(41):
        p=j/41
        p1=min(1,(j+.93)/41)
        F(m,"Separate battered coal conveyor belt slats","coal_gray" if j%4 else "coal",
          (line(p1,-.105),line(p,-.105),line(p,.105),line(p1,.105)))
        T(m,"Coal belt shaped transverse slat ribs","steel",line(p,-.114,.003),line(p,.114,.003),.004,.004,6)
    for p in (.016,.310,.616,.972):
        T(m,"Conveyor support drums","dark_slate",line(p,-.157,-.036),line(p,.157,-.036),.056,.056,12)
        for n in (-.151,.151):
            x,z,h=line(p,n,-.189)
            B(m,"Conveyor support grout pad","foundation",x,z,.151,.159,.004,.055,.014)
            T(m,"Conveyor articulated grade stand","dark_green",(x,z,.041),(x,z,h),.018,.015,8)
    B(m,"Coal conveyor enclosed roof intake","dark_slate",3.244,1.131,.267,.432,1.103,1.369,.022)
    B(m,"Louvered cast steel intake coupler","steel",3.262,1.238,.276,.175,1.128,1.280,.014)
    B(m,"Coal conveyor receiving motor","steel",5.646,2.544,.142,.239,.139,.270,.025)
    T(m,"Drive motor exposed end shaft","copper",(5.706,2.549,.196),(5.82,2.549,.196),.024,.024,10)

def split(m,tx,tz):
    out=A.mesh()
    lx=2*tx-.5;lz=2*tz-.5
    for n,items in m.parts.items():
        vs=m.vertices[n]
        for ids,color in items:
            p=[vs[i] for i in ids]
            for axis,at,sign,last in ((0,lx,1,False),(0,lx+2,-1,tx==3),
                                     (1,lz,1,False),(1,lz+2,-1,tz==1)):
                if sign<0 and not last and all(abs(v[axis]-at)<A.EPS for v in p):p=[]
                if not p:break
                p=A.clip(p,axis,at,sign)
            out.face(n,color,[(x-(lx+1),z-(lz+1),y) for x,z,y in p])
    return out

def write_palette():
    def c(tag,body):
        return struct.pack(">I",len(body))+tag+body+struct.pack(">I",zlib.crc32(tag+body))
    raw=b"".join(bytes.fromhex(v)*8 for v in COLORS.values())
    p=R.TEXTURES/"bl_power_station_atlas.png"
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",len(COLORS)*8,8,8,2,0,0,0))
                  +c(b"IDAT",zlib.compress((b"\0"+raw)*8,9))+c(b"IEND",b""))

def double_stack(m):
    for i,(x,z,top) in enumerate(STACKS):stack(m,x,z,top,i)

GROUPS=(("Concourse and drive geometry",ground),
        ("Turbine hall, boiler and pump architecture",boiler),
        ("Twin refractory exhaust shafts",double_stack),
        ("Twin-cell cooling tower and pipes",steam_loop),
        ("Two transformer tile banks",switchgear),
        ("Coal receiving pit, stockpiles and transfer belt",receiving))

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc["source"]="OpenTTD 14.1 default power station variant 0; [7 7 7 10]/[9 8 8 10]. Original geometry."
    sc["datum"]="Native node dimensions. Ground top Z=0 in Blender. Runtime anchor +1 from flat nodes."
    sc["access"]="Truck entry in +X boundary, at Z=2.5. Southern apron available beside (not owning) station rail tile."
    sc["effects"]="Native effect top anchors (2.48, 3.38, 2.10) and (4.34, 3.52, 2.10), relative to grass top."
    mats=R.materials()
    for idx,name in enumerate(COLORS):mats[idx].name=name.replace("_"," ").title()
    for name,fn in GROUPS:
        m=A.mesh();fn(m)
        c=bpy.data.collections.new(name);sc.collection.children.link(c)
        R.to_blender(m,c,mats)
    full=A.mesh()
    for _,fn in GROUPS:fn(full)
    for z,row in enumerate(FOOTPRINT):
        for x,gfx in enumerate(row):
            p=R.MODELS/f"bl_power_station_{x}_{z}.obj"
            R.export_obj(p,split(full,x,z))
            raw=p.read_text()
            p.write_text(raw.replace(raw.splitlines()[0],
                f"# Riverbend Power original, layout 0, ({x},{z}) gfx {gfx}; tools/build_power_station_art.py",1))
    write_palette()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                sp=area.spaces.active
                sp.shading.color_type="MATERIAL"
                sp.region_3d.view_location=(3.59,1.56,1.12)
                sp.region_3d.view_distance=10.5
                sp.region_3d.view_rotation=(Vector((3.52,1.60,1.12))-Vector((7.55,9.,5.7))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/riverbend_power_station.blend"),compress=True)
    if os.environ.get("POWER_STATION_RENDER"):review(sc,Path(os.environ["POWER_STATION_RENDER"]))

def review(sc,path):
    V=Vector
    bpy.ops.mesh.primitive_plane_add(size=28,location=(3.5,1.5,-.0013))
    grass=bpy.data.materials.new("Late summer grass")
    grass.diffuse_color=(.154,.250,.095,1)
    bpy.context.object.data.materials.append(grass)
    world=bpy.data.worlds.new("Country daylight")
    sc.world=world;world.use_nodes=True
    bg=world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value=(.60,.76,.92,1)
    bg.inputs[1].default_value=.54
    li=bpy.data.lights.new("Morning sun","SUN");li.energy=2.45;li.angle=.105
    sun=bpy.data.objects.new("Morning sun",li);sc.collection.objects.link(sun)
    sun.rotation_euler=(.40,-.52,-.58)
    ca=bpy.data.cameras.new("Riverbend survey");ca.type="ORTHO"
    ob=bpy.data.objects.new("Riverbend survey",ca);sc.collection.objects.link(ob);sc.camera=ob
    sc.render.engine="CYCLES";sc.cycles.samples=25;sc.cycles.use_denoising=False
    sc.view_settings.view_transform="AgX"
    sc.render.resolution_x=1216;sc.render.resolution_y=840
    sc.render.resolution_percentage=100
    for label,eye,aim,zoom in (
        ("",(8.30,11.48,7.56),(3.51,1.55,1.22),9.8),
        ("-truck",(8.24,5.81,2.38),(5.22,2.10,1.25),6.4),
    ):
        ca.ortho_scale=zoom
        ob.location=eye
        ob.rotation_euler=(V(aim)-ob.location).to_track_quat("-Z","Y").to_euler()
        sc.render.filepath=str(path.with_name(path.stem+label+".png"))
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":main()
