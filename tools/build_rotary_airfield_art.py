#!/usr/bin/env python3
"""Original RC1 Helidepot and Helistation continuous sheets and native tile media.

python3 tools/build_rotary_airfield_art.py --check
blender -b -t 3 --python-exit-code 1 --python tools/build_rotary_airfield_art.py -- --blend --preview /tmp
"""
from argparse import ArgumentParser
from dataclasses import dataclass
from math import cos, hypot, pi, sin, sqrt
from pathlib import Path
import sys
from random import Random

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_heliport_art import Art, png

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
DATUM=-.5
APRON=-.496
PAINT=-.485
SPAN=(-.48,1.48)
PORTAL=(-.445,1.445)  # swept envelope for current Tricario and Guru X2
PORTAL_ARCH_CLEAR_Y=1.47
COLORS={
    "Apron aggregate":"777570","Apron patch":"797874","Apron warmer":"7e7970",
    "Deck inset":"636969","Deck highlight":"747876","Expansion crease":"63645e",
    "Gravel shoulder":"8a8477","H enamel":"f6edca","Narrow yellow taxi lead":"c8aa60",
    "Hazard dark":"393f3b","Warm concrete":"bcb19c","Pale dry concrete":"d5c6ac",
    "Mortar and soffit":"867968","Brick rust":"9d624b","Brick warm":"a8765e",
    "Brick shadow":"855949","Depot mullions":"596963","Glass trench":"2f4144",
    "Glass teal":"52777a","Glass light":"779598","Glass shadow":"3e595e",
    "Steel roof graphite":"3f515a","Steel roof rain":"5c737c","Steel roof powder blue":"6a818a",
    "Steel trim":"4a605f","Blue fascia":"46616a","Depot coping":"52717a",
    "Station paint":"a59873","Station enamel green":"52766c","Station frame":"326154",
    "Office felt roof":"566260","Office gravel roof":"76766a","Workroom floor":"64625a",
    "Perimeter rail blue":"647b7a","Perimeter rail shade":"3d5758","Gravel shadow":"78776a",
    "Parking cream light":"e8ca91","Parking amber rim":"b99e69","Door brass":"b0a077",
}

# Coordinates relative to the RC1 north-west tile; field order is z then x.
# Fence directions are the literal x or z edge offsets from station_land.h,
# not the iso compass labels on sprite names.
DEPOT=(
    ("office","north west"),("hangar",""),
    ("pad","west south"),("apron","east south"),
)
STATION=(
    ("hangar",""),("office","north"),("pad","north"),("pad","north east"),
    ("apron","west south"),("apron","south"),("apron","south"),("pad","south east"),
)


@dataclass(frozen=True)
class Airfield:
    name:str
    cells:tuple
    width:int
    park_px:tuple
    depot_px:tuple
    start_year:int

    def variant(self,x,z):return self.cells[z*self.width+x]


FIELDS=(
    Airfield("helidepot",DEPOT,2,((8,24),),(24,4),1976),
    Airfield("helistation",STATION,4,((40,8),(56,8),(56,24)),(8,3),1980),
)


def px_to_native(p):
    return tuple(n/8-.5 for n in p)


def draw_line(a,name,mat,points,width,height):
    for (x,z),(u,v) in zip(points,points[1:]):
        dx,dz=u-x,v-z
        d=hypot(dx,dz)
        if d<1e-8:continue
        cx,cz=dz*width/(2*d),-dx*width/(2*d)
        a.face(name,mat,(x+cx,height,z+cz),(x-cx,height,z-cz),
               (u-cx,height,v-cz),(u+cx,height,v+cz))


def octagon(cx,cz,rx,rz,cut=.15):
    return [(cx-rx+cut,cz-rz),(cx+rx-cut,cz-rz),(cx+rx,cz-rz+cut),(cx+rx,cz+rz-cut),
            (cx+rx-cut,cz+rz),(cx-rx+cut,cz+rz),(cx-rx,cz+rz-cut),(cx-rx,cz-rz+cut)]


def concrete(a,field,tx,tz):
    slot="01 Continuous airfield concrete"
    a.plate(slot,"Apron aggregate",-.5,1.5,-.5,1.5,APRON)
    # Same seam value on both sides of the tile; pitch derived across the
    # continuous slab, no offset panels or overlapping grass top.
    for side in ("west","east","north","south"):
        if side in ("west","east"):
            x=-.5 if side=="west" else 1.484
            a.plate(slot,"Expansion crease",x,x+.016,-.5,1.5,APRON+.002)
        else:
            z=-.5 if side=="north" else 1.484
            a.plate(slot,"Expansion crease",-.484,1.484,z,z+.016,APRON+.002)
    rng=Random((field.width<<12)+tx*131+tz*127)
    for i in range(11):
        x=-.45+1.69*rng.random()
        z=-.45+1.69*rng.random()
        w=.028+rng.random()*.16
        h=.022+rng.random()*.12
        a.plate(slot,"Apron warmer" if i%3==0 else "Apron patch",x,x+w,z,z+h,APRON+.001+i*.00005)


def line_inside(a,name,mat,x0,x1,z0,z1,h=PAINT):
    x0,x1=max(x0,-.5),min(x1,1.5)
    z0,z1=max(z0,-.5),min(z1,1.5)
    if x1-x0>1e-7 and z1-z0>1e-7:a.plate(name,mat,x0,x1,z0,z1,h)


def route(a,field,tx,tz):
    name="02 Followable yellow apron guidance"
    # Horizontal ground transfer is sewn exactly across all applicable tiles.
    # OpenTTD stock still owns taxi motion; paint is visual only.
    if field.width==2:
        stripes=((.50,2.502,2.466,2.516),(2.476,2.524,1.18,3.01),(.476,.524,1.505,2.01))
    else:
        stripes=((.50,6.50,2.225,2.27),(.476,.524,1.10,2.248),(4.476,4.524,1.08,2.247),
                 (6.476,6.524,1.08,2.25))
    for n,(x0,x1,z0,z1) in enumerate(stripes):
        line_inside(a,name,"Narrow yellow taxi lead",x0-2*tx,x1-2*tx,z0-2*tz,z1-2*tz,PAINT+.0005*n)


def pad(a,field,tx,tz):
    name="03 Marked helicopter stand"
    coord=[(x-2*tx,z-2*tz) for x,z in map(px_to_native,field.park_px)
           if -.5<x-2*tx<1.5 and -.5<z-2*tz<1.5]
    assert len(coord)==1,(field,tx,tz)
    cx,cz=coord[0]
    dep=field.width==2
    if dep:
        # Explicit ground-level circle rather than Helistation's raised-looking square.
        rpts=[(cx+.834*cos(2*pi*i/28),cz+.834*sin(2*pi*i/28)) for i in range(28)]
    else:
        rpts=octagon(cx,cz,.847,.847,.152)
    a.face(name,"Deck inset",*[(x,APRON+.008,z) for x,z in reversed(rpts)])
    if dep:
        for i in range(30):
            p,q=2*pi*i/30,2*pi*(i+1)/30
            # White closed ring, skew to inset to clear taxi-side cable fixtures.
            a.face(name,"H enamel",*((cx+r*cos(t),PAINT+.004,cz+r*sin(t)) for r,t in
                                    ((.635,p),(.635,q),(.704,q),(.704,p))))
    else:
        corners=[
            ((cx-.65,cz-.51),(cx-.65,cz-.66),(cx-.48,cz-.66)),
            ((cx+.48,cz-.66),(cx+.65,cz-.66),(cx+.65,cz-.51)),
            ((cx-.65,cz+.51),(cx-.65,cz+.66),(cx-.48,cz+.66)),
            ((cx+.48,cz+.66),(cx+.65,cz+.66),(cx+.65,cz+.51)),
        ]
        # Segments stop a hair apart rather than drawing two coplanar quads
        # over the corners and causing glimmer on the yellow stencil.
        for left,joint,right in corners:
            shorten=lambda p,q:(p[0]+.16*(q[0]-p[0]),p[1]+.16*(q[1]-p[1]))
            draw_line(a,name,"Parking amber rim",[left,shorten(joint,left)],.023,PAINT+.003)
            draw_line(a,name,"Parking amber rim",[shorten(joint,right),right],.023,PAINT+.003)
    w=.350 if dep else .395
    start,stop=cx-w,cx+w
    a.plate(name,"H enamel",start,start+.102,cz-.37,cz+.37,PAINT+.004)
    a.plate(name,"H enamel",stop-.102,stop,cz-.37,cz+.37,PAINT+.004)
    a.plate(name,"H enamel",start+.102,stop-.102,cz-.055,cz+.055,PAINT+.004)
    for dx,dz in ((-.755,-.33),(.755,.33),(-.33,.755),(.33,-.755)):
        a.box(name,"Steel trim",cx+dx-.027,cx+dx+.027,APRON+.007,APRON+.027,cz+dz-.026,cz+dz+.026)
        a.plate(name,"Parking cream light",cx+dx-.018,cx+dx+.018,cz+dz-.017,cz+dz+.017,APRON+.0273)


def fencing(a,edges):
    name="04 Low steel perimeter guardrail (RC1 fence edges)"
    for end in edges.split():
        vertical=end in ("west","east")
        shift=-.442 if end in ("west","north") else 1.442
        def wire(material,t0,t1,k0,k1,y0,y1):
            args=(shift+k0,shift+k1,y0,y1,t0,t1) if vertical else (t0,t1,y0,y1,shift+k0,shift+k1)
            a.box(name,material,*args)
        for j in range(8):
            t=-.405+j*.258
            wire("Perimeter rail shade",t-.019,t+.019,-.018,.018,APRON,-.040)
            wire("Perimeter rail blue",t-.023,t+.023,-.021,.021,-.068,-.025)
        wire("Perimeter rail blue",-.467,1.467,-.013,.013,-.097,-.081)
        wire("Perimeter rail shade",-.467,1.467,-.010,.010,-.210,-.194)


def trim_band(a,label,x0,x1,z0,z1,y,color,h=.026):
    a.box(label,color,x0,x1,y,y+h,z0,z1)


def hangar(a,station):
    body="05 Open southeast helicopter maintenance bay"
    shell="06 Pressed-metal corrugated barrel roof"
    xlo,xhi=SPAN
    z0,z1=-.37,1.325
    x0,x1=PORTAL
    eave=1.27
    frame="Station frame" if station else "Depot coping"
    slab="Pale dry concrete" if station else "Warm concrete"
    a.box(body,"Workroom floor",xlo,xhi,APRON,APRON+.012,z0,z1)
    for l,h,zc,zd in ((xlo,x0,z0,z1),(x1,xhi,z0,z1)):
        a.box(body,"Brick shadow",l,h,APRON,eave,zc,zd,slab)
    # An open-backed structural roof creates real headroom. Continuing the
    # bay through the rear avoids a last-frame blade strike when the stock
    # rotorcraft reaches its shallow depot coordinate and becomes hidden.
    def coord(i,rim=0):
        angle=pi*i/12
        return .5-(.957+rim)*cos(angle),eave+(.768+rim)*sin(angle)
    for i in range(12):
        x,y=coord(i); u,v=coord(i+1)
        xa,ya=coord(i,.031); ub,vb=coord(i+1,.031)
        color=("Steel roof graphite","Steel roof rain","Steel roof powder blue","Steel roof rain")[i%4]
        # Roof surface outward/up, soffit downward, front and rear curved trims.
        a.face(shell,color,(xa,ya,-.428),(xa,ya,1.455),(ub,vb,1.455),(ub,vb,-.428))
        a.face(shell,"Mortar and soffit",(x,y,-.428),(u,v,-.428),(u,v,1.455),(x,y,1.455))
        a.face(shell,frame,(x,y,1.455),(u,v,1.455),(ub,vb,1.455),(xa,ya,1.455))
        a.face(shell,frame,(xa,ya,-.428),(ub,vb,-.428),(u,v,-.428),(x,y,-.428))
        a.face(body,slab,(x,eave,-.368),(x,y,-.368),(u,v,-.368),(u,eave,-.368)) if 0<i<11 else None
        if i in (2,3,4,7,8,9):
            for j in (0,1,2):
                zz=-.335+j*.617
                # Short standing seam strips in the local inclined segment.
                a.face(shell,"Steel roof powder blue",
                      (xa,ya+.006,zz),(xa,ya+.006,zz+.018),(ub,vb+.006,zz+.018),(ub,vb+.006,zz))
    for x in (-.469,1.469):
        a.box(body,frame,x-.017,x+.017,APRON,eave-.016,1.329,1.404)
        for j in range(5):
            y=-.485+j*.069
            a.wall(body,"Narrow yellow taxi lead" if j%2==0 else "Hazard dark","south",1.405,x-.018,x+.018,y,y+.046)
    # Ground/service lights, tool rails and gable trim stay outside the swept width.
    for x in (-.469,1.469):
        a.box(body,"Parking cream light",x-.018,x+.018,1.080,1.139,1.327,1.360)
        for j in range(3):
            zz=-.132+j*.29
            a.plate(body,"Expansion crease",x-.023,x+.023,zz,zz+.020,APRON+.014)
    for n in range(5):
        y=-.285+n*.276
        for x,dx in ((xlo,-1),(xhi,1)):
            a.wall(body,"Hazard dark","west" if dx<0 else "east",x+.0015*dx,-.30,1.28,y,y+.074)
            a.wall(body,slab,"west" if dx<0 else "east",x+.0025*dx,-.30,1.28,y+.072,y+.092)
    for l,h in ((-.487,-.451),(1.451,1.487)):
        a.box(body,"Steel trim",l,h,APRON+.025,.108,-.119,.45)
        a.box(body,"Mortar and soffit",l,h,.108,.151,-.147,.47)
    # Rounded metal gable at the nose, facility registration independent from art.
    a.box(body,frame,xlo+.010,xlo+.041,eave-.009,eave+.100,-.382,1.382)
    a.box(body,frame,xhi-.041,xhi-.010,eave-.009,eave+.100,-.382,1.382)


def terminal(a,station):
    name="07 Terminal checked luggage and waiting room"
    exterior="08 Recessed windows, passenger doors and entrance canopy"
    base="Brick rust" if station else "Brick warm"
    cap="Office felt roof" if station else "Office gravel roof"
    trim="Station enamel green" if station else "Depot coping"
    if station:
        z0,z1=-.295,.780
        xp,xm=-.290,1.245
        a.box(name,base,xp,xm,APRON,.326,z0,z1)
        a.box(name,base,xp,.434,APRON,.326,z1,1.269)
        a.box(name,cap,xp-.045,xm+.047,.317,.399,z0-.049,z1+.024,"Warm concrete")
        a.box(name,cap,xp-.044,.479,.317,.399,z1+.025,1.317,"Warm concrete")
        a.box(name,"Warm concrete",xp-.016,.468,APRON,APRON+.025,1.259,1.397)
        south=1.271
        for x in (.465,.664,.870,1.074):
            a.wall(exterior,"Glass trench","south",.783,x+.018,x+.182,-.285,.229)
            a.wall(exterior,"Glass teal","south",.786,x+.037,x+.166,-.233,.196)
            a.wall(exterior,"Glass light","south",.789,x+.044,x+.163,.147,.185)
        a.box(exterior,trim,xp-.014,.469,.181,.234,1.267,1.436)
        for n in range(3):
            x=xp+.06+n*.24
            a.box(exterior,"Steel trim",x-.012,x+.012,APRON,.184,1.405,1.429)
    else:
        xp,xm=-.276,1.26
        z0,z1=-.306,1.003
        a.box(name,base,xp,xm,APRON,.301,z0,z1)
        a.box(name,cap,xp-.052,xm+.047,.294,.375,z0-.041,z1+.059,"Warm concrete")
        a.box(name,"Office felt roof",.64,1.141,.369,.478,-.178,.252)
        south=1.005
        a.box(exterior,trim,xp+.022,.486,.135,.196,1.005,1.242)
        a.box(name,"Warm concrete",xp,.504,APRON,APRON+.034,.99,1.298)
        for j in range(3):
            x=.58+j*.210
            a.wall(exterior,"Glass trench","south",south,x,x+.172,-.26,.214)
            a.wall(exterior,"Glass teal","south",south+.002,x+.018,x+.152,-.216,.172)
            a.wall(exterior,"Glass light","south",south+.004,x+.021,x+.147,.106,.153)
    for edge,x,p,q in (("west",xp-.002,z0+.111,south-.121),("north",z0-.002,xp+.078,xm-.104)):
        for j in range(4):
            width=(q-p)/4
            f=p+j*width
            end=f+width*.77
            a.wall(exterior,"Glass trench",edge,x,f,end,-.246,.216)
            a.wall(exterior,"Glass teal",edge,x-.003,f+.019,end-.019,-.202,.172)
            a.wall(exterior,"Glass light",edge,x-.005,f+.024,end-.025,.116,.156)
    for j in range(2):
        x=xp+.070+j*.236
        a.wall(exterior,"Glass trench","south",south+.002,x,x+.165,APRON+.04,.127)
        a.wall(exterior,"Glass shadow","south",south+.004,x+.018,x+.143,APRON+.063,.101)
        a.wall(exterior,"Door brass","south",south+.006,x+.116,x+.133,-.251,-.234)
    # Real brick coursing on the wall's opaque bottom skirt; not a big textured label.
    for j in range(3):
        y=-.433+j*.035
        edge="Brick shadow" if j%2 else "Mortar and soffit"
        a.wall(name,edge,"north",z0-.003,xp+.012,xm-.012,y,y+.007)
        a.wall(name,edge,"west",xp-.003,z0+.005,south-.018,y,y+.007)


def make(field):
    out={}
    for z in range(2):
        for x in range(field.width):
            a=Art()
            tile,edges=field.variant(x,z)
            concrete(a,field,x,z)
            route(a,field,x,z)
            if tile=="hangar":hangar(a,field.width==4)
            if tile=="office":terminal(a,field.width==4)
            if tile=="pad":pad(a,field,x,z)
            if edges:fencing(a,edges)
            out[x,z]=a
    return out


def rgb(name):return tuple(bytes.fromhex(COLORS[name]))


def atlas():
    row=b"".join(bytes(rgb(n))*6 for n in COLORS)
    row+=bytes(rgb(list(COLORS)[-1]))*(256-len(row)//3)
    return png(256,16,[row]*16)


def obj(a,field,x,z):
    names={n:i+1 for i,n in enumerate(COLORS)}
    out=[f"# Original RC1 {field.name} area ({x},{z}); tools/build_rotary_airfield_art.py","o Facility"]
    out.extend(f"vt {(6*i+3)/256:.8f} .5" for i in range(len(names)))
    vertices,normals,polygons={},{},[]
    for part,faces in a.parts.items():
        polygons.append("# "+part)
        for mat,face in faces:
            pts=list(reversed([(-x,y,z) for x,y,z in face]))
            ix=[vertices.setdefault(tuple(round(v,6) or 0 for v in p),len(vertices)+1) for p in pts]
            u=[pts[1][j]-pts[0][j] for j in range(3)]
            v=[pts[2][j]-pts[0][j] for j in range(3)]
            n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
            d=sqrt(sum(q*q for q in n))
            assert d>1e-9,(part,mat,face)
            ni=normals.setdefault(tuple(round(q/d,7) or 0 for q in n),len(normals)+1)
            for i in range(1,len(face)-1):
                polygons.append("f "+" ".join(f"{ix[j]}/{names[mat]}/{ni}" for j in (0,i,i+1)))
    out.extend("v "+" ".join(f"{q:.6f}" for q in v) for v in vertices)
    out.extend("vn "+" ".join(f"{q:.7f}" for q in n) for n in normals)
    out.extend(polygons)
    return ("\n".join(out)+"\n").encode()


def canvas():
    S=4
    P=32*S
    buf=bytearray(P*P*4)
    def poly(points,color):
        points=[(x*S,y*S) for x,y in points]
        ink=bytes.fromhex(color)+b"\xff"
        for i in range(P):
            y=i+.5
            if not min(p[1] for p in points)<=y<=max(p[1] for p in points):continue
            for j in range(P):
                x=j+.5
                inside=False
                for (a,b),(c,d) in zip(points,points[1:]+points[:1]):
                    if (b>y)!=(d>y) and x<a+(c-a)*(y-b)/(d-b):inside=not inside
                if inside:
                    ix=4*(P*i+j);buf[ix:ix+4]=ink
    def export():
        out=[]
        for y in range(32):
            row=bytearray()
            for x in range(32):
                k=((y*S)*P+x*S)*4
                cells=[buf[k+4*(P*j+i):k+4*(P*j+i)+4] for i in range(S) for j in range(S)]
                opaque=[c for c in cells if c[3]]
                if opaque:
                    row.extend(round(sum(c[j] for c in opaque)/len(opaque)) for j in range(3))
                    row.append(round(255*len(opaque)/(S*S)))
                else:row.extend(b"\0\0\0\0")
            out.append(row)
        return png(32,32,out,True)

    return poly,export


def icon(field):
    poly,export=canvas()
    station=field.width==4
    if station:
        poly([(1,16),(16,4),(30,12),(31,24),(19,32),(2,24)],"20363b")
        poly([(2,19),(16,8),(30,14),(30,23),(19,30),(3,23)],"857761")
        poly([(3,19),(16,9),(29,15),(29,22),(19,28),(4,22)],"646c64")
        hx,hy=5,4
        for x,y in [(18,18),(23,20),(19,24)]:
            poly([(x-3,y),(x,y-2),(x+4,y),(x+4,y+2),(x+.3,y+3.4),(x-3,y+1.3)],"485956")
            poly([(x-2,y+.25),(x-.9,y-.45),(x+.85,y+1.81),(x-.2,y+2.32)],"f7edc9")
            poly([(x+.2,y-.85),(x+1.3,y-1.45),(x+3.23,y+.72),(x+2.1,y+1.5)],"f7edc9")
            poly([(x-.57,y+.77),(x+1.84,y-.25),(x+2.4,y+.28),(x+.2,y+1.59)],"f7edc9")
        poly([(10,16),(13,14),(18,16),(18,18),(15,20),(10,18)],"9a7058")
        poly([(10,16),(13,14),(18,16),(15,18)],"83a091")
    else:
        poly([(1,17),(16,5),(31,14),(31,24),(18,31),(2,25)],"23373d")
        poly([(2,19),(16,8),(30,15),(30,23),(18,29),(3,24)],"897f6c")
        poly([(3,19),(16,9),(29,15),(29,22.4),(18,28),(4,23)],"686c62")
        hx,hy=5,5
        poly([(16,14),(19,12),(26,16),(26,19),(22,21),(16,17)],"94634c")
        poly([(16,14),(19,12),(26,16),(22,18)],"87988d")
        for i in range(24):
            a,b=i*2*pi/24,(i+1)*2*pi/24
            poly([(19.8+r*cos(t),22.8+r*.56*sin(t)) for r,t in ((6.35,a),(6.35,b),(4.85,b),(4.85,a))],"f2dfae")
        poly([(17.45,21.85),(18.6,21.39),(20.55,23.47),(19.47,24.01)],"ffefc9")
        poly([(20.15,21.28),(21.36,20.80),(23.4,22.75),(22.37,23.40)],"ffefc9")
        poly([(19.11,22.38),(21.2,21.60),(21.82,22.25),(19.77,23.04)],"ffefc9")
    def hang(points,color):poly([(hx+x,hy+y) for x,y in points],color)
    hang([(-1,1),(5,-2),(13,3),(14,6),(14,11),(11,13),(6,12),(-1,8)],"334954")
    hang([(0,4),(6,7),(6,12),(0,9)],"a79a81")
    hang([(7,6),(13,3.8),(13,10.6),(12,11.5),(12,7),(10.8,6.7),(7.8,8.35),(7.8,11.7),(6.8,12.5)],"c7ba9c")
    hang([(7.5,8),(10.6,6.6),(12.1,7),(12.15,10.9),(7.5,12)],"29393a")
    hang([(0,4),(1,1),(6,-1),(11,1),(13,3.7),(11.6,5),(7,7),(3.6,6)],"758b97")
    hang([(1.3,2.1),(5.9,.2),(9.8,1.2),(10.7,2.15),(5.1,4.16),(3,3.65)],"9caeb0")
    hang([(1,6.1),(5.7,8.1),(5.7,9),(1,7.1)],"777065")
    return export()


def category_icon():
    poly,export=canvas()
    # Dark edge joins aircraft, hub, boom and skid into one clear silhouette.
    poly([(1,11),(2,8),(13,8),(13,5),(17,4),(21,5),(21,8),(30,8),
          (31,10),(31,12),(21,12),(21,15),(19,18),(20,20),(20,22),
          (25,23),(27,19),(29,19),(29,24),(27,27),(22,29),(10,29),
          (8,27),(8,24),(6,22),(4,20),(1,20),(1,16),(3,14),(8,15),
          (10,12),(3,12)],"243943")
    poly([(3,9),(15,9),(15,7),(17,6),(19,7),(19,9),(29,9),(29,11),
          (19,11),(18.5,14),(16,14),(15.5,11),(3,11)],"adbac0")
    poly([(2,16),(5,15),(6,17),(11,18),(12.4,15),(15.2,13.2),(19.9,13.2),
          (24.5,15.3),(27.3,18),(27.5,20.5),(25.6,22.5),(21.3,24),
          (14.3,24),(10.5,22.5),(8.8,21),(5,19),(2,19)],"d89a5d")
    poly([(12.1,17),(14,14.7),(17.2,14.6),(17.1,19.1),(12,19.1)],"6c8c95")
    poly([(18.5,14.4),(21,14.65),(24.4,16.2),(25.7,18.6),(18.5,18.6)],"517583")
    poly([(18.9,14.8),(21.1,15.15),(23.9,16.35),(24.55,17.05),(18.9,16.68)],"afc1bb")
    poly([(11.5,21.5),(25.7,21.5),(24,22.7),(21.2,23.4),(14,23.4)],"99643e")
    poly([(14,22.9),(15.7,22.9),(14.8,25.8),(21.1,25.8),(20.5,23.05),
          (22.1,22.75),(23.2,25.75),(25.55,25.55),(26.75,24.75),
          (27.65,25.35),(26.8,26.6),(24.8,27.25),(11.45,27.25),
          (11.45,25.75),(13,25.75)],"c1c4ad")
    poly([(2.05,16.45),(4.5,15.65),(5.3,17),(2.1,18)],"e4d5a7")
    return export()


def files(field,views):
    result={MOD/"models"/f"bl_{field.name}_{x}_{z}.obj":obj(a,field,x,z) for (x,z),a in views.items()}
    result[MOD/"textures"/f"bl_{field.name}_atlas.png"]=atlas()
    result[MOD/"textures"/f"bl_dispatch_{field.name}.png"]=icon(field)
    return result


def editable(field,views,preview):
    import bpy
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene["reference"]="OpenTTD 16.0-RC1; layout and stock FTA quarter coordinates, wholly original art"
    scene["datum"]="Grass y=-.5 at node ground+1. x,z = RC1 pixel/8-.5. Hangar opens towards +z."
    def material(name,color):
        m=bpy.data.materials.new(name)
        def conversion(x):return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
        m.diffuse_color=(*[conversion(c/255) for c in color],1)
        return m
    mats={n:material(n,rgb(n)) for n in COLORS}

    for (x,z),v in views.items():
        kind,edges=field.variant(x,z)
        collection=bpy.data.collections.new(f"{x} {z} {kind.capitalize()}")
        scene.collection.children.link(collection)
        for label,records in v.parts.items():
            faces,pts=[],[]
            for mat,coords in records:
                faces.append(tuple(range(len(pts),len(pts)+len(coords))))
                pts.extend((vx+2*x,-(vz+2*z),y) for vx,y,vz in coords)
            mesh=bpy.data.meshes.new(label)
            mesh.from_pydata(pts,[],faces)
            mesh.update()
            unique=list(dict.fromkeys(mat for mat,p in records))
            for mat in unique:mesh.materials.append(mats[mat])
            for polygon,(mat,_) in zip(mesh.polygons,records):
                polygon.material_index=unique.index(mat)
            collection.objects.link(bpy.data.objects.new(label,mesh))

    scene.render.engine="BLENDER_WORKBENCH"
    sh=scene.display.shading
    sh.color_type="MATERIAL"
    sh.light="STUDIO"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    sh.background_type="WORLD"
    sh.studiolight_rotate_z=.48
    scene.world=bpy.data.worlds.new("Slate")
    scene.world.color=(.058,.079,.087)
    width=field.width
    center=Vector((width-.5,-1.5,.0))
    bpy.ops.object.camera_add(location=center+Vector((7,-9,8)))
    cam=bpy.context.object
    cam.name="Review camera"
    cam.rotation_euler=(center-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=5.6 if width==2 else 8.75
    scene.camera=cam
    scene.render.resolution_x=660 if width==2 else 840
    scene.render.resolution_y=580
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.30
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=center
                view.region_3d.view_distance=cam.data.ortho_scale*1.2
                view.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/{field.name}.blend"),compress=True)
    if not preview:return
    scene.render.filepath=str(Path(preview)/f"luanttd-{field.name}.png")
    bpy.ops.render.render(write_still=True)
    # Review-only sizing rigs use real shipped body and main-rotor coordinates,
    # at their actual Luanti mesh scaling. Do not store them in master art.
    def aircraft(x,z,yaw,stem):
        def read_native(suffix,dy):
            points,faces=[],[]
            u=cos(yaw);v=sin(yaw)
            data=(MOD/"models"/f"bl_stock_{stem}{suffix}.obj").read_text().splitlines()
            for line in data:
                if line.startswith("v "):
                    i,j,k=map(float,line.split()[1:]);i=-i*.1;k*=.1
                    points.append((x+u*i-v*k,-(z+v*i+u*k),DATUM+j*.1+dy+.014))
                elif line.startswith("f "):
                    faces.append(tuple(reversed([int(t.split("/")[0])-1 for t in line.split()[1:]])))
            m=bpy.data.meshes.new("Swept vehicle view")
            m.from_pydata(points,[],faces);m.update();m.materials.append(mats["Parking cream light"] if not suffix else mats["Steel roof graphite"])
            scene.collection.objects.link(bpy.data.objects.new("Preview only rotorcraft",m))
        read_native("",0)
        read_native("_rotor",.407 if stem=="tricario_heli" else .515)

    for p in field.park_px:
        x,z=px_to_native(p)
        aircraft(x,z,.35,"tricario_heli")
    # Independent well-lit portal view helps spot floors blocking the mouth.
    x,z=px_to_native(field.depot_px)
    aircraft(x,z+.775,0,"tricario_heli")
    scene.render.filepath=str(Path(preview)/f"luanttd-{field.name}-clearance.png")
    bpy.ops.render.render(write_still=True)


def main():
    p=ArgumentParser()
    p.add_argument("--check",action="store_true")
    p.add_argument("--blend",action="store_true")
    p.add_argument("--preview",help="directory for both design renders")
    p.add_argument("--only",choices=[a.name for a in FIELDS])
    flags=p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else (sys.argv[1:] if "bpy" not in sys.modules else []))
    if not flags.only:
        category=MOD/"textures/bl_dispatch_rotary_airfields.png"
        payload=category_icon()
        if flags.check:assert category.read_bytes()==payload,category
        elif not category.exists() or category.read_bytes()!=payload:category.write_bytes(payload)
    for field in FIELDS:
        if flags.only and flags.only!=field.name:continue
        views=make(field)
        for path,body in files(field,views).items():
            if flags.check:assert path.read_bytes()==body,path
            elif not path.exists() or path.read_bytes()!=body:path.write_bytes(body)
        if flags.blend:editable(field,views,flags.preview)


if __name__=="__main__":
    main()
