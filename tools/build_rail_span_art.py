"""Original LuanTTD rail timber trestle, stone tunnel, and editable Blender kit."""
from math import cos, pi, sin
from pathlib import Path
import os
from random import Random
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))

import build_road_bridge_art as kit
import build_rail_art as normal

bpy = kit.bpy
Vector = kit.Vector
BRIDGE = "bl_rail_bridge_wood"
TUNNEL = "bl_rail_tunnel_portal"
TRACK = {f"Stock rail {i}": c for i,c in enumerate(normal.COLORS)}
COLORS = TRACK | {
    "Timber — cut ends":"aa794d", "Deck plank":"86623f", "Deck honey":"95704d",
    "Deck grey":"786657","Deck dark":"775137","Grain line":"695040",
    "Stringer edge":"6f513d","Stringer":"584338","Timber shadow":"453730",
    "Iron nut":"a2a099","Iron strap":"56514b","Iron bolts":"a2a099","Steel straps":"56514b","Check rail":"666c65","Check rail crown":"8a8d7e",
    "Cinder 1":"706355","Cinder 2":"7b6d5c","Cinder 3":"897967",
    "Dressed cap":"a29c84","Ashlar warm":"8c826e","Ashlar cool":"858571",
    "Ashlar dark":"706b5e","Ashlar shadow":"635c52","Ashlar light":"aaa088","Pointed mortar":"615b4d",
    "Brick highlight":"af775c","Brick warm":"9a624e","Brick cool":"896150",
    "Clay mortar":"5e5046","Soot barrel 0":"534941","Soot barrel 1":"423d37",
    "Soot barrel 2":"383532","Soot barrel 3":"312f2e",
    "Turf":"57814c","Turf light":"5b844e","Turf dark":"537d46","Engraved brass":"a28a63",
    "Snow-white enamel":"d8cca9","Letter black":"464841"
}
HALF=.487
SPRING=.714
RISE=.285
MOUTH=.633
THROAT=.797
N=20

def track_color(i):
    return f"Stock rail {i}"

def tapered(m,g,color,a,b,h0,h1):
    # Trapezoidal plan; real taper into the running way.
    aa,ab,va=a
    ba,bb,vb=b
    lo=((aa,va,h0(va)),(ab,va,h0(va)),(bb,vb,h0(vb)),(ba,vb,h0(vb)))
    hi=((aa,va,h1(va)),(ab,va,h1(va)),(bb,vb,h1(vb)),(ba,vb,h1(vb)))
    m.poly(g,color,*hi)
    m.poly(g,color,*lo[::-1])
    for i in range(4):
        j=(i+1)%4
        m.poly(g,color,lo[i],lo[j],hi[j],hi[i])

def full_track(m,h,ballast,guards=None):
    bed=normal.BED_EDGE
    if ballast == "full":
        start=1
    elif ballast:
        start=-.34
    else:
        start=None
    if start is not None:
        sidew=lambda v:bed if ballast=="full" else bed-.075*max(0,(v+1)/(start+1))
        center=lambda v:normal.BED_CROWN if ballast=="full" else normal.BED_CROWN-.025*max(0,(v+1)/(start+1))
        cells=12
        for i in range(cells):
            a=-1+i*(start+1)/cells
            b=-1+(i+1)*(start+1)/cells
            for side in (-1,1):
                def pt(v,surface):
                    return (side*(center(v) if surface else sidew(v)), v, h(v)+(.036 if surface else .006))
                outline=(pt(a,1),pt(a,0),pt(b,0),pt(b,1))
                m.poly("Cinder shoulders",track_color((3+i*5+side)%6),*(outline if side>0 else outline[::-1]))
            pts=((-center(a),a,h(a)+.036),(center(a),a,h(a)+.036),
                 (center(b),b,h(b)+.036),(-center(b),b,h(b)+.036))
            m.poly("Cinder formation",track_color(2+i%2),*pts)
        if ballast!="full":
            # End of the formation has a real sloped cut to the old timbers.
            end=start+.20
            end_width=normal.SLEEPER-.02
            m.poly("Cinder termination","Cinder 1",(-sidew(start),start,h(start)+.006),
                   (-center(start),start,h(start)+.036),(-end_width,end,h(end)+.022))
            m.poly("Cinder termination","Cinder 2",(-center(start),start,h(start)+.036),
                   (center(start),start,h(start)+.036),(end_width,end,h(end)+.022),(-end_width,end,h(end)+.022))
            m.poly("Cinder termination","Cinder 1",(center(start),start,h(start)+.036),
                   (sidew(start),start,h(start)+.006),(end_width,end,h(end)+.022))
    for i in range(10):
        v=-.9+.20*i
        # Rusty inset fastening plates, beveled transverse sleepers.
        m.box("Creosoted rail sleepers",track_color(normal.END),-normal.SLEEPER,normal.SLEEPER,v-.046,v+.046,
              lambda s:h(s)+.026,lambda s:h(s)+.059,
              face_colors={"top":track_color(normal.BEVEL),"under":"Timber shadow"})
        m.box("Sleeper upper mill marks",track_color(6+i%5),-.325,.325,v-.036,v+.038,
              lambda s:h(s)+.059,lambda s:h(s)+.071)
        for sign in (-1,1):
            x=sign*normal.GAUGE/2
            m.box("Rail foot chairs",track_color(normal.CHAIR),x-.056,x+.056,v-.043,v+.043,
                  lambda s:h(s)+.070,lambda s:h(s)+.078)
            for u in (x-.051,x+.051):
                m.box("Forged spikes","Iron nut",u-.007,u+.007,v-.009,v+.009,
                      lambda s:h(s)+.075,lambda s:h(s)+.083)
    for x in (-normal.GAUGE/2,normal.GAUGE/2):
        # Same cross sections and top-strip breakpoints as ordinary track.
        for name,r,lo,hi,c in (("Rail foot",normal.FOOT,.068,.082,normal.FOOT_MAT),
                               ("Rail web",.016,.082,.099,normal.WEB),
                               ("Polished railhead",normal.HEAD,.099,.114,normal.HEAD_SIDE)):
            for side in (-1,1):
                u=x+side*r
                pts=[(u,-1,h(-1)+lo),(u,1,h(1)+lo),(u,1,h(1)+hi),(u,-1,h(-1)+hi)]
                m.poly(name,track_color(c),*(pts if side>0 else pts[::-1]))
        for a,b in ((x-normal.FOOT,x-.016),(x+.016,x+normal.FOOT)):
            m.section("Rail foot",track_color(normal.FOOT_MAT),a,b,-1,1,lambda s:h(s)+.082)
        m.section("Polished railhead",track_color(normal.STEEL),x-normal.HEAD,x+normal.HEAD,-1,1,
                  lambda s:h(s)+normal.TRACK_TOP)
    if guards:
        guard_start=-.30 if guards=="head" else -1
        for sign in (-1,1):
            x=sign*.122
            m.box("Renewable inner check steel","Check rail",x-.016,x+.016,guard_start,1,
                  lambda s:h(s)+.065,lambda s:h(s)+.090,end_faces=False,
                  face_colors={"top":"Check rail crown"})
            if guards=="head":
                # Flared throat leads in from the approach without trapping a flange.
                n=sign*.069
                tapered(m,"Pier check-rail throat","Check rail crown",(n-.014,n+.014,-.55),
                        (x-.016,x+.016,guard_start),lambda s:h(s)+.065,lambda s:h(s)+.090)

def timber(m,h,head):
    v0=-.68 if head else -1
    # Individual transverse open-deck sleepers bear on four full-length stringers.
    for u in (-.332,-.193,.193,.332):
        m.box("Continuous laminated pitch-pine stringers","Stringer",u-.059,u+.059,v0,1,
               lambda v:h(v)-.227,lambda v:h(v)-.049,end_faces=False,
               face_colors={"top":"Stringer edge","under":"Timber shadow"})
        for offset in (-.069,-.117,-.169):
            a,b=sorted((u+(1 if u>0 else -1)*.059,u+(1 if u>0 else -1)*.060))
            m.box("Visible stringer lamination seams","Timber shadow",a,b,v0,1,
                  lambda v:h(v)-.009+offset,lambda v:h(v)+offset,end_faces=False)
    palette=("Deck plank","Deck honey","Deck grey","Deck dark")
    n=14 if head else 17
    for i in range(n):
        a=v0+(1-v0)*i/n;b=v0+(1-v0)*(i+1)/n
        if i: a+=.004
        if i<n-1: b-=.004
        for sign in (-1,1):
            lo,hi=sorted((sign*.093,sign*.502))
            m.box("Treated wooden walkway planks",palette[(i*7+sign)%4],
                  lo,hi,a,b,lambda v:h(v)-.059,lambda v:h(v)+.022,
                  end_faces=i not in (0,n-1),face_colors={"under":"Timber shadow"})
            if i%3 != 0:
                lo,hi=sorted((sign*(normal.SLEEPER-.005),sign*normal.SLEEPER))
                m.section("Walking plank weathering","Grain line",lo,hi,a+.012,b-.016,lambda v:h(v)+.0227)
        # A central board connects to the inner walkways. Slight recess exposes sleeper profile.
        m.box("Inner timber bridge filler",palette[(i+2)%4],-.092,.092,a,b,
              lambda v:h(v)-.058,lambda v:h(v)+.015,end_faces=True)
    for v in (-.65,-.19,.27,.73):
        m.box("Transverse switch-timber bearers","Stringer edge",-.545,.545,v-.043,v+.043,
              lambda q:h(q)-.145,lambda q:h(q)-.059,face_colors={"right":"Timber — cut ends","left":"Timber — cut ends"})
    for sign in (-1,1):
        post=.493*sign
        if head:
            a,b=sorted((sign*.479,sign*.507))
            m.box("Rounded approach safety cap","Deck honey",a,b,-.576,-.550,
                  lambda v:h(v)+.197,lambda v:h(v)+.229)
        for lo,hi in ((.199,.234),(.095,.117)):
            a,b=sorted((sign*.477,sign*.517))
            m.box("Bridge inspection fence","Deck plank",a,b,-.552 if head else -1,1,
                  lambda v:h(v)+lo,lambda v:h(v)+hi,end_faces=False,
                  face_colors={"top":"Deck honey","under":"Timber shadow"})
        for v in (-.515,-.01,.495,.924):
            m.box("Landing fence upright","Deck dark",post-.029,post+.029,v-.031,v+.031,
                  lambda q:h(q)-.065,lambda q:h(q)+(.266 if v<.9 else .259),
                  face_colors={"top":"Timber — cut ends"})
            m.bolt("Landing fence hexagonal fastener",sign*.523,v,h(v)+.207,sign)
        # Beam joins reinforced with plates visible at the bridge quarter points.
        for v in (-.66,.24,.73):
            a,b=sorted((sign*.392,sign*.405))
            m.box("Riveted fish plate","Iron strap",a,b,v-.075,v+.075,
                  lambda q:h(q)-.198,lambda q:h(q)-.058)
            for delta in (-.038,.038):
                m.bolt("Fish plate heavy bolts",sign*.406,v+delta,h(v+delta)-.12,sign)

def support(m,pier=False):
    for u in (-.315,.315):
        tone="Stringer"
        m.box("Trestle twin king posts",tone,u-.061,u+.061,-.072,.072,-.5,.5 if pier else .067,
              face_colors={"front":"Stringer edge","left":"Deck dark","right":"Deck dark"})
        if not pier:
            m.box("Main bearing seat","Ashlar dark",u-.086,u+.086,-.095,.095,.055,.147,
                  face_colors={"top":"Dressed cap","front":"Ashlar warm"})
    if pier:
        for edge in (-.405,.398):
            m.box("Boxed bent belt","Deck dark",-.393,.393,-.093,.093,edge-.038,edge+.038,
                  face_colors={"top":"Stringer edge","front":"Deck plank"})
        for sign in (-1,1):
            m.bar("Cooked pine diagonal bracing","Deck dark",(sign*.315,sign*.098,-.415),(-sign*.315,sign*.098,.409),.077,.055)
            for top in (-.405,.398):
                m.bolt("Trestle chord hardware",sign*.397,.006,top,sign)
    else:
        m.box("Cross cap immediately below four stringers","Stringer edge",-.434,.434,-.12,.12,
              .149,.286,face_colors={"front":"Deck plank","top":"Timber — cut ends"})
        m.box("Cross cap lower sole","Stringer",-.386,.386,-.092,.092,.085,.148,
              face_colors={"under":"Timber shadow"})
        # Rods run through the structural cap and transfer load to the bent below.
        for sign in (-1,1):
            m.bolt("Bearing cap carriage bolts",sign*.437,.009,.214,sign)

def abutment(m,h,variant):
    # The anchor dips inside the stock supporting terrain. On the inner
    # side the face and foot stay continuous even on a declining approach.
    for i in range(7):
        low=-.506+i*.101
        high=low+.099
        edge=.636-.011*i
        v0=.419 if variant=="flat" else .654
        v1=.988
        m.box("Abutment heavy ashlar core","Ashlar dark",-edge,edge,v0,v1,low,high,
              end_faces=True,face_colors={"front":"Ashlar shadow","back":"Pointed mortar"})
        cols=("Ashlar warm","Ashlar dark","Ashlar cool","Ashlar light")
        for j in range(7):
            a=max(-edge,-edge+(j-.42*(i%2))*2*edge/6)
            b=min(edge,-edge+(j+1-.42*(i%2))*2*edge/6)
            if b-a<.012:continue
            m.box("Individual coursed ashlar blocks",cols[(3*i+j*7)%4],
                  a+.003,b-.003,.986,1.0,low+.003,high-.002,
                  face_colors={"top":"Ashlar light","right":"Ashlar shadow"})
        for sign in (-1,1):
            for j in range(3):
                a,b=sorted((edge*sign,(edge+.003)*sign))
                lo=v0+(v1-v0)*j/3+.004
                hi=v0+(v1-v0)*(j+1)/3-.004
                m.box("Rusticated abutment returns",cols[(i+3*j+sign)%4],a,b,lo,hi,low+.004,high-.004,
                      face_colors={"top":"Ashlar light"})
    m.box("Mortared railway bearing sill","Dressed cap",-.649,.649,.712,.997,.199,.264,
          end_faces=True,face_colors={"front":"Ashlar cool","under":"Ashlar shadow"})
    for sign in (-1,1):
        a,b=sorted((sign*.549,sign*.655))
        m.box("Capped bridge end wing","Ashlar warm",a,b,.472,1,.206,.296,
              face_colors={"top":"Dressed cap"})
        a,b=sorted((sign*.554,sign*.631))
        m.box("Distance plate support","Ashlar cool",a,b,.835,.930,.278,.342,
              face_colors={"top":"Ashlar light"})
        m.box("Enamel stone-mounted chainage marker","Snow-white enamel",a,b,.823,.834,.302,.332,
              face_colors={"front":"Snow-white enamel"})

def descending_land(m):
    # The level deck shares its native mesh anchor with its outward-rising
    # post-foundation ground shell. Preserve the one-level descending edge
    # corners while leaving space for stone abutment and bridge stringers.
    stages=(-1,-.77,-.48,-.11,.25,.62,1)
    strips=(-1,-.66,-.36,-.07,.16,.43,.72,1)
    turf=("Turf","Turf light","Turf","Turf dark","Turf")
    for j,(a,b) in enumerate(zip(stages,stages[1:])):
        for i,(u,w) in enumerate(zip(strips,strips[1:])):
            m.section("Exact outward-rising founded land",turf[(i*13+j*7)%5],u,w,a,b,lambda v:-v/2)

def bridge(variant):
    m=kit.Mesh()
    h=(lambda v:.5) if variant!="ramp" else (lambda v:v/2)
    if variant=="flat":
        descending_land(m)
    full_track(m,h,variant!="span",guards="span" if variant=="span" else "head")
    timber(m,h,variant!="span")
    if variant=="span":support(m)
    else:abutment(m,h,variant)
    return m


def incline(v):return (v+1)/2

def width(v):return .565+.193*(MOUTH-v)/(MOUTH+1)

def arch(theta,w=HALF,rise=RISE):
    return w*cos(theta),SPRING+rise*sin(theta)

def front(m,g,c,x0,x1,v,a,b,w=.016):
    m.box(g,c,x0,x1,v-w,v,a,b,face_colors={"right":"Ashlar shadow","top":"Ashlar light"})

def tunnel():
    m=kit.Mesh()
    full_track(m,lambda v:0,"full")
    rng=Random(3417)
    turf=("Turf","Turf","Turf dark","Turf light","Turf")
    dirt=("Cinder 1","Cinder 2","Cinder 3")
    stones=("Ashlar warm","Ashlar cool","Ashlar dark","Ashlar light")
    for side in (-1,1):
        def sidepoly(g,c,pts):
            m.poly(g,c,*(pts if side>0 else pts[::-1]))
        pts=tuple(-1+i*(MOUTH+1)/13 for i in range(14))
        for i,(a,b) in enumerate(zip(pts,pts[1:])):
            bi=lambda v:.002*min(1,(v+1)*7)
            sidepoly("Rail cut drainage ways",dirt[i%3],[(side*normal.BED_EDGE,a,bi(a)),(side*width(a),a,bi(a)),
                      (side*width(b),b,bi(b)),(side*normal.BED_EDGE,b,bi(b))])
            sidepoly("Dressed wing cap blocks","Dressed cap",[(side*width(a),a,incline(a)),
                      (side*(width(a)+.081),a,incline(a)),(side*(width(b)+.081),b,incline(b)),
                      (side*width(b),b,incline(b))])
            sidepoly("Cut into natural graded turf",rng.choice(turf),[(side*(width(a)+.081),a,incline(a)),
                      (side*1.,a,incline(a)),(side*1.,b,incline(b)),(side*(width(b)+.081),b,incline(b))])
            for course in range(10):
                low=.079*course
                l=max(a,2*(low-.002)-1)+.0003
                r=b
                if l>=r:continue
                top=lambda v:min(low+.079,incline(v))
                floor=lambda v:min(low,incline(v)-.0001)
                sidepoly("Tapered quarry-stone curtain walls",stones[(course+i*7+side)%4],
                         [(side*width(l),l,top(l)),(side*width(r),r,top(r)),
                          (side*width(r),r,floor(r)),(side*width(l),l,floor(l))])
        for i in range(10):
            a,b=sorted((side*HALF,side*.572))
            low=i*SPRING/10
            front(m,"Recessed brick portal jambs","Clay mortar",a,b,MOUTH,low,low+SPRING/10)
            front(m,"Fired brick jamb facing",("Brick highlight","Brick cool","Brick warm")[(i+side)%3],
                  a+.002,b-.003,MOUTH-.020,low+.003,low+SPRING/10-.003,.016)
        for i in range(11):
            a,b=sorted((side*.573,side*.713))
            h=i*.103
            front(m,"Dressed stone side of portal",stones[(3*i+side)%4],a,b,MOUTH+.013,h,h+.102,.024)
        for j in range(8):
            a=MOUTH+(1-MOUTH)*j/8
            b=MOUTH+(1-MOUTH)*(j+1)/8
            for course in range(7):
                lo=course*SPRING/7;hi=(course+1)*SPRING/7
                tone=f"Soot barrel {min(3,1+j//3)}"
                sidepoly("Interior soot-darkened barrel jambs",tone,[(side*HALF,a,hi),(side*HALF,b,hi),
                                                                   (side*HALF,b,lo),(side*HALF,a,lo)])
        for v in (-.08,.427):
            a,b=sorted((side*.505,side*.532))
            m.box("Milepost pale plinth","Ashlar cool",a,b,v-.020,v+.019,.002,.072,
                  face_colors={"top":"Snow-white enamel"})
            front(m,"Smoked enamel track mileage plate","Snow-white enamel",a+.002,b-.003,v-.021,.040,.065,.003)
        v0=MOUTH;v1=MOUTH+.026
        sidepoly("Corner seam outside retaining head","Turf",[(side*.713,v0,incline(v0)),
                   (side*1.,v0,incline(v0)),(side*1.,v1,incline(v1)),(side*.713,v1,incline(v1))])
    # Exact open brick segmental arch. The inside never terminates in a fake black end panel.
    tones=("Brick warm","Brick highlight","Brick cool","Brick warm")
    for i in range(N):
        a=pi-pi*i/N;b=pi-pi*(i+1)/N
        li,ri=arch(a),arch(b)
        lo,ro=arch(a,.572,.352),arch(b,.572,.352)
        m.poly("Mortared arch rib","Clay mortar",(li[0],MOUTH,li[1]),(ri[0],MOUTH,ri[1]),
               (ro[0],MOUTH,ro[1]),(lo[0],MOUTH,lo[1]))
        f=MOUTH-.046
        rib=[arch(a-.008,HALF+.001,RISE+.001),arch(b+.008,HALF+.001,RISE+.001),
             arch(b+.008,.569,.349),arch(a-.008,.569,.349)]
        m.poly("Separate weathered brick voussoirs",tones[i%4],*[(x,f,h) for x,h in rib])
        for j,(u,y) in enumerate(rib):
            x,h=rib[(j+1)%4]
            m.poly("Voussoir beveled edges","Brick cool",(x,f,h),(u,f,y),(u,MOUTH,y),(x,MOUTH,h))
        m.poly("Ashlar spandrel above aperture",stones[(i*3)%4],(lo[0],MOUTH,lo[1]),
               (ro[0],MOUTH,ro[1]),(ro[0],MOUTH,1.151),(lo[0],MOUTH,1.151))
        for j in range(9):
            v0=MOUTH+(1-MOUTH)*j/9;v1=MOUTH+(1-MOUTH)*(j+1)/9
            tone=f"Soot barrel {min(3,(j+(i%2))//2)}"
            m.poly("Coursed brick intrados",tone,(li[0],v0,li[1]),(li[0],v1,li[1]),
                   (ri[0],v1,ri[1]),(ri[0],v0,ri[1]))
    m.box("Quarry-cut cornice with projecting drip","Ashlar cool",-.724,.724,MOUTH-.083,MOUTH+.115,1.144,1.194,
          face_colors={"top":"Dressed cap","under":"Ashlar shadow"})
    front(m,"Raised arch keystone","Dressed cap",-.042,.042,MOUTH-.059,1.032,1.164,.023)
    for side in (-1,1):
        a,b=sorted((side*.563,side*.716))
        front(m,"Cornice spring supports","Ashlar warm",a,b,MOUTH+.010,1.112,1.152,.036)
    # Roof follows the existing exact terrain along side edges. A narrow
    # spoil mound swells around the cornice and tapers to the ordinary crest.
    strips=(-1,-.803,-.716,-.558,-.450,-.225,0,.225,.450,.558,.716,.803,1)
    stages=(MOUTH+.026,THROAT,.881,1)
    def crown(x,v):
        over=max(0.0,min(1.0,(.806-abs(x))/.099))
        t=(1-v)/(1-stages[0])
        base=incline(v)
        # Near the crown the grade can be barely lower than the physical
        # arch; guarantee roof remains above the interior ellipse.
        return max(base+(1.184-incline(stages[0]))*t*over,
                   (SPRING+RISE*(max(0.,1-(x/HALF)**2))**.5+.007*t) if abs(x)<=HALF else base)
    for j,(a,b) in enumerate(zip(stages,stages[1:])):
        for i,(u,w) in enumerate(zip(strips,strips[1:])):
            m.poly("Crowned cut turf and portal backfill",turf[(3*i+2*j)%5],(u,a,crown(u,a)),(w,a,crown(w,a)),
                   (w,b,crown(w,b)),(u,b,crown(u,b)))
    return m


def lower(m,h):
    out=kit.Mesh()
    for g,faces in m.groups.items():
        for color,p in faces:
            out.poly(g,color,*[(u,v,a+h) for u,v,a in p])
    return out


def showcase(parts):
    scene=bpy.context.scene
    collection=lambda prefix,name:parts[prefix,name]
    for v,p in ((-4,"head_ramp_1"),(-2,"span_1"),(0,"span_1"),(2,"span_1"),(4,"head_ramp_3")):
        kit.instance(collection(BRIDGE,p),(-2.3,v,1))
    for v in (-2,0,2):
        kit.instance(collection(BRIDGE,"pier_1"),(-2.3,v,0))
    kit.instance(collection(TUNNEL,"1"),(2.4,0,0))
    def plain(name,loc,size,color):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        ob=bpy.context.object;ob.name=name;ob.scale=size
        mat=bpy.data.materials.new(name);mat.diffuse_color=(*color,1);ob.data.materials.append(mat)
    for v in (-4,4):
        plain("Grounded timber approach",(-2.3,v,0),(2.4,2,1),(.13,.25,.09))
    plain("Foothills",(2.4,-2.1,-.50),(2.0,2.2,1),(.13,.25,.09))
    plain("Cut earth floor",(2.4,0,-.50),(2.0,2.0,1),(.13,.25,.09))
    for u in (1.63,3.17):
        plain("Hill continuation", (u,2.4,.19),(.46,2.8,1.63),(.14,.243,.11))
    plain("Hill grass above vaulted cut",(2.4,2.4,1.076),(2,2.8,.152),(.14,.243,.11))
    plain("Shadow behind the demonstration bore",(2.4,3.66,.504),(1.08,.06,1.016),(.028,.027,.026))
    plain("Slate backdrop below viaduct",(0,0,-.638),(200,200,.08),(.165,.231,.245))
    bpy.ops.object.camera_add(location=(10,-14,8.3))
    ca=bpy.context.object
    ca.rotation_euler=(Vector((-.4,.18,.32))-ca.location).to_track_quat("-Z","Y").to_euler()
    ca.data.type="ORTHO";ca.data.ortho_scale=11
    scene.camera=ca
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1640;scene.render.resolution_y=1090
    scene.display.shading.light="STUDIO"
    scene.display.shading.studio_light="paint.sl"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.20
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Overcast harbour light")
    scene.world.color=(.15,.19,.225)
    scene.view_settings.view_transform="Standard"

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    kit.COLORS=COLORS
    mats=kit.materials()
    parts={}
    for prefix,part_names in (
        (BRIDGE,dict([(f"span_{a}",bridge("span").oriented(d)) for a,d in enumerate((2,1))]+
                     [(f"head_{t}_{d}",bridge(t).oriented(d)) for t in ("flat","ramp") for d in range(4)]+
                     [(f"pier_{a}",(lambda m:(support(m,pier=True),m)[1])(kit.Mesh()).oriented(d))
                      for a,d in enumerate((2,1))])),
        (TUNNEL,{str(d):tunnel().oriented(d) for d in range(4)})
    ):
        kit.PREFIX=prefix
        for name,m in part_names.items():
            kit.export(name,lower(m,-.5) if prefix==TUNNEL else m)
            parts[prefix,name]=kit.author(m," / ".join((prefix,name)),mats)
        kit.atlas()
    showcase(parts)
    bpy.context.scene.name="LuanTTD | Timber railway trestle and masonry bore"
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/"art"/"rail_spans.blend"),compress=True)
    if target:=os.getenv("RAIL_SPAN_RENDER"):
        bpy.context.scene.render.filepath=target
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()
