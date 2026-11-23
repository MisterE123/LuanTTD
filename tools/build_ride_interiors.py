#!/usr/bin/env python3
"""Rebuild original LuanTTD transit interiors. Python stdlib only.

Luanti local coordinates in node units: +X right, +Y up, +Z vehicle forward.
Anchor is exterior body center at seat-floor height, not the viewer's eye.
Atlas pixels and geometry are authored here and exported as editable OBJ.
"""
from math import cos, sin, pi, sqrt
from pathlib import Path
import struct
import zlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"mods"/"luanttd_core"
SW=40
COL=8
COMMON={
    "rim":("252c2b","fine"), "metal":("788280","brush"), "rubber":("282d2c","dots"),
    "steel":("424f50","brush"), "glassline":("dce5d1","brush"), "brass":("af8e4d","brush"),
    "paper":("c5baa1","fine"), "ink":("303638","flat"), "white":("e7e4d7","fine"),
    "lit":("fbefbe","flat"), "red":("8a3b39","fine"), "shadow":("302a27","fine"),
}
PAINT={
    "bus":dict(shell=("687c72","brush"), edge=("52625b","brush"), lower=("32554e","brush"),
        upper=("c6b895","fine"), ceiling=("dbd3b8","fine"), floor=("66645a","stone"),
        aisle=("514f49","dots"), seat=("874943","leather"), seam=("b58469","fine"),
        seatback=("663a37","leather"), door=("74664e","wood"), padding=("b5a17d","fine"),
        black=("414238","brush"), gasket=("343841","fine")),
    "coach":dict(shell=("4a6560","brush"), edge=("2e5557","brush"), lower=("71533e","wood"),
        upper=("c9b789","fine"), ceiling=("dbcdab","fine"), floor=("66513b","wood"),
        aisle=("537279","carpet"), seat=("59778c","carpet"), seam=("9aa9a7","fine"),
        seatback=("354854","carpet"), door=("846448","wood"), padding=("aaa08c","fine"),
        black=("323938","brush"), gasket=("2e4343","fine")),
    "cab":dict(shell=("42534e","brush"), edge=("333e39","brush"), lower=("354d3d","brush"),
        upper=("9b946c","fine"), ceiling=("6d7569","brush"), floor=("423d36","wood"),
        aisle=("4d5351","dots"), seat=("845b3d","leather"), seatback=("593f34","leather"),
        seam=("b1935f","fine"), door=("635f4c","wood"), padding=("a79772","fine"),
        black=("292f30","brush"), gasket=("24292a","fine"), fire=("734134","brush"),
        copper=("a96d49","brush"), needle=("cf503a","flat"), dial=("e1d9b3","fine")),
}
EYES={"bus":(-.020,.117,-.042), "coach":(-.091,.207,-.080), "cab":(.075,.228,-.228)}
FLOORS={"bus":.071,"coach":.202,"cab":.247}
# Only the riding client sees the cabin. Expand around the fixed eye, not the
# vehicle so projected positions stay the same while nearby details clear the
# Luanti camera's near plane. These shells never supply collision or world art.
CLIP_CLEARANCE={"bus":1.58,"coach":1.29,"cab":1.42}


def ident(v):
    return tuple(round(x,6) for x in v)


def sub(a,b):
    return tuple(x-y for x,y in zip(a,b))


def cross(a,b):
    return a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def normal(points):
    v=cross(sub(points[1],points[0]),sub(points[2],points[0]))
    m=sqrt(dot(v,v))
    return None if m<1e-12 else tuple(x/m for x in v)


def pixel(swatch,x,y,seed):
    base,kind=swatch
    rgb=bytes.fromhex(base)
    h=(((x+13)*19349663)^((y+9)*83692757)^(seed*12151543))%37
    if kind=="wood":
        texture=(2 if y%8==0 else 0)+4*sin(y*.68+cos(x*.24))+3*sin(y*2.58+x*.08)+(h%5-2)
    elif kind=="leather":
        texture=(h%9-4)+((x+y)%6==0)*3
    elif kind=="carpet":
        texture=(h%9-4)+((x+2*y)%4==0)*6
    elif kind=="dots":
        texture=(h%4-2)+(9 if x%7 in (0,1) and y%7 in (0,1) else 0)
    elif kind=="brush":
        texture=(y%8-4)*.7+(h%5-2)*.6
    elif kind=="stone":
        texture=h%12-6
    elif kind=="flat":
        texture=0
    else:
        texture=h%7-3
    return bytes(int(max(0,min(255,c+texture))) for c in rgb)


class Mesh:
    def __init__(self, kind):
        self.kind=kind
        self.materials=COMMON|PAINT[kind]
        self.names=list(self.materials)
        self.faces=[]

    def face(self,group,paint,points,expected=None):
        points=list(map(ident,points))
        n=normal(points)
        if n is None:return
        if expected and dot(n,expected)<0:
            points.reverse()
        self.faces.append((group,paint,points))

    def box(self,group,c,x0,x1,y0,y1,z0,z1,top=None):
        if not (x1-x0>1e-6 and y1-y0>1e-6 and z1-z0>1e-6):return
        for pts,n in (
            (((x0,y0,z0),(x0,y1,z0),(x0,y1,z1),(x0,y0,z1)),(-1,0,0)),
            (((x1,y0,z0),(x1,y1,z0),(x1,y1,z1),(x1,y0,z1)),(1,0,0)),
            (((x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)),(0,-1,0)),
            (((x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)),(0,1,0)),
            (((x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0)),(0,0,-1)),
            (((x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)),(0,0,1)),
        ):
            self.face(group,(top or c) if n[1]==1 else c,pts,n)

    def place(self,group,c,x,y,z,w,h,l,top=None):
        self.box(group,c,x-w/2,x+w/2,y-h/2,y+h/2,z-l/2,z+l/2,top)

    def padded(self,group,c,x,y,z,w,h,l,bevel,top=None):
        # Rounded corners illustrated by actual chamfer facets, not decals.
        xx,zz=w/2,l/2
        b=min(bevel,xx*.8,zz*.8)
        coords=((-xx+b,-zz),(xx-b,-zz),(xx,-zz+b),(xx,zz-b),
            (xx-b,zz),(-xx+b,zz),(-xx,zz-b),(-xx,-zz+b))
        for k,(u,v) in enumerate(coords):
            a,d=coords[(k+1)%len(coords)]
            self.face(group,c,((x+u,y-h/2,z+v),(x+a,y-h/2,z+d),
              (x+a,y+h/2,z+d),(x+u,y+h/2,z+v)),(u+a,0,v+d))
        for side in (-1,1):
            self.face(group,top or c,[(x+u,y+side*h/2,z+v) for u,v in coords],(0,side,0))

    def tube(self,group,c,a,b,r,segments=10,hollow=0):
        ab=sub(b,a); length=sqrt(dot(ab,ab)); axis=[x/length for x in ab]
        ref=(0,0,1) if abs(axis[2])<.8 else (0,1,0)
        u=cross(axis,ref); d=sqrt(dot(u,u)); u=[x/d for x in u]
        v=cross(axis,u)
        def ring(p,radius):
            return [tuple(p[k]+radius*(cos(i*2*pi/segments)*u[k]+sin(i*2*pi/segments)*v[k])
                          for k in range(3)) for i in range(segments)]
        at,bt=ring(a,r),ring(b,r)
        ai,bi=(ring(a,hollow),ring(b,hollow)) if hollow else (None,None)
        for i in range(segments):
            j=(i+1)%segments
            self.face(group,c,(at[i],at[j],bt[j],bt[i]),sub(at[i],a))
            if hollow:
                self.face(group,c,(ai[i],bi[i],bi[j],ai[j]),sub(a,ai[i]))
                self.face(group,c,(at[i],at[j],ai[j],ai[i]),[-x for x in axis])
                self.face(group,c,(bt[i],bi[i],bi[j],bt[j]),axis)
        if not hollow:
            self.face(group,c,at,[-x for x in axis]);self.face(group,c,bt,axis)

    def export(self,base):
        rows=(len(self.names)+COL-1)//COL
        W,H=COL*SW,rows*SW
        vt=[]
        for i in range(len(self.names)):
            x=i%COL*SW;y=i//COL*SW
            vt.extend(((x+2,y+2),(x+SW-2,y+2),(x+SW-2,y+SW-2),(x+2,y+SW-2), (x+SW/2,y+SW/2)))
        positions,indices,normals,directions,groups=[],{},{},{},{}
        for group,c,poly in self.faces:
            # Undo Luanti's OBJ X reflection; the mirrored file is still
            # right-handed for Blender and all OBJ viewers.
            eye,scale=EYES[self.kind],CLIP_CLEARANCE[self.kind]
            enlarged=[tuple(e+(v-e)*scale for e,v in zip(eye,p)) for p in poly[::-1]]
            ps=[ident((-x*10,y*10,z*10)) for x,y,z in enlarged]
            n=ident(normal(ps))
            ni=directions.get(n)
            if ni is None: ni=directions[n]=len(directions)+1
            uv0=self.names.index(c)*5+1
            uv=[0,1,2,3] if len(ps)==4 else [4]*len(ps)
            refs=[]
            for q,t in zip(ps,uv):
                vi=indices.get(q)
                if vi is None:
                    positions.append(q);vi=indices[q]=len(positions)
                refs.append(f"{vi}/{uv0+t}/{ni}")
            groups.setdefault(group,[]).append(refs)
        body=["# LuanTTD originally authored transit cabin. See tools/build_ride_interiors.py."]
        body += ["v %.6f %.6f %.6f"%p for p in positions]
        body += ["vt %.6f %.6f"%(x/W,1-y/H) for x,y in vt]
        body += ["vn %.6f %.6f %.6f"%n for n in directions]
        for group,faces in groups.items():
            body.append("o "+group.replace(" ","_"))
            for f in faces:
                for i in range(1,len(f)-1): body.append("f "+' '.join((f[0],f[i],f[i+1])))
        (OUT/"models"/(base+".obj")).write_text("\n".join(body)+"\n")
        rgba=bytearray()
        paints=list(self.materials.values())
        for y in range(H):
            rgba.append(0)
            for x in range(W):
                k=(y//SW)*COL+x//SW
                rgba.extend(pixel(paints[min(k,len(paints)-1)],x%SW,y%SW,k))
        def chunk(kind,data):
            return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
        img=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",W,H,8,2,0,0,0))
        img+=chunk(b"IDAT",zlib.compress(rgba,9))+chunk(b"IEND",b"")
        (OUT/"textures"/(base+".png")).write_bytes(img)
        print(f"{base}: {len(positions)} vertices, {sum(len(f)-2 for _,_,f in self.faces)} triangles")


def crosswall(m,z,x,lo,win_bottom,win_top,roof,opening,depth=.007):
    name="End bulkhead and window reveals"
    m.box(name,"lower",-x,x,lo,win_bottom,z-depth/2,z+depth/2)
    m.box(name,"upper",-x,x,win_top,roof,z-depth/2,z+depth/2)
    start=-x
    for a,b in opening:
        m.box(name,"upper",start,a,win_bottom,win_top,z-depth/2,z+depth/2)
        # Contrast seals and small ledges end at the air aperture.
        for y in (win_bottom-.002,win_top+.002):
            m.box("End window rubber surrounds","gasket",a,b,y-.0017,y+.0017,z-depth*.9,z+depth*.9)
        for xx in (a,b):
            m.place("End window gasket uprights","gasket",xx,(win_bottom+win_top)/2,z,.0035,win_top-win_bottom,depth*1.8)
        start=b
    m.box(name,"upper",start,x,win_bottom,win_top,z-depth/2,z+depth/2)


def sides(m,x,z0,z1,low,hi,roof,windows,depth):
    # The horizontal facade is tessellated around openings rather than
    # cutting transparent paint out of one flat wall. No window polygons.
    for sign in (-1,1):
        a,b=sign*x-depth/2,sign*x+depth/2
        m.box("Lower interior wainscot","lower",a,b,0,low,z0,z1)
        m.box("Upper interior liner","upper",a,b,hi,roof,z0,z1)
        start=z0
        for u,v in windows:
            m.box("Between-window intermediate posts","upper",a,b,low,hi,start,u)
            for z in (u,v):
                m.place("Window pillar seals","gasket",sign*x,(low+hi)/2,z,depth*1.55,hi-low,.003)
            z=(u+v)/2
            m.place("Window seals above","gasket",sign*x,hi,z,depth*1.55,.004,v-u)
            m.place("Solid window sill ledges","padding",sign*x,low-.001,z,depth*3.0,.004,v-u)
            start=v
        m.box("Window end pillars","upper",a,b,low,hi,start,z1)
        m.place("Longitudinal bright trim","brass",sign*x,low*.87,(z0+z1)/2,depth*1.65,.003,z1-z0)


def roof(m,l,r,z0,z1,center_y,edge_y):
    profile=[(l,edge_y),(l*.79,edge_y+.44*(center_y-edge_y)),(l*.48,edge_y+.82*(center_y-edge_y)),
        (0,center_y),(r*.48,edge_y+.82*(center_y-edge_y)),(r*.79,edge_y+.44*(center_y-edge_y)),(r,edge_y)]
    for (a,b),(x,y) in zip(profile,profile[1:]):
        for dz,dcol,dnormal in ((0,"ceiling",(0,-1,0)),(.004,"shell",(0,1,0))):
            m.face("Curved ceiling panels",dcol,((a,b+dz,z0),(x,y+dz,z0),(x,y+dz,z1),(a,b+dz,z1)),dnormal)
    # Close the curved header above the end windows as a real panel. Both
    # faces are visible from an eye-level camera and in Blender inspection.
    for z,sign in ((z0,-1),(z1,1)):
        for (a,b),(x,y) in zip(profile,profile[1:]):
            for inset,normal_z in ((0,sign),(-.004*sign,-sign)):
                zz=z+inset
                m.face("Fascia crown","upper",((a,edge_y,zz),(a,b+.004,zz),(x,y+.004,zz)),(0,0,normal_z))
                m.face("Fascia crown","upper",((a,edge_y,zz),(x,y+.004,zz),(x,edge_y,zz)),(0,0,normal_z))



def seats(m,x,z,seat_w,seat_y,back_y,depth,coach=False):
    frame=.0045 if not coach else .007
    skin=depth*.16
    m.padded("Cushioned seat pan","seat",x,seat_y,z,seat_w,frame*2,depth,frame*1.4)
    m.padded("Seats upholstered upright","seatback",x,back_y,z-depth*.39,seat_w,2*(back_y-seat_y),skin,frame)
    m.padded("Face cushion panel","seat",x,back_y+.002,z-depth*.30,seat_w*.87,(back_y-seat_y)*1.52,
        skin*.59,frame*.68)
    m.place("Contrast piping on seat backs","seam",x,2*back_y-seat_y-.002,z-depth*.40,
        seat_w*.93,frame*.62,skin*.32)
    for side in (-1,1):
        xx=x+side*seat_w*.36
        m.place("Steel leg frames","steel",xx,seat_y*.40,z,frame,seat_y*.9,frame*1.22)
        m.place("Seat arm rest","door",x+side*seat_w*.54,seat_y*1.52,z+depth*.05,
            frame*.95,frame*1.25,depth*.72)
    m.place("Seat back grab rails","metal",x,2*back_y-seat_y+.001,z-depth*.44,seat_w*.70,frame*.6,frame*.7)


def bus():
    m=Mesh("bus");x=.130;z=.329
    m.box("Rubber bus floor","floor",-x,x,-.008,0,-z,z)
    m.place("Non-slip aisle","aisle",0,.0007,-.02,.049,.0014,.61)
    for xx in (-.027,.027):
        m.place("Metal aisle border","metal",xx,.0018,-.024,.002,.002,.593)
    sides(m,x,-z,z,.077,.167,.185,
        [(-.305,-.204),(-.187,-.075),(-.058,.059),(.076,.188),(.207,.308)],.006)
    roof(m,-x,x,-z,z,.201,.183)
    crosswall(m,z-.005,x,0,.084,.164,.183,[(-.112,-.009),(.009,.111)])
    crosswall(m,-z+.005,x,0,.088,.164,.183,[(-.112,.112)])
    for i,p in enumerate((-.261,-.111,.048,.171)):
        for xx in (-.079,.079):
            if xx>0 and i==3:continue  # clear front entry well
            seats(m,xx,p,.065,.042,.082,.064)
    m.padded("Driver small dashboard","black",- .060,.097,.284,.115,.022,.067,.008,top="edge")
    m.tube("Steering wheel rim","rim",(-.068,.131,.251),(-.068,.134,.258),.021,16,.016)
    m.tube("Steering column","steel",(-.068,.092,.268),(-.068,.131,.254),.004)
    m.place("Round instrument cluster frame","brass",-.077,.113,.277,.033,.006,.013)
    for xx in (-.018,.014):
        m.tube("Overhead pull rails","brass",(xx,.172,-.274),(xx,.172,.259),.0021,8)
        for zz in (-.220,-.063,.096,.247):
            m.tube("Ceiling rail hanger","metal",(xx,.174,zz),(xx,.192,zz),.002,7)
    for xx in (-.065,.065):
        m.place("Long ceiling diffusers","white",xx,.183,-.013,.017,.007,.307)
    for zz in (.213,.304):
        m.tube("Front doorway poles","brass",(.097,.010,zz),(.097,.171,zz),.0024,8)
    m.padded("Front passenger step","black",.089,.021,.254,.075,.016,.084,.008,"floor")
    m.place("Ticket console and coin tray","black",.028,.081,.254,.026,.069,.031,"metal")
    return m


def coach():
    m=Mesh("coach");x=.218;z=.422
    m.box("Coach oak subfloor","floor",-x,x,-.012,0,-z,z)
    m.place("Woven center aisle runner","aisle",0,.001,.0,.100,.002,.798)
    for xx in (-.050,.050):
        m.place("Runner brass binding","brass",xx,.003,0,.004,.004,.794)
    sides(m,x,-z,z,.164,.313,.352,
        [(-.393,-.311),(-.287,-.190),(-.167,-.060),(-.039,.069),(.090,.193),(.216,.303),(.324,.392)],.009)
    roof(m,-x,x,-z,z,.384,.349)
    for zz in (-z+.005,z-.005):
        crosswall(m,zz,x,0,.148,.321,.35,[(-.103,.103)])
        # Narrow end vestibules have real open glazing and strapped side panels.
        for xx in (-.140,.140):
            m.place("Varnished vestibule door slab","door",xx,.111,zz,.065,.205,.013)
            m.place("Pressed leather door inset","seatback",xx,.114,zz+( -.008 if zz>0 else .008),.052,.106,.004)
            m.place("Vestibule brass door hardware","brass",xx+(-.034 if xx>0 else .034),.199,zz,.012,.036,.021)
    for zz in (-.325,-.181,-.024,.129,.277):
        for xx in (-.135,.135):
            seats(m,xx,zz,.119,.066,.117,.100,True)
    for sgn in (-1,1):
        for xx in (.156,.187,.208):
            m.tube("Brass luggage rack longitudinal rods","brass",(sgn*xx,.331,-.36),(sgn*xx,.331,.36),.0025,8)
        for zz in (-.343,-.244,-.146,-.047,.047,.146,.244,.343):
            m.tube("Luggage rack rods and mounting","metal",(sgn*.145,.331,zz),(sgn*.215,.331,zz),.0026,8)
        for zz in (-.309,-.103,.103,.309):
            m.place("Warm coach ceiling fixtures","lit",sgn*.065,.371,zz,.030,.006,.045)
    return m


def cab():
    m=Mesh("cab");x=.190;rear=-.365;front=-.108
    m.box("Locomotive steel pin floor","floor",-x,x,-.012,0,rear,front)
    m.place("Checkerplate tread","aisle",0,.0007,(front+rear)/2,.264,.0014,.222)
    sides(m,x,rear,front,.139,.310,.348,[(rear+.014,-.251),(-.237,front-.018)],.008)
    roof(m,-x,x,rear,front,.356,.345)
    crosswall(m,front,x,0,.167,.319,.346,[(-.162,-.025),(.024,.162)])
    crosswall(m,rear,x,0,.156,.314,.347,[(-.163,-.018),(.018,.163)])
    m.tube("Black riveted boiler beyond the spectacles","black",(0,.130,front+.006),(0,.130,.340),.098,18)
    for z in (-.073,.050,.172,.289):
        m.tube("Boiler bands and joints","metal",(0,.130,z-.0023),(0,.130,z+.0023),.099,18)
    m.tube("Short exhaust chimney silhouette","black",(0,.207,.281),(0,.317,.281),.020,12)
    m.tube("Chimney upper edge","steel",(0,.305,.281),(0,.318,.281),.023,12)
    for xx in (-.099,.099):
        m.tube("External longitudinal grip rails","steel",(xx,.157,-.069),(xx,.157,.309),.0024,8)
    m.padded("Backhead at the firebox","black",-.022,.081,-.118,.148,.150,.042,.013)
    m.tube("Circular firebox inspection door","fire",(-.019,.073,-.148),(-.019,.073,-.151),.033,16)
    m.place("Iron firebox latch","metal",.004,.076,-.153,.027,.006,.008)
    m.place("Control shelf below forward windows","door",.065,.141,-.122,.233,.017,.031,"metal")
    for xx in (-.138,-.083,-.022):
        m.tube("Brass pressure gauge surrounds","brass",(xx,.161,-.129),(xx,.161,-.138),.019,16)
        m.tube("Ivory gauge faces","dial",(xx,.161,-.138),(xx,.161,-.140),.015,16)
        m.place("Contrast gauge needles","needle",xx-.002,.163,-.142,.003,.022,.003)
        m.tube("Curved copper feed risers","copper",(xx,.044,-.139),(xx,.142,-.139),.0034,10)
        m.tube("Copper feed elbows","copper",(xx,.045,-.140),(xx,.045,-.123),.0034,10)
    m.tube("Brake wheel brass hub","brass",(.129,.119,-.144),(.129,.119,-.171),.013,12)
    m.tube("Brake wheel black rim","black",(.129,.119,-.172),(.129,.119,-.179),.029,18,.024)
    for angle in (0,pi/3,-pi/3):
        u=.023*cos(angle);v=.023*sin(angle)
        m.tube("Brake wheel spokes","steel",(.129-u,.119-v,-.175),(.129+u,.119+v,-.175),.002,8)
    m.tube("Red throttle lever","steel",(.093,.085,-.138),(.087,.149,-.171),.0046,9)
    m.tube("Throttle wooden grip","seat",(.074,.149,-.171),(.103,.149,-.171),.007,10)
    m.padded("Engineer spring stool","seat",.075,.105,-.288,.080,.016,.068,.009)
    m.tube("Engineer seat pedestal","steel",(.075,.013,-.288),(.075,.097,-.288),.013,12)
    for xx in (-.135,.135):
        m.tube("Cab entry handrails","brass",(xx,.092,rear+.01),(xx,.279,rear+.01),.0032,8)
    m.place("Cab ceiling warm glow housing","lit",0,.345,-.234,.051,.009,.044)
    return m


if __name__=="__main__":
    for name,build in (("bl_ride_bus_interior",bus),("bl_ride_train_interior",coach),("bl_ride_train_cab",cab)):
        build().export(name)
