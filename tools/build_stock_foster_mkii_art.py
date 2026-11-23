#!/usr/bin/env python3
"""Original Foster MkII production artwork. Native .40; Y=0 tread, nose −Z."""
from math import cos, sin, sqrt, tau
from pathlib import Path
import os
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
sys.path.append(os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_road_primitives as road

w, r, bpy, V = road.w, road.r, road.bpy, road.Vector
B, C, rod = road.B, road.C, road.rod
STEM = "bl_stock_foster_mk2_bus"
COL = {
    "Axle grey":"535d64", "Frame":"283740", "Rubber":"282b30", "Tyre scuff":"3d4248",
    "Hub":"55647a", "Nurled iron":"394451", "Rim":"a3aead", "Roof dark":"222e40",
    "Midnight blue":"243c55", "Coat shadow":"274967", "Main cobalt":"315c85",
    "Roof shoulder blue":"487da7", "Roof peak blue":"5588ad", "Waist blue":"386c98",
    "Bright fairing":"69a1bd", "Molding blue":"426886", "Ice stripe":"a5c2d2",
    "Accent aqua":"7ac2c1", "Reflective register":"c6d3c8", "Black trim":"26343f",
    "Satin moulding":"3a4b59", "Cab underside":"283d4e", "Access panel blue":"2e5270",
    "Glass rim":"242d3a", "Glass":"314e64", "Glass glint":"7498ab",
    "Glass rear shade":"40576a", "Warm side glass":"624e42", "Tint blue":"4a6a83",
    "Tint upper":"638fa7", "Tint lower":"2d445f", "Tint fade":"566f88",
    "Aluminum":"adbabc", "Brushed alloy":"798e99", "Bright chrome":"c2cbc5",
    "White LED":"f0e4be", "Marker Amber":"dfaa58", "Tail ruby":"b94c50",
    "Tail bead":"e87966", "Tail dark":"673f4e", "Rear plate amber":"dcb675",
    "Destination face":"293d43", "Destination lit":"ecd19a", "Pavement":"556268",
    "Lane marking":"e2c997", "Silk Silver":"b5c9ca", "Shell light":"477499",
    "Console pad":"526067", "Reverse light":"bec7c4", "Bright inset":"365673",
    "Grille black":"212c34", "Grille satin":"45535c", "Cooling shadow":"243844",
    "Nickel muted":"8599a1", "Side latch blue":"254761", "Air intake":"253e53",
}
while len(COL) < 64:
    COL[f"Reserved {len(COL):02}"] = "627078"
P = {label:i for i,label in enumerate(COL)}
w.P = road.P = P
r.COLORS[:] = COL.values()
AXLES = (-.451, .467)
R = .119
T = .227
DOORS = ((-.704,-.558), (.024,.231))
LOW = ((-.811,.162),(-.798,.221),(-.767,.250),(-.704,.275),(-.652,.277),
       (.660,.277),(.726,.267),(.764,.245),(.791,.200))
UP = ((-.792,.181,.392,.430),(-.766,.224,.412,.457),(-.733,.247,.440,.491),
      (-.682,.263,.492,.536),(-.628,.274,.534,.596),(-.571,.277,.560,.641),
      (-.492,.278,.566,.677),(-.400,.278,.568,.686),
      (.567,.278,.568,.686),(.665,.277,.558,.671),
      (.730,.265,.525,.632),(.768,.240,.486,.576),(.787,.207,.448,.513))


def interp(rows, z):
    for left, right in zip(rows, rows[1:]):
        a,b = left[0],right[0]
        if a <= z <= b:
            f=(z-a)/(b-a)
            return tuple(x+(y-x)*f for x,y in zip(left[1:],right[1:]))
    return rows[0 if z < rows[0][0] else -1][1:]


def f(m,name,col,points):
    road.f(m,name,col,points)


def low_body(m):
    road.bus_frame(m,-.687,.714,.384)
    road.wheels(m,*AXLES,T,R,"Aluminum",True)
    for s in (-1,1):
        for z in AXLES:
            road.fender(m,"Original color-keyed rolled arch trim",s*.245,z,R,R+.033,.086,"Midnight blue")
            B(m,"Heavy front and rear axle flex air springs","Axle grey",s*.147,z,.045,.057,.119,.212,.01)
        B(m,"Original suspended rear wheel spray louver","Rubber",s*.227,.607,.073,.023,.071,.213,.006)
    cuts={z for z,_ in LOW}
    for z in AXLES:
        cuts.update(z+j*.148/9 for j in range(-9,10))
    for a,b in DOORS:
        cuts.update((a-.006,a,a+.016,b-.016,b,b+.006))
    rings=[]
    for z in sorted(cuts):
        t,=interp(LOW,z)
        d=min(abs(z-a) for a in AXLES)
        h=max(.137,R+sqrt(max(0,.148*.148-d*d)))
        opening=max(0.,*(min(1.,(z-a)/.017,(b-z)/.017) for a,b in DOORS))
        p=t-opening*.045
        rings.append((z,[(-t*.84,h),(p*.84,h),(p,h+.018),(p*.997,.273),
                         (t,.311),(t*.98,.344),(-t*.98,.344),(-t,.311),
                         (-t*.997,.273),(-t,h+.018)]))
    road.section_hull(m,"Continuous low-floor outer skin with actual wheel and door relief",rings,
                     ["Cab underside","Midnight blue","Coat shadow","Main cobalt","Waist blue","Main cobalt",
                      "Waist blue","Main cobalt","Coat shadow","Midnight blue"],"Main cobalt")


def upper_hull(m):
    def contour(x, h, top):
        return [(-x*.97,.337),(x*.97,.337),(x,.365),(x,h-.030),(x*.982,h),
                (x*.845,top-.037),(x*.652,top-.014),(x*.333,top-.004),
                (0.,top),(-x*.333,top-.004),(-x*.652,top-.014),(-x*.845,top-.037),
                (-x*.982,h),(-x,h-.030),(-x,.365)]
    road.section_hull(m,"Crowned single-deck composite passenger coach shell",
      [(z,contour(x,h,top)) for z,x,h,top in UP],
      ["Main cobalt","Glass rim","Black trim","Roof dark","Roof shoulder blue","Roof peak blue","Bright fairing",
       "Roof peak blue","Roof peak blue","Bright fairing","Roof peak blue","Roof shoulder blue",
       "Roof dark","Black trim","Glass rim"],"Main cobalt")


def window_sweep(m,kind):
    """Build a contiguous curved laminated windshield along actual hull contours."""
    front=kind=="front"
    extents=((-.775,-.487) if front else (.628,.777))
    wanted=[z for z,*_ in UP if extents[0] < z < extents[1]]
    shape=lambda width: tuple(sorted({x for x in (0.,.333,.652,.845,width) if x<=width}))
    def point(z, fraction, lift):
        x,h,t=interp(UP,z)
        curve=((0.,t),(.333,t-.004),(.652,t-.014),(.845,t-.037),(.982,h))
        return (x*fraction,z,interp(curve,abs(fraction))[0]+lift)
    def shell(name,col,z0,z1,width,lift):
        cuts=[z0,*(z for z in wanted if z0<z<z1),z1]
        half=shape(width)
        xs=[-v for v in reversed(half[1:])]+list(half)
        lines=[[point(z,t,lift) for t in xs] for z in cuts]
        for a,b in zip(lines,lines[1:]):
            for i in range(len(a)-1):
                f(m,kind.title()+" "+name,col,(a[i],a[i+1],b[i+1],b[i]))
    a,b=extents
    shell("Deep swept rubber windshield perimeter","Glass rim",a,b,.922,.008)
    shell("Continuous curved laminated driver pane","Glass",a+.012,b-.012,.870,.015)
    if front:
        shell("Soft top edge sky reflection in windshield","Glass glint",-.519,-.503,.807,.017)
    else:
        shell("Soft top edge sky reflection in windshield","Glass glint",.643,.661,.794,.017)
    if front:
        for s in (-1,1):
            a,b,c=point(-.753,s*.188,.019),point(-.725,s*.575,.023),point(-.698,s*.679,.025)
            rod(m,"Twin independently parked windscreen wiper arms","Black trim",a,b,.0038)
            rod(m,"Twin independently parked windscreen wiper blades","Black trim",b,c,.0031)


def side_window(m,s,z,width,low=.362,high=.538):
    x,*_=interp(UP,z)
    x*=s
    B(m,"Deep dark wraparound side-window perimeter","Glass rim",x+s*.002,z,.013,width,low,high,.009)
    B(m,"Large dark panoramic passenger glass","Tint blue",x+s*.012,z,.008,width-.016,
      low+.012,high-.012,.006)
    B(m,"Warm lower internal silhouettes behind window","Tint lower",x+s*.018,z,.006,width-.025,
      low+.016,low+.046,.005)
    B(m,"High cold sky ribbon across pane","Tint upper",x+s*.018,z,.006,width-.025,
      high-.048,high-.019,.004)
    B(m,"Subtle diagonal glint on modern flush glazing","Glass glint",x+s*.020,z-.008,.004,width-.044,
      high-.029,high-.022,.002)


def door(m,a,b):
    z=(a+b)/2
    span=b-a
    B(m,"Recessed sliding passenger doorway reveal","Black trim",.262,z,.030,span,.173,.552,.010)
    for zz in (z-span*.244,z+span*.244):
        B(m,"Individually modeled plug-sliding door leaves","Coat shadow",.278,zz,
          .016,span*.466,.188,.525,.006)
        B(m,"Tall laminated boarding-door glass","Glass",.287,zz,.008,span*.380,.307,.517,.005)
        B(m,"Reflected sky in doors","Tint upper",.293,zz,.004,span*.363,.469,.510,.003)
        B(m,"New low sill step guard on boarding door","Access panel blue",.288,zz,
          .009,span*.397,.197,.299,.007)
        B(m,"Door pull and accessibility push button","Brushed alloy",.295,zz,.006,.024,.290,.304,.003)
    for dx,y in ((.259,.161),(.238,.197)):
        B(m,"Serrated aluminum boarding threshold","Grille satin",dx,z,.053,span-.007,y,y+.012,.004)
        B(m,"High-contrast edge along low-floor entrance","Ice stripe",dx+.027,z,.007,span-.010,
          y+.005,y+.013,.002)
    for dz in (-span*.43,span*.43):
        rod(m,"Powder-coated passenger grab post","Accent aqua",(.282,z+dz,.201),(.282,z+dz,.337),.0038)


def sides(m):
    for a,b in DOORS:
        door(m,a,b)
    for s in (-1,1):
        if s<0:
            side_window(m,s,-.580,.177,.368,.529)
            side_window(m,s,.132,.226)
        side_window(m,s,-.374,.250)
        side_window(m,s,-.113,.253)
        side_window(m,s,.353,.222)
        side_window(m,s,.582,.199,.363,.533)
        side_window(m,s,.710,.060,.373,.495)
        belt=[(-.728,.325),(-.704,.340),(-.645,.351),(-.558,.348),(-.478,.349),
              (.024,.349),(.231,.349),(.473,.349),(.664,.349),(.749,.319)]
        for (z0,y0),(z1,y1) in zip(belt,belt[1:]):
            if s>0 and any(a<(z0+z1)/2<b for a,b in DOORS):
                continue
            x0,x1=(s*(interp(LOW,z)[0]+.003) for z in (z0,z1))
            f(m,"Continuous pale blue fleet waist graphic","Ice stripe",
              ((x0,z0,y0),(x1,z1,y1),(x1,z1,y1+.023),(x0,z0,y0+.023))[::s])
        tail=[(-.293,.273),(-.121,.269),(.024,.272),(.231,.275),(.291,.280),(.529,.306),(.679,.330)]
        for (z0,y0),(z1,y1) in zip(tail,tail[1:]):
            if s>0 and .024<(z0+z1)/2<.231:
                continue
            x0,x1=(s*(interp(LOW,z)[0]+.004) for z in (z0,z1))
            f(m,"Original aqua swept accent livery","Accent aqua",
                ((x0,z0,y0),(x1,z1,y1),(x1,z1,y1+.018),(x0,z0,y0+.016))[::s])
        for z,span in ((-.186,.261),(.303,.126),(.667,.092)):
            x=s*interp(LOW,z)[0]
            B(m,"Stamped and hinged lower service door","Side latch blue",x,z,.010,span,.190,.254,.008)
            B(m,"Main color inset service door","Access panel blue",x+s*.006,z,
                .008,span-.013,.195,.250,.005)
            B(m,"Flush bright service key latch","Brushed alloy",x+s*.011,z+span*.28,
                .005,.025,.215,.225,.002)
        rod(m,"Aerodynamic forward mirror arms tied to A-pillar","Black trim",
            (s*.256,-.651,.462),(s*.294,-.665,.480),.0055)
        B(m,"Folded-in sculpted mirror covers","Waist blue",s*.294,-.666,.033,.035,.460,.518,.007)
        B(m,"Rear-facing mirror reflectors","Bright chrome",s*.295,-.646,.025,.010,.466,.512,.004)
        for z in (-.705,-.227,.279,.698):
            x=s*(interp(LOW,z)[0]+.005)
            B(m,"Road-position amber side reflectors","Marker Amber",x,z,.007,.018,.207,.218,.002)


def fascia(m):
    B(m,"Sculpted rounded lower front impact beam","Black trim",0,-.799,.433,.044,.155,.215,.015)
    B(m,"Front recessed lower cooling mouth","Grille black",0,-.811,.235,.031,.218,.278,.012)
    for i in range(6):
        B(m,"Front lower recessed intake vanes","Grille satin",0,-.830,.196,.008,.225+.007*i,.228+.007*i,.001)
    B(m,"Two opposed modern sill ribs","Molding blue",0,-.825,.259,.009,.159,.176,.003)
    for s in (-1,1):
        def light_path(name,col,outline,z):
            points = [(s*x,z+max(0,x-.162)*.22,h) for x,h in outline]
            f(m,name,col,points[::s])
        outer=((.103,.286),(.213,.286),(.249,.311),(.233,.335),(.138,.329),(.103,.315))
        white=((.113,.294),(.208,.294),(.232,.313),(.226,.326),(.145,.323),(.113,.313))
        light_path("Original swept front polycarbonate light housing","Black trim",outer,-.818)
        light_path("True forward swept lights","White LED",white,-.826)
        light_path("Fine white running lamp eyebrow","Reverse light",[(x,y+.005) for x,y in white],-.830)
        B(m,"Low fog lamp cast round mounted","Brushed alloy",s*.168,-.814,.069,.009,.183,.208,.008)
        B(m,"Independent warm fog lamp insert","White LED",s*.169,-.821,.051,.006,.187,.202,.007)
        B(m,"Slim bright side indicator","Marker Amber",s*.227,-.786,.027,.010,.258,.278,.006)
        B(m,"Tall sculpted rear red light casting","Tail dark",s*.165,.789,.074,.035,.246,.398,.013)
        for j in range(3):
            B(m,"Raised LED rear luminous row","Tail ruby" if j!=1 else "Reverse light",s*.165,.807,.055,.013,
              .269+j*.035,.287+j*.035,.004)
            B(m,"Inner LED edge lip","Tail bead" if j!=1 else "Silk Silver",s*.165,.815,.041,.005,
              .280+j*.035,.285+j*.035,.002)
        B(m,"Warm high rear marker in engine apron","Marker Amber",s*.157,.805,.041,.012,.376,.386,.003)
    B(m,"Front integrated fleet panel","Destination face",0,-.803,.163,.023,.350,.388,.007)
    glyphs=(("101","101","010","101","101"),("111","001","111","100","111"))
    for i,glyph in enumerate(glyphs):
        for y,row in enumerate(glyph):
            for x,lit in enumerate(row):
                if lit=="1":
                    B(m,"Independent tiny warm LED route dots","Destination lit",(i-.5)*.028+(x-1)*.007,
                      -.817,.0049,.006,.381-y*.005,.384-y*.005,.001)
    B(m,"Full rear quarter wrap impact strip","Midnight blue",0,.786,.413,.053,.146,.211,.014)
    B(m,"Rear opening engine bay appliance surround","Black trim",0,.789,.247,.025,.228,.379,.006)
    for j in range(7):
        B(m,"Stamped rear heat exchanger louvre","Grille satin",0,.806,.220,.011,.248+j*.017,.255+j*.017,.003)
    B(m,"Yellow rear fleet registration plate frame","Black trim",0,.818,.123,.012,.179,.210,.004)
    B(m,"Yellow rear registration plate","Rear plate amber",0,.826,.108,.006,.181,.206,.004)
    for i,h in enumerate((.013,.017,.010,.015,.016,.010,.012)):
        B(m,"Unbranded plate detail","Destination face",-.043+i*.014,.830,.005,.004,.185,.185+h,.001)
    rod(m,"Rear side-exit exhaust tailpipe","Axle grey",(.062,.688,.106),(.065,.810,.116),.014)


def roof(m):
    for s in (-1,1):
        for a,b,y in ((-.454,-.187,.622),(-.149,.224,.622),(.256,.562,.622)):
            rod(m,"Long rainseal beside molded roof fairing","Shell light",(s*.232,a,y),(s*.232,b,y),.005)
    def ac(z,w,h):
        return (z,[(-w,.657),(w,.657),(w,h-.023),(w*.84,h-.008),(w*.67,h),(-w*.67,h),
                   (-w*.84,h-.008),(-w,h-.023)])
    road.section_hull(m,"Low-profile 2000s single-deck rooftop air conditioner",
      [ac(.111,.122,.687),ac(.159,.172,.715),ac(.425,.173,.715),ac(.492,.132,.691)],
      ["Roof dark","Roof shoulder blue","Bright fairing","Roof peak blue","Roof shoulder blue",
       "Roof peak blue","Bright fairing","Roof shoulder blue"],"Shell light")
    for x in (-.087,.087):
        for z in (.249,.365):
            C(m,"A/C cooling intake pressure grille rim","Roof dark",(x,z,.716),.041,"h",-.003,.0025,18)
            C(m,"Recess in separate boxed A/C cooling collar","Cooling shadow",(x,z,.720),.034,"h",-.002,.002,16)
            for i in range(7):
                dx=(i-3)*.008
                B(m,"Flush slots in rooftop fan guards","Grille satin",x+dx,z,.003,2*sqrt(.032**2-dx**2),
                  .721,.724,.001)
    B(m,"Independent light blue roof escape hatch","Bright fairing",0,-.192,.227,.162,.678,.694,.013)
    B(m,"Smoked inset on emergency exit hatch","Glass rear shade",0,-.192,.174,.123,.691,.699,.009)
    B(m,"Embossed emergency hatch arrow strip","Ice stripe",0,-.170,.133,.014,.697,.701,.003)
    B(m,"Black rubber radio base","Black trim",.120,-.410,.028,.023,.661,.692,.006)
    rod(m,"Raked coach radio aerial","Satin moulding",(.120,-.410,.688),(.125,-.358,.746),.0026)


def art():
    m=r.Mesh(r.terrain_height(0))
    low_body(m)
    upper_hull(m)
    window_sweep(m,"front")
    window_sweep(m,"rear")
    sides(m)
    fascia(m)
    roof(m)
    return m


def palette(path):
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(val)*16 for val in COL.values())
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",1024,16,8,2,0,0,0))+
        chunk(b"IDAT",zlib.compress((b"\0"+row)*16))+chunk(b"IEND",b""))


def make():
    artpath=ROOT/"art/stock_foster_mk2_bus.blend"
    palette(ROOT/"mods/luanttd_core/textures"/(STEM+"_atlas.png"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Foster MkII Superbus #119"
    scene["source_version"]="OpenTTD 16.0-RC1"
    scene["stock_engine_id"]=119
    scene["native_visual_scale"]=.40
    scene["axes"]="−Y nose/Z up in Blender; −Z nose/Y up in Luanti; actual tread Y=0"
    editable=bpy.data.collections.new("01 • Original editable MkII coachwork")
    scene.collection.children.link(editable)
    m=art()
    mats=r.materials()
    for label,mat in zip(COL,mats):
        mat.name=label
        shader=mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value=.29 if label.startswith(("Glass","Tint")) else .56
        shader.inputs["Metallic"].default_value=.45 if label.startswith(("Brushed","Bright chrome","Aluminum")) else .12
    r.to_blender(m,editable,mats)
    obj=ROOT/"mods/luanttd_core/models"/(STEM+".obj")
    r.export_obj(obj,w.local_obj(m))
    lines=obj.read_text().splitlines()
    lines[0]="# Original LuanTTD Foster MkII Superbus; tools/build_stock_foster_mkii_art.py"
    obj.write_text("\n".join(lines)+"\n")
    prev=set(scene.objects)
    road.studio(scene)
    studio=bpy.data.collections.new("90 • Studio pavement and cameras (excluded from OBJ)")
    scene.collection.children.link(studio)
    front=scene.camera
    views=[
        ("front",front,(2.13,-2.65,1.58),1.95),
        ("rear",None,(-2.20,2.52,1.50),1.95),
        ("street",None,(2.58,-1.19,.68),2.05),
    ]
    cameras=[]
    for name,cam,loc,zoom in views:
        if cam is None:
            cam=front.copy()
            cam.data=front.data.copy()
            scene.collection.objects.link(cam)
        cam.name=f"{name.title()} inspection"
        cam.location=loc
        cam.rotation_euler=(V((0,0,.356))-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.ortho_scale=zoom
        cameras.append((name,cam))
    for other in set(scene.objects)-prev:
        for layer in list(other.users_collection):
            layer.objects.unlink(other)
        studio.objects.link(other)
    scene.view_settings.exposure=.68
    scene.display.shading.studiolight_rotate_z=.32
    scene.render.resolution_x,scene.render.resolution_y=1000,720
    scene.render.resolution_percentage=100
    bpy.ops.wm.save_as_mainfile(filepath=str(artpath),compress=True)
    if qa:=os.getenv("SUPERBUS_QA"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=90
        for name,cam in cameras:
            scene.camera=cam
            scene.render.filepath=str(Path(qa)/f"superbus-{name}.jpg")
            bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    make()
