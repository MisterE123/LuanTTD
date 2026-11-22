"""Generate editable Bayline scenery and native-size OBJ meshes in Blender.

Run: blender -b -t 2 --python-exit-code 1 --python tools/build_scenery_art.py
Optional BAYLINE_SCENERY_REVIEW=/tmp/path creates an orthographic review scene.
All geometry and swatches are authored here; no third-party sprites are used.
"""
from math import cos, sin, pi, sqrt
import os
from pathlib import Path
from random import Random
import struct
import zlib

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SWATCH = {
    "brick": "a05b4c", "brick bright": "bf7560", "terracotta": "a85946",
    "terracotta bright": "ba725a", "slate": "405564", "slate bright": "566e7e",
    "shingle": "655550", "shingle bright": "80685c", "plaster": "e8d8bd",
    "warm limestone": "c2aa91", "stone": "9f9e90", "pale stone": "c6c2af",
    "blue board": "859fab", "cream board": "e7cf9b", "cream": "f0e2c1",
    "burgundy": "894c45", "cedar": "79553c", "trail": "ab926e",
    "sapwood": "a17e53", "dark metal": "354d4a", "teal": "49746b",
    "glazing": "2a4857", "reflection": "5b8090", "white": "f5e6cb",
    "black": "302c31", "coal": "494854", "rust": "89513c", "metal": "7b8587",
    "light metal": "a5aeab", "gold": "c4a257", "wheat": "be9b47",
    "straw": "d9b960", "soil": "836144", "soil shade": "694d3b",
    "sage": "788153", "hedge": "425c38", "mint": "628249",
    "foliage dark": "355641", "foliage": "4d7346", "foliage sun": "729953",
    "pine dark": "375d52", "pine": "487366", "pine sun": "628771",
    "flower": "baa353", "water": "638c94",
}
MATS = {}
COLORS = list(SWATCH)
def srgb(hexcode):
    ch = [int(hexcode[i:i+2], 16)/255 for i in (0,2,4)]
    return [c/12.92 if c<.04045 else ((c+.055)/1.055)**2.4 for c in ch]

def init():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.view_settings.view_transform = "Standard"
    MATS.clear()
    for name, color in SWATCH.items():
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*srgb(color), 1)
        MATS[name] = m

def mesh(name, vertices, faces, colors):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    out = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(out)
    if isinstance(colors, str):
        data.materials.append(MATS[colors])
    else:
        names = list(dict.fromkeys(colors))
        for color in names:
            data.materials.append(MATS[color])
        for poly, color in zip(data.polygons, colors):
            poly.material_index = names.index(color)
    return out

def box(name, xyz, dims, color):
    x,y,z = xyz
    w,d,h = (k*.5 for k in dims)
    verts = [(x+i*w,y+j*d,z+k*h) for i,j,k in
             ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    return mesh(name, verts, ((3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)), color)

def beam(name, start, end, width, depth, color):
    a,b = Vector(start),Vector(end)
    cent = (a+b)*.5
    o = box(name, (0,0,0), (width, depth, (b-a).length), color)
    o.location = cent
    o.rotation_euler = (b-a).to_track_quat('Z','Y').to_euler()
    return o

def tapered(name, start, end, r1, r2, sides, color, rng=None):
    a,b = Vector(start),Vector(end)
    q = (b-a).to_track_quat('Z','Y')
    radii = [rng.uniform(.9,1.1) for _ in range(sides)] if rng else [1]*sides
    verts = []
    for k,r in ((a,r1),(b,r2)):
        for j in range(sides):
            t=j*2*pi/sides
            verts.append(k+q @ Vector((cos(t)*r*radii[j],sin(t)*r*radii[j],0)))
    faces = [tuple(reversed(range(sides))),tuple(range(sides,2*sides))]
    return mesh(name, verts, faces+[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)], color)

def gable(name, x,y,w,d,eave,peak,wall,roof,trim,ribs=5):
    """Gable fronts local +/-Y; courses and fascia are physical roof details."""
    a,b = w/2,d/2
    for q in (-1,1):
        verts=[(x-a,y+q*b,eave),(x+a,y+q*b,eave),(x,y+q*b,peak)]
        mesh(name+" gable end",verts,((0,1,2),) if q==-1 else ((0,2,1),),wall)
    a+=.044
    b+=.052
    for i in (-1,1):
        verts=[(x,y-b,peak+.027),(x+i*a,y-b,eave),(x+i*a,y+b,eave),(x,y+b,peak+.027)]
        mesh(name+" roof slope",verts,((0,1,2,3),) if i==1 else ((3,2,1,0),),roof)
        for q in (-1,1):
            beam(name+" rake", (x,y+q*b,peak+.016),(x+i*a,y+q*b,eave-.005), .024,.025,trim)
        box(name+" eave", (x+i*a,y,eave-.013), (.027,b*2,.036),trim)
        for j in range(1,ribs+1):
            f=j/(ribs+1)
            box(name+" roof course", (x+i*a*f,y,(1-f)*(peak+.027)+f*eave+.002),
                (.02,b*2,.006),roof+" bright")
    box(name+" ridge cap",(x,y,peak+.028),(.052,b*2,.025),roof+" bright")

def hip(name,x,y,w,d,eave,peak,roof):
    a,b=w*.5+.05,d*.5+.05
    z=peak+.005
    verts=[(x-a,y-b,eave),(x+a,y-b,eave),(x+a,y+b,eave),(x-a,y+b,eave),
           (x,y-b*.51,z),(x,y+b*.51,z)]
    mesh(name,verts,((0,1,4),(1,2,5,4),(2,3,5),(3,0,4,5)),(roof+" bright",roof,roof+" bright",roof))
    box(name+" ridge",(x,y,z+.011),(.056,b*1.07,.026),roof+" bright")
    for s in (-1,1):
        box(name+" eave",(x+s*a,y,eave),(.021,b*2,.033),"cream")
        box(name+" eave",(x,y+s*b,eave),(a*2,.021,.033),"cream")
        for off in (-1,1):
            beam(name+" hip flashing",(x,y+off*b*.51,z),(x+s*a,y+off*b,eave),.02,.02,roof+" bright")

def pane(name, x,y,z,w,h,q="front",f="cream", shutters=False, divisions=2):
    # Face lies on y for front/back, x for left/right. Inner dimensions are visible glazing.
    direction = -1 if q in ("front","left") else 1
    def part(desc,u,v,n,du,dv,dn,color):
        if q in ("front","back"):
            return box(name+" "+desc,(x+u,y+direction*n,z+v),(du,dn,dv),color)
        return box(name+" "+desc,(x+direction*n,y+u,z+v),(dn,du,dv),color)
    part("frame",0,0,.008,w+.023,h+.024,.018,f)
    part("recess",0,0,.020,w,h,.015,"glazing")
    part("sky reflection",0,h*.31,.028,w-.014,h*.22,.005,"reflection")
    for d in range(1,divisions):
        part("mullion",(d/divisions-.5)*w,0,.030,.009,h,.008,f)
    part("meeting rail",0,-h*.1,.031,w,.008,.008,f)
    part("stone sill",0,-h*.56,.021,w+.047,.026,.047,"pale stone")
    if shutters:
        for s in (-1,1):
            part("louver shutter",s*(w*.5+.043),0,.010,.056,h+.02,.019,"teal")
            for j in (-2,-1,0,1,2):
                part("shutter slat",s*(w*.5+.043),j*h*.14,.024,.050,.006,.004,"dark metal")

def frontdoor(x,y,h, color, floor=.05):
    box("Stone threshold", (x,y-.038,floor),(.263,.215,.036),"pale stone")
    box("Door case",(x,y-.009,h*.5+floor),(.215,.03,h+.026),"cream")
    box("Paneled door",(x,y-.029,h*.5+floor),(.179,.025,h),"teal" if color=="plaster" else "cedar")
    box("Door glass",(x,y-.044,h*.69+floor),(.112,.014,h*.23),"glazing")
    box("Door transom",(x,y-.050,h*.69+floor),(.008,.013,h*.23),"cream")
    box("Brass knob",(x+.06,y-.048,h*.45+floor),(.017,.017,.018),"gold")

def chimney(x,y,z, h=.29, c="brick"):
    box("Masonry chimney",(x,y,z+h*.5),(.155,.165,h),c)
    for j in (1,2,3):
        box("Chimney mortar",(x,y,z+j*h/4),(.161,.170,.008),"brick bright")
    box("Projecting chimney cap",(x,y,z+h+.018),(.205,.215,.039),"stone")
    for n in (-1,1):
        tapered("Clay chimney pot",(x+n*.043,y,z+h+.038),(x+n*.043,y,z+h+.11),.030,.024,8,"terracotta")

def path(name,x,y,w,d):
    box(name,(x,y,.012),(w,d,.024),"trail")
    for j in range(3):
        box(name+" paver",(x,y+(j-1)*d*.27,.029),(w*.83,d*.22,.012),"pale stone")

def bulbs(x,y,rng):
    for n in range(4):
        angle=n*pi*.5+.31
        a,b=x+cos(angle)*.09,y+sin(angle)*.063
        tapered("Flower stalk",(a,b,.02),(a,b,.084),.014,.008,5,"hedge")
        tapered("Calendula",(a,b,.079),(a,b,.100),.029,.023,6,"flower")

def house(style):
    # Four distinct early-to-mid-century vernacular forms, not just paint variants.
    w,d,h,c,r = (
        (1.04,.87,.57,"plaster","terracotta"),
        (1.14,1.13,.86,"brick","slate"),
        (1.22,.83,.52,"blue board","shingle"),
        (1.00,.95,.65,"cream board","terracotta"),
    )[style]
    y=.084
    f=y-d/2
    box("Stone footing",(0,y,.042),(w+.046,d+.026,.084),"warm limestone")
    box("House structure",(0,y,h/2+.049),(w,d,h),c)
    peak=h+.32 if style!=1 else h+.34
    if style==1:
        hip("Hipped slate roof",0,y,w,d,h+.05,peak,r)
    else:
        gable("Main roof",0,y,w,d,h+.05,peak,c,r,"cream")
    chimney(.30,y+.13,peak-.19,.32)
    if style in (2,3):
        for j in range(1,int(h/.093)+1):
            box("Clapboard lower edge",(0,f-.002,.08+j*.087),(w,.012,.009),"reflection" if style==2 else "warm limestone")
    if style in (0,3):
        pane("Gable attic light",0,f,peak-.12,.09,.10,divisions=1)
    frontdoor(.23 if style in (0,2) else 0,f,.335,c)
    for i in (-1,1) if style in (1,3) else (-1,):
        pane("Front sash",i*.31,f,.30,.211 if style!=2 else .40,.21,shutters=style in (0,2))
    if style==1:
        for i in (-1,0,1):
            pane("Upper sash",i*.34,f,.641,.179,.22)
        box("Painted lintel",(0,f-.022,.802),(w+.025,.046,.045),"pale stone")
    for i in (-1,1):
        for delta in (-.20,.19):
            pane("Side sash",i*w/2,y+delta,.31,.162,.20,"left" if i<0 else "right")
            if style==1:
                pane("Upper side sash",i*w/2,y+delta,.645,.158,.20,"left" if i<0 else "right")
        pane("Rear sash",i*.245,y+d*.5,.35,.176,.20,"back")
    if style==3:
        box("Veranda deck", (0,f-.13,.085),(w+.08,.36,.08),"cedar")
        for i in (-1,1):
            box("Turned veranda post",(i*.438,f-.265,.30),(.049,.052,.44),"cream")
            box("Veranda foot",(i*.438,f-.265,.112),(.075,.077,.066),"cream")
        o=box("Veranda awning",(0,f-.16,.506),(w+.13,.38,.051),"terracotta")
        o.rotation_euler.x=.125
    if style==2:
        box("Side pantry",(.705,y+.16,.215),(.28,.44,.38),"blue board")
        box("Pantry roof",(.705,y+.16,.43),(.36,.50,.063),"shingle")
        pane("Pantry window",.845,y+.16,.23,.139,.13,"right")
    path("Front walk",.23 if style in (0,2) else 0,-.70,.244,.43)
    for i in (-1,1):
        box("Flowerbed earth",(i*.63,-.63,.017),(.30,.17,.035),"soil")
        bulbs(i*.63,-.63,Random(style))
    if style in (0,2):
        for i in range(5):
            box("Picket",(-.82+i*.126,-.83,.10),(.04,.034,.19),"cream")
        box("Picket rail",(-.57,-.813,.105),(.56,.025,.034),"cream")

def town():
    # A municipal hall & civic square with tall readable clock tower.
    w,d,y,h=1.48,1.10,.18,.88
    f=y-d/2
    box("Granite hall base",(0,y,.049),(w+.08,d+.064,.098),"stone")
    box("Brick hall",(0,y,h/2+.06),(w,d,h),"brick")
    hip("Slate hall roof",0,y,w,d,.95,1.28,"slate")
    for z in (.16,.93):
        box("String course",(0,y,z),(w+.041,d+.042,.038),"pale stone")
    for side in (-1,1):
        for i in (.26,.53):
            pane("Tall municipal window",i*side,f,.46,.166,.43,divisions=2)
        for p in (-.29,.0,.29):
            pane("Side hall window",side*w*.5,y+p,.48,.127,.405,"left" if side<0 else "right")
    frontdoor(0,f,.46,"plaster",.07)
    for j in range(3):
        box("Civic entry step",(0,f-.09-j*.044,.049-j*.012),(.51,.13,.058-j*.014),"pale stone")
    x,ty=-.02,.18
    box("Clock tower shaft",(x,ty,1.10),(.46,.484,1.08),"brick bright")
    for z in (1.24,1.58,1.62):
        box("Tower band",(x,ty,z),(.51,.535,.027),"pale stone")
    for off in (-1,1):
        xx, yy = x+off*.239,ty+off*.246
        tapered("Clock bezel",(x,yy,1.414),(x,yy+off*.022,1.414),.124,.124,20,"pale stone")
        tapered("Clock dial",(x,yy+off*.024,1.414),(x,yy+off*.029,1.414),.104,.104,20,"cream")
        beam("Clock minute hand",(x,yy+off*.037,1.415),(x-.024,yy+off*.037,1.489),.010,.009,"dark metal")
        beam("Clock hour hand",(x,yy+off*.038,1.414),(x+.056,yy+off*.038,1.43),.011,.009,"dark metal")
        pane("Tower side louvre",xx,ty,1.426,.123,.185,"left" if off<0 else "right","pale stone")
    box("Tower cornice",(x,ty,1.66),(.56,.581,.06),"pale stone")
    tapered("Copper spire",(x,ty,1.68),(x,ty,2.015),.36,.035,4,"teal")
    tapered("Finial",(x,ty,1.993),(x,ty,2.082),.029,.01,8,"gold")
    path("Civic flagstone walk",0,-.665,.55,.355)
    for i in (-1,1):
        box("Planter stone coping",(i*.611,-.617,.062),(.37,.23,.075),"pale stone")
        box("Planter soil",(i*.611,-.617,.105),(.33,.188,.016),"soil")
        bulbs(i*.611,-.617,Random(i))
        tapered("Town square lamp",(i*.59,-.84,0),(i*.59,-.84,.40),.019,.015,8,"dark metal")
        tapered("Lantern glass",(i*.59,-.84,.385),(i*.59,-.84,.465),.044,.052,6,"cream")
        tapered("Lantern cap",(i*.59,-.84,.465),(i*.59,-.84,.50),.061,.028,6,"dark metal")

def canopy(name, xyz, scales, palette, rng):
    x,y,z=xyz
    rx,ry,rz=scales
    sides=8
    verts=[(x,y,z-rz)]
    for layer,(height,a) in enumerate(((-.48,.76),(.22,1),(.70,.68))):
        phase=layer*.204
        for i in range(sides):
            angle=i*2*pi/sides+phase
            r=rng.uniform(.88,1.09)
            verts.append((x+rx*r*a*cos(angle),y+ry*r*a*sin(angle),z+rz*(height+rng.uniform(-.08,.08))))
    verts.append((x+.10*rx,y-.08*ry,z+rz))
    faces=[]
    for i in range(sides):
        j=(i+1)%sides
        faces += [(0,1+j,1+i),(1+i,1+j,9+i),(1+j,9+j,9+i),(9+i,9+j,17+i),(9+j,17+j,17+i),(17+i,17+j,25)]
    return mesh(name,verts,faces,[palette[rng.randrange(0,3)] for _ in faces])

def tree(style):
    rng=Random(821+style)
    height=(1.31,1.47,1.39,1.20)[style]
    bark="cedar" if style!=3 else "sapwood"
    trunk=(-.036,.026,height*.55)
    tapered("Flared rooted trunk",(0,0,0),trunk,.075,.034,8,bark,rng)
    for n in range(5):
        a=n*2*pi/5
        tapered("Exposed root",(0,0,.055),(.124*cos(a),.124*sin(a),.008),.033,.009,5,bark)
    if style in (1,2):
        p=("pine dark","pine","pine sun")
        tapered("Central leader",trunk,(.012,0,height*.94),.036,.011,7,bark)
        for layer in range(4):
            crownbase=.38+layer*.209
            width=(.39-layer*.071)*(1 if style==1 else .88)
            dx,dy=(rng.uniform(-.029,.029),rng.uniform(-.029,.029))
            # Broad asymmetric skirts taper to a pinched top on each whorl.
            tapered("Needle whorl",(dx,dy,crownbase),(dx*.2,dy*.2,crownbase+.365),width,.055-layer*.009,9,p[layer%2],rng)
            canopy("Broken lower foliage edge",(dx,dy,crownbase+.040),(width,.93*width,.109),p,rng)
    else:
        p=("foliage dark","foliage","foliage sun")
        ratio=(1 if style==0 else .88)
        tapered("Crown leader",trunk,(.055,.01,height*.89),.038,.012,7,bark)
        for i,(x,y,z,rx,ry,rz) in enumerate((
                (-.22,.043,.95,.24,.24,.25),(.22,-.036,.88,.22,.25,.24),
                (-.014,.204,1.03,.24,.23,.24),(.020,-.18,1.08,.25,.24,.24),
                (.038,.018,1.16,.30,.29,.27))):
            z=z*ratio
            tapered("Forked bough",trunk,(x*.82,y*.82,z-.04),.031,.013,6,bark)
            canopy("Oak foliage cluster" if not style else "Birch foliage cluster",(x,y,z),(rx,ry,rz*ratio),p,rng)

def material_heap(tag,x,y,z,rx,ry,h,color,rng):
    verts = [(x,y,z+h)]
    for i in range(8):
        a=i*pi/4
        r=rng.uniform(.75,1.1)
        verts.append((x+rx*r*cos(a),y+ry*r*sin(a),z+.025+rng.random()*.025))
    return mesh(tag,verts,[(0,i+1,((i+1)%8)+1) for i in range(8)],
                [color if i%3 else "coal" for i in range(8)])

def mine():
    rng=Random(31)
    box("Working hardstanding",(0,0,.014),(1.86,1.87,.028),"soil shade")
    # Raised ore headframe, cheek wheels and trussed support over a shaft.
    for i in (-1,1):
        for s in (-1,1):
            beam("Headframe truss leg",(i*.25,s*.23,0),(i*.184,s*.134,1.19),.045,.05,"dark metal")
        for y in (-.15,.15):
            beam("Headframe crossbrace",(i*.230,-y,.34),(i*.18,y,1.08),.029,.031,"metal")
    for z in (.34,.82,1.14):
        box("Structural bearing frame",(0,0,z),(.48,.35,.042),"metal")
    for x in (-.142,.142):
        tapered("Hoist sheave",(x-.027,0,1.24),(x+.027,0,1.24),.139,.139,12,"rust")
        for t in (0,pi/3,2*pi/3):
            d=(.0,.1*cos(t),.1*sin(t))
            beam("Sheave spoke",(x+.030,-d[1],1.24-d[2]),(x+.030,d[1],1.24+d[2]),.012,.016,"light metal")
    box("Shaft guard curb",(0,0,.039),(.43,.38,.079),"stone")
    box("Open grated shaft",(0,0,.087),(.33,.29,.014),"black")
    for x in (-.11,-.055,0,.055,.11):
        box("Shaft bar",(x,0,.102),(.016,.28,.017),"metal")
    beam("Hoist cable",(-.145,0,1.37),(-.145,.57,.26),.013,.014,"black")
    box("Engine house",(-.47,.59,.246),(.59,.445,.44),"brick")
    gable("Engine house roof",-.47,.59,.59,.445,.46,.61,"brick","slate","pale stone",3)
    pane("Engine house window",-.48,.366,.28,.21,.18,"front","pale stone")
    for i in range(3):
        material_heap("Loose coal",.48, -.53+.43*i,.028,.32,.24,.26+rng.random()*.12,"black",rng)
    for x in (-.11,.11):
        box("Mine siding rail",(x,-.59,.078),(.022,.72,.026),"light metal")
    for i in range(7):
        box("Mine siding sleeper",(0,-.91+i*.105,.052),(.35,.039,.038),"cedar")

def farm():
    rng=Random(682)
    box("Tilled field",(-.368,-.13,.013),(1.10,1.56,.027),"soil")
    for i in range(6):
        x=-.822+i*.172
        box("Raised furrow",(x,-.13,.038),(.071,1.51,.048),"soil shade")
        for j in range(11):
            y=-.82+j*.129
            ht=rng.uniform(.114,.196)
            tapered("Ripe wheat stand",(x,y,.047),(x+rng.uniform(-.023,.023),y,ht),.039,.033,5,"wheat")
            tapered("Golden wheat head",(x,y,ht-.02),(x,y,ht+.026),.033,.024,5,"straw")
    x,y=.544,.508
    box("Brick barn plinth",(x,y,.032),(.691,.719,.064),"stone")
    box("Weatherboard barn",(x,y,.228),(.64,.68,.37),"burgundy")
    gable("Barn roof",x,y,.64,.68,.427,.671,"burgundy","shingle","cream",4)
    for i in range(7):
        box("Barn split-door board",(x-.132+i*.043,y-.35,.218),(.038,.027,.315),"cedar")
    for i in (-1,1):
        beam("Barn door cross brace",(x+i*.013,y-.37,.145),(x+i*.136,y-.37,.289),.022,.025,"cream board")
    pane("Barn loft vent",x,y-.34,.509,.13,.085,"front","cream")
    for j in range(3):
        xx,yy=.57+j*.09,-.16-j*.19
        tapered("Cylindrical hay bale",(xx-.057,yy,.089),(xx+.057,yy,.089),.074,.074,9,"wheat")
        for i in (-1,1):
            tapered("Straw bale end",(xx+i*.061-.004,yy,.089),(xx+i*.061+.004,yy,.089),.060,.060,9,"straw")
    for j in range(5):
        box("Paddock fence post",(.878,-.79+j*.238,.111),(.047,.049,.222),"cream board")
    for z in (.088,.164):
        box("Paddock fence rails",(.878,-.319,z),(.036,1.01,.039),"cream board")

def mill():
    # Hot-metal works: furnace, elevated gas line, crane gallery and stacked ingots.
    box("Works slab",(0,0,.027),(1.85,1.85,.054),"stone")
    box("Rolling hall",(-.50,.147,.344),(.76,1.37,.585),"brick")
    gable("Rolling hall roof",-.50,.147,.76,1.37,.648,.84,"brick","slate","light metal",5)
    for yy in (-.34,.03,.42,.68):
        pane("Rolling hall clerestory",-.115,yy,.462,.200,.170,"right","pale stone")
    tapered("Blast furnace hearth",(.41,.405,.05),(.41,.405,.39),.285,.329,14,"rust")
    tapered("Blast furnace bosh",(.41,.405,.39),(.41,.405,.754),.329,.226,14,"metal")
    tapered("Furnace bell tower",(.41,.405,.754),(.41,.405,1.19),.226,.149,14,"coal")
    for z,r in ((.385,.339),(.746,.244),(.994,.186),(1.178,.160)):
        tapered("Band around furnace",(.41,.405,z-.015),(.41,.405,z+.014),r,r,14,"light metal")
    tapered("Offtake",(.41,.405,1.19),(.41,.405,1.35),.092,.092,10,"rust")
    tapered("Angled gas conduit",(.41,.405,1.32),(.68,-.235,1.19),.066,.066,9,"rust")
    tapered("Brick stove stack",(.70,-.32,.055),(.70,-.32,1.59),.112,.084,14,"brick")
    tapered("Chimney crown",(.70,-.32,1.57),(.70,-.32,1.63),.106,.102,14,"pale stone")
    for x in (.01,.63):
        for y in (-.83,-.36):
            beam("Gantry supports",(x,y,.052),(x,y,.55),.063,.062,"teal")
    for y in (-.83,-.36):
        beam("Gantry transverse girder",(-.02,y,.55),(.70,y,.55),.07,.071,"gold")
    for x in (.22,.40):
        beam("Crane slide",(x,-.85,.56),(x,-.34,.56),.036,.040,"metal")
    box("Hoist cage",(.31,-.63,.49),(.21,.16,.095),"gold")
    for k in range(2):
        for j in range(3-k):
            box("Stacked steel billets",(.28+(j-1)*.058,-.69,.080+k*.056),(.048,.30,.047),"light metal")

def factory():
    box("Factory yard",(0,0,.021),(1.83,1.85,.042),"stone")
    w,y,d=1.49,.29,.99
    box("Warehouse walls",(0,y,.335),(w,d,.575),"brick bright")
    box("Concrete dado",(0,y,.09),(w+.02,d+.02,.126),"pale stone")
    f=y-d/2
    # Three north-light sawtooth roof bays.
    for i in range(3):
        x=(i-1)*.49
        left,right=x-.256,x+.248
        back,front=y+d*.5+.045,f-.049
        low, high=.636,.896
        mesh("Sawtooth slate plane",[(left,front,low),(right,front,high),(right,back,high),(left,back,low)],
             [(0,1,2,3)],"slate")
        box("North-light glass",(right,y,(high+low)*.5),(.014,d+.014,high-low),"reflection")
        for z in (low+.015,high-.01):
            box("North-light frame",(right+.010,y,z),(.024,d+.043,.028),"light metal")
        for j in range(5):
            box("North-light mullion",(right+.012,f+.25*j,(low+high)*.5),(.025,.018,high-low),"pale stone")
        for yy,flip in ((front,False),(back,True)):
            mesh("Sawtooth end wall",[(left,yy,low),(right,yy,low),(right,yy,high)],[(0,2,1) if flip else (0,1,2)],"brick")
    for x in (-.51,-.03,.46):
        pane("Factory sash",x,f,.442,.262,.193,"front","pale stone",False,3)
    for x in (-.51,.01,.53):
        box("Factory loading shutters",(x,f-.016,.19),(.282,.035,.236),"teal")
        for j in range(4):
            box("Loading door slat",(x,f-.036,.105+.042*j),(.268,.010,.013),"dark metal")
    box("Raised loading dock",(0,f-.15,.076),(1.62,.29,.088),"pale stone")
    box("Service awning",(0,f-.145,.341),(1.61,.273,.044),"slate")
    for x in (-.69,.69):
        box("Awning supports",(x,f-.253,.195),(.036,.037,.213),"dark metal")
    for i in range(4):
        x=-.65+(i%2)*.24
        y=-.77+(i//2)*.20
        box("Jute cargo crate",(x,y,.103),(.20,.16,.159),"cedar")
        for s in (-1,1):
            box("Crate strap",(x+s*.057,y,.185),(.025,.164,.020),"sapwood")
    tapered("Factory stack",(.655,.725,.61),(.655,.725,1.32),.111,.08,12,"brick")
    tapered("Stack crown",(.655,.725,1.29),(.655,.725,1.345),.096,.096,12,"pale stone")

def export_palette():
    """UV-swatches for Luanti, padded to a power-of-two wide RGB image."""
    width, height = 256, 8
    def chunk(kind, data):
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data))
    values = (COLORS+["cream"]*64)[:64]
    pixels = b"".join(bytes.fromhex(SWATCH[key])*4 for key in values)
    png = b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR", struct.pack(">IIBBBBB",width,height,8,2,0,0,0))
    png += chunk(b"IDAT",zlib.compress((b"\0"+pixels)*height))+chunk(b"IEND",b"")
    (ROOT/"mods/bayline/textures/bl_scenery_palette.png").write_bytes(png)

def output_asset(stem, geometry, centered=False):
    # Blender objects keep editability and materials; runtime is one triangle mesh.
    init()
    geometry()
    bpy.context.scene.name="Bayline / "+stem.replace("_"," ")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/scenery_{stem}.blend"),compress=True)
    first=next(iter(bpy.context.scene.objects))
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active=first
    bpy.ops.object.join()
    o=bpy.context.object
    # Node geometry occupies .5,-.5,.5 relative to the even world anchor;
    # OBJ loader flips X and Blender-to-OBJ maps local Y to -Z.
    W=o.matrix_world.copy()
    o.matrix_world.identity()
    offset=Vector((0,0,-.5) if centered else (-.5,-.5,-.5))
    for v in o.data.vertices:
        v.co=W@v.co+offset
    uv=o.data.uv_layers.active or o.data.uv_layers.new()
    for p in o.data.polygons:
        idx=COLORS.index(o.data.materials[p.material_index].name)
        for i in p.loop_indices:
            uv.data[i].uv=((idx+.5)/64,.5)
    o.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/f"mods/bayline/models/bl_scenery_{stem}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=1,forward_axis="NEGATIVE_Z",up_axis="Y")

ASSETS=[(f"house_{i}",lambda k=i:house(k),False) for i in range(4)]
ASSETS+=[("town",town,False)]
ASSETS+=[(f"tree_{i}",lambda k=i:tree(k),True) for i in range(4)]
ASSETS+=[("mine",mine,False),("farm",farm,False),("mill",mill,False),("factory",factory,False)]
def review(path):
    init()
    layout = ([(i,0.0,f"house_{i}") for i in range(4)]
              + [(i,1.0,x) for i,x in enumerate(("town","tree_0","tree_1","tree_3"))]
              + [(i,2.0,x) for i,x in enumerate(("mine","farm","mill","factory"))]
              + [(4.0,1.0,"tree_2")])
    source={name:fn for name,fn,_ in ASSETS}
    for x,y,name in layout:
        before={ob.name for ob in bpy.context.scene.objects}
        source[name]()
        box("Preview sod", (0,0,-.061), (2,2,.117), "sage")
        for o in bpy.context.scene.objects:
            if o.name not in before:
                o.location.x += (x-1.65)*2.16
                o.location.y += (1-y)*2.43
    bpy.ops.object.camera_add(location=(1,-11,11))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((.2,.10,.4))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=12.6
    scene=bpy.context.scene
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1700,1120
    scene.render.resolution_percentage=100
    display=scene.display.shading
    display.light="STUDIO"
    display.color_type="MATERIAL"
    display.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Neutral preview backdrop")
    scene.world.color=(.14,.16,.17)
    display.show_shadows=True
    display.show_cavity=True
    display.cavity_type="BOTH"
    display.cavity_ridge_factor=1.1
    display.cavity_valley_factor=.85
    display.studiolight_rotate_z=.25
    scene.render.filepath=path
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    export_palette()
    for name,fn,center in ASSETS:
        output_asset(name,fn,center)
    if (review_path := os.environ.get("BAYLINE_SCENERY_REVIEW")):
        review(review_path)
