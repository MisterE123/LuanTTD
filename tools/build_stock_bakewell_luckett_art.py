#!/usr/bin/env python3
"""Four editable Bakewell–Luckett aircraft from the stock RC1 City/Country fleet.

blender -b -t 2 --python-exit-code 1 --python tools/build_stock_bakewell_luckett_art.py
Optional BAKEWELL_REVIEW=/dir captures apron/flight images. No external art imported.
"""
from dataclasses import dataclass
from math import cos, sin, sqrt, pi, tau
from pathlib import Path
import os
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_stock_darwin_family_art as native

art, base, B, C, M = native.art, native.base, native.B, native.C, native.M
e = native.e

@dataclass(frozen=True)
class Airframe:
    id: int
    series: str
    description: str
    livery: tuple
    fuselage: tuple # fore/aft extent, pressure half-width, belt, crown and belly
    nose: tuple     # width/crown at the pressure windscreen and blunt tip
    wing: tuple     # semi-span, root leading/trailing, tip leading/trailing, root height and dihedral
    tail: tuple     # stabilizer semi-span, leading/trailing, height, dihedral, fin root lead, fin tip lead, fin height
    motor: tuple    # offset, intake/exhaust y, height, intake radius, exhaust radius
    gear: tuple
    cabin: tuple    # outer window count, roundness, independent mid and aft door positions
    dorsal: tuple | None = None # centerline trijet nacelle datum and annulus
    tips: bool = False

    @property
    def stem(self): return f"bakewell_luckett_lb{self.series}"
    @property
    def export_name(self): return f"Bakewell_Luckett_LB{self.series}"
    @property
    def name(self): return f"Bakewell Luckett LB{'-' if self.series != '80' else ''}{self.series}"

FRAMES = [
    Airframe(221,"9","Compact rear-twin narrow-body, short wing, raised tailplane and low tricycle bogies",
        ("fff4dd","e6e4d3","a1303a","672f36","ad343a","e2aa87","cbc3bb"),
        (.791,.821,.116,.210,.112,.105),(.86,.92,.025),(.711,.120,-.394,-.229,-.365,.153,.070),
        (.275,-.583,-.791,.525,.018,-.461,-.677,.548),
        (.180,-.363,-.743,.253,.059,.040),(.172,-.136,.046,.0,1,.506,.032),
        (19,.87,(.073,),-.534)),
    Airframe(222,"80","Stretched rear-twin narrow-body, higher tail, larger fan cans and extended cabin",
        ("edeae0","d6dfda","287a77","254e5d","357276","e1b363","9baeb1"),
        (1.056,1.106,.123,.234,.116,.105),(.82,.95,.017),(.817,.158,-.478,-.201,-.435,.179,.081),
        (.311,-.827,-1.051,.597,.019,-.622,-.897,.623),
        (.186,-.550,-.998,.291,.074,.046),(.193,-.182,.048,.0,1,.685,.033),
        (29,.53,(.267,-.355),-.677)),
    Airframe(223,"10","Early wide-body trijet, twin underwing pods and straight-through dorsal third duct",
        ("f1e9d6","e0ddd7","39699b","30486d","a34136","df9d48","b9cad3"),
        (.996,.997,.178,.285,.152,.142),(.88,.97,.034),(.922,.276,-.428,-.235,-.397,.199,.104),
        (.418,-.614,-.962,.358,.022,-.415,-.821,.690),
        (.364,.240,-.233,.160,.103,.061),(.229,-.125,.056,.080,2,.652,.039),
        (25,.65,(.337,-.314),-.653),
        (0,-.540,-1.038,.509,.101,.055)),
    Airframe(224,"11","Stretch wide-body trijet with upright winglets, broad fans and an additional centerline bogie",
        ("f4efeb","e3d9e2","664867","492d58","7c4263","dfa7a6","a6a4b6"),
        (1.083,1.077,.173,.309,.147,.138),(.83,.91,.022),(.938,.308,-.467,-.250,-.439,.204,.122),
        (.354,-.702,-1.029,.383,.026,-.497,-.914,.726),
        (.386,.207,-.280,.163,.111,.059),(.250,-.163,.059,.088,2,.728,.041),
        (29,.68,(.393,-.369),-.734),
        (0,-.623,-1.137,.532,.105,.053),True),
]
COLORS = ("Crown ivory","Panel ivory","Lit blue","Dark coastal cobalt","Blue taper",
          "Copper pinstripe","Silver pressure hull")

def sections(q):
    fore, aft, w, h, cu, belly = q.fuselage
    nose, crown, blunt = q.nose
    # 18 separate cross-sections, including each model's physical nose/radome and pressure bulkhead.
    front = [(0,1,1,1),(.43,1,1,1),(.610,.994,.992,.981),(.709,.972,.989,.930),
             (.802,nose,crown,.804),(.868,nose*.862,crown*.86,.676),(.922,nose*.671,crown*.711,.491),
             (.956,nose*.466,crown*.551,.326),(.985,nose*.241,crown*.344,.161),(1,blunt,.085,.048)]
    rear = [(1,.032,.082,.040),(.978,.171,.260,.162),(.915,.330,.474,.308),
            (.823,.550,.665,.468),(.713,.719,.831,.655),(.569,.893,.948,.848),(.40,.981,1,.980),(.28,1,1,1)]
    return tuple((-aft*t,w*x,h+.043*max(0,t-.55),cu*z,belly*b) for t,x,z,b in rear)+tuple(
                (fore*t,w*x,h-.048*max(0,t-.66),cu*z,belly*b) for t,x,z,b in front)

def body(q):
    loft = sections(q)
    ang = [j*tau/40 for j in range(40)]
    def stripe(a):
        a=sin(a+pi/40)
        if q.dorsal:         # broad split-deck cheatline on the larger fuselages
            levels=(.81,.49,.19,-.065,-.17,-.64)
        elif q.id==221:      # narrow enameled picture windows with a low metal belly
            levels=(.78,.32,.19,-.075,-.12,-.61)
        else:                # mid-era twin ribbon and a silver painted lower cargo deck
            levels=(.78,.47,.28,.075,-.08,-.63)
        return next((color for i,color in enumerate(COLORS[:6]) if a>levels[i]),"Bellying brushed alloy")
    art.sections("Independent panelled pressure loft with original fuselage banding",
        [(y,[(w*cos(a),h+(r if sin(a)>0 else b)*sin(a)) for a in ang])
         for y,w,h,r,b in loft],"Silver pressure hull",[stripe(a) for a in ang])
    fore,aft,_,belt,crown,_=q.fuselage
    def skin(s,y,z,lift):
        w,h,a,b=e.interp(loft,y)
        f=(z-h)/(a if z>=h else b)
        assert abs(f)<1,(q.name,y,z,f)
        return (s*(w*sqrt(1-f*f)+lift),y,z)
    count,rounded,doors,aftdoor=q.cabin
    outline=[(cos(tau*i/10),sin(tau*i/10)) for i in range(10)] if rounded>.8 else [
        (-1,-.54),(-.56,-1),(.56,-1),(1,-.54),(1,.54),(.56,1),(-.56,1),(-1,.54)]
    def pane(name,color,s,y,z,w,h,raise_,rim=False,square=False):
        poly=((-1,-.63),(-.64,-1),(.64,-1),(1,-.63),(1,.63),(.64,1),(-.64,1),(-1,.63)) if square else outline
        n=len(poly)
        loops=(1,.87) if rim else (1,.62,.25)
        pts=[skin(s,y+u*w*f,z+v*h*f,raise_) for f in loops for u,v in poly]
        fs=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)[::s] for j in range(len(loops)-1) for i in range(n)]
        if not rim: fs.append(tuple(range(2*n,3*n))[::s])
        return M(name,pts,fs,color)
    for s in (-1,1):
        start,end=.68*fore,(-.576 if q.dorsal else -.46)*aft
        for i in range(count):
            y=start-(start-end)*i/(count-1)
            if any(abs(y-d)<.035 for d in doors): continue
            z=belt+(.040 if q.dorsal else .034)
            pane("Individual airliner pressure-window rim","Aluminium bezel",s,y,z,.013,.016,.0033)
            pane("Separate dark rounded passenger glass","Cab glass",s,y,z,.011,.013,.0048)
            pane("Subtle light reflected in a real passenger pane","Window glint",s,y+.001,z+.005,.006,.002,.0057)
        for y in (.746*fore,*doors,aftdoor):
            w,h=(.019,.036) if y in doors else (.030,.058)
            pane("Outline of independent hinged and latched cabin door","Pressure door seal",s,y,belt+.001,w,h,.0052,True,True)
            pane("Door window tinted glazing","Cab glass",s,y,belt+.020,w*.37,h*.23,.0066,False,True)
        for y in (-.406*aft,.298*fore):
            pane("Inset lower hold rectangle","Pressure door seal",s,y,belt-.053,.061,.028,.0055,True,True)
            pane("Latch set in lower cargo door","Landing gear chrome",s,y,belt-.048,.016,.0025,.0075)
        # Each in-house tail mark repeats in a smaller geometric badge beside the passenger door.
        for i in range(2):
            vertices=[skin(s,fore*.598-u*.035-i*.028,belt+.074+v*.021,.0065)
                      for u,v in ((0,0),(.7,1),(1.3,1),(.56,0))]
            M("Bakewell tandem flight-stripe badge",vertices,[(0,1,2,3)[::s]],"Blue taper")
        def glass(name,ink,a,b,l,r,offset):
            pts=[]
            for i in range(8):
                v=i/7
                y=fore*(a+(b-a)*v)
                w,h,u,_=e.interp(loft,y)
                for j in range(8):
                    x=l+(r-l)*j/7-v*(.04 if j>4 else -.06)
                    pts.append((s*x*w,y,h+u*sqrt(1-x*x)+offset))
            faces=[(i*8+j,i*8+j+1,(i+1)*8+j+1,(i+1)*8+j)[::s] for i in range(7) for j in range(7)]
            M(name,pts,faces,ink)
        glass("Recessed two-layer wraparound windscreen seal","Glazing bezel",.812,.955,.025,.840,.0045)
        glass("Compound-curved stand-alone cockpit glazing","Cab glass",.824,.944,.066,.799,.0067)
        glass("Scaled reflection across upper cockpit quadrant","Window glint",.855,.867,.250,.736,.008)
        for v in (.29,.588):
            def edge(y):
                w,h,u,_=e.interp(loft,y*fore)
                return (s*v*w,y*fore,h+u*sqrt(1-v*v)+.009)
            C("Cockpit structural mullion",edge(.829),edge(.938),.0024,.0017,"Glazing bezel",7)
    C("Dorsal communications antenna",(0,.26,belt+crown),(0,.241,belt+crown+.041),.008,.001,"Wing leading trim",8)

def surfaces(q):
    semispan,le,te,tip,tipte,height,delta=q.wing
    span,sle,ste,root,rise,fle,ftip,fheight=q.tail
    def rows(fs,x,a,b,c,d,r,z,th):
        return [(x*f,a+(c-a)*f**.91,b+(d-b)*f,r+z*f**1.12,th*(1-.94*f)) for f in fs]
    main=rows((.09,.19,.32,.50,.68,.82,.93,1),semispan,le,te,tip,tipte,height,delta,.095 if q.dorsal else .075)
    stab=rows((.05,.20,.44,.67,.84,1),span,sle,ste,sle-.152,ste+.022,root,rise,.040)
    for side in (-1,1):
        art.foil("Main pressure-formed wing, dihedral and separate trailing control surface",main,side)
        art.foil("High T-tail stabilizer" if not q.dorsal else "Swept conventional trijet tailplane",stab,side)
        for f in (.32,.57,.77):
            y=te+(tipte-te)*f
            z=height+delta*f-.013
            x=semispan*f*side
            C("Pale exposed slotted-flap track blister",(x,y+.097,z),(x+side*.031,y-.087,z+.013),.016,.005,
              "Shadowed flap",9)
            C("Closed upper flap panel hinge",(x,y+.089,z+.046),(x+side*.105,y+.050,z+.057),.0017,.0015,"Rib inset",6)
        x,front,back,z,_=main[-1]
        if q.tips:
            # Winglet is an upright airfoil, not just translated geometry.
            rs=((x-.049,z,front+.032,back-.003,.015),(x-.020,z+.071,front-.021,back+.001,.012),
                (x+.010,z+.157,front-.091,back-.019,.007),(x+.021,z+.186,front-.119,back-.033,.004))
            pts=[(side*(u+w*f),a+(b-a)*g,h) for u,h,a,b,w in rs
                 for f,g in ((0,0),(-.64,.22),(-.69,.69),(0,1),(.69,.69),(.64,.22))]
            polys=[tuple(range(6))]+[(i*6+j,i*6+(j+1)%6,(i+1)*6+(j+1)%6,(i+1)*6+j) for i in range(3) for j in range(6)]
            polys+=[tuple(range(18,24))]
            art.close_mesh("Individually swept and tapered vertical winglet",pts,polys,
                           ["Dark coastal cobalt"]*7+["Blue taper"]*6+["Lit blue"]*6+["Copper pinstripe"])
        C("Port or starboard navigation lamp",(side*x,front+.006,z),(side*x,front-.030,z),
          .0072,.0046,"Port marker ruby" if side<0 else "Starboard marker mint",9)
    aft=q.fuselage[1]
    # Tri-jet vertical tail starts on the external nacelle's crown, so
    # the center intake is an actual hollow chamber rather than capped by fin steel.
    min_h=q.dorsal[3]+q.dorsal[4]*.78 if q.dorsal else q.fuselage[3]+.031
    trailing=-aft*.981
    profile=((0,0),(.076,-.48),(.26,-1),(.66,-.75),(.95,-.30),(1,0),(.95,.30),(.66,.75),(.26,1),(.076,.48))
    levels=((0,.027),(.16,.041),(.31,.040),(.52,.034),(.71,.028),(.90,.021),(1,.010))
    verts=[]
    for f,w in levels:
        a=fle+(ftip-fle)*f**.79
        b=trailing+(.029 if q.dorsal else .049)*f
        if q.dorsal: a=min(a,q.dorsal[1]-.036-.09*f)
        z=min_h+(fheight-min_h)*f
        verts.extend((w*x,a+(b-a)*y,z) for y,x in profile)
    faces=[tuple(range(10))]; inks=["Dark coastal cobalt"]
    band=("Crown ivory","Dark coastal cobalt","Blue taper","Lit blue","Copper pinstripe","Blue taper") if q.id in (221,223) else (
        "Dark coastal cobalt","Dark coastal cobalt","Copper pinstripe","Blue taper","Lit blue","Crown ivory")
    for j,col in enumerate(band):
        for i in range(10):
            faces.append((j*10+i,j*10+(i+1)%10,(j+1)*10+(i+1)%10,(j+1)*10+i));inks.append(col)
    faces.append(tuple(range(60,70)));inks.append("Crown ivory")
    art.close_mesh("Real swept vertical tail with Bakewell family fin paint",verts,faces,inks)
    C("Top white tail beacon",(0,trailing+.038,fheight),(0,trailing+.059,fheight+.010),.006,.004,
      "Bright cap light",8)

def propulsion(q):
    def nacelle(title, dims, dorsal=False):
        x,front,back,h,r,ex=dims
        def v(t,rad,d,tone):
            return (front+(back-front)*t,rad,h+d,tone)
        d=.006 if dorsal else .009
        art.turbojet(title,x,(
            v(0,r*.839,0,"Wing leading trim"),v(.042,r,0,"Skinned wing alloy"),
            v(.16,r*1.033,-d*.18,"Silver pressure hull"),v(.43,r*.981,-d*.40,"Panel ivory"),
            v(.65,r*.81,-d*.80,"Shadowed nacelle steel"),v(.85,ex*1.155,-d,"Exhaust patina bronze"),
            v(.99,ex,-d*1.15,"Dark intake"),v(1.,ex*.79,-d*1.15,"Warm burner rivets"),
            v(.91,ex*.697,-d,"Dark intake"),v(.28,r*.594,-d*.16,"Dark intake"),
            v(.024,r*.702,0,"Shadowed nacelle steel")),"Exhaust patina bronze")
    lateral,lead,end,h,r,ex=q.motor
    for s in (-1,1):
        nacelle("Through-bore lateral turbofan with real lip, fan and tapered nozzle",(s*lateral,lead,end,h,r,ex))
        if q.dorsal:
            z=(h+q.wing[5]+.050)*.5
            B("Integrated underwing engine pylon and cooling fairing",(s*lateral,(lead+end)*.5-.016,z),
              (.062,(lead-end)*.65,max(.032,q.wing[5]+.089-h)),"Shadowed nacelle steel",.013,(0,0,s*.079))
        else:
            B("Airframe-rooted swept rear nacelle stub",(s*lateral*.77,(lead+end)*.5-.032,h-.008),
              (.131,(lead-end)*.60,.050),"Skinned wing alloy",.014,(0,0,-s*.173))
        C("Threaded turbine case drain",(s*lateral,end+.042,h-ex*.75),(s*lateral,end+.014,h-ex*.81),
          .0037,.0019,"Warm burner rivets",7)
    if q.dorsal:
        x,y,tail,z,r,c=q.dorsal
        nacelle("Independent third inlet through swept dorsal fan nacelle",(x,y,tail,z,r,c),True)
        B("Integral dorsal nacelle saddle above pressure bulkhead",(0,(y+tail)*.5+.02,z-r*.86),
          (.114,(y-tail)*.76,.061),"Blue taper",.012,(.082,0,0))
        # Low roots touch the plume-free outer capsule without penetrating the central fan bore.
        for s in (-1,1):
            C("Brushed annulus fairing along dorsal engine side",(s*r*.79,y-.095,z-r*.473),
              (s*c*.67,tail+.071,z-c*.44),.021,.007,"Skinned wing alloy",9)

def undercarriage(q,extended):
    native.gear(q,extended)
    if not q.tips: return
    # The late trijet's individually modeled center gear is shorter than
    # the primary four-wheel bogies, with a separate bay and two wheels.
    y=-.400
    h=q.fuselage[3]-q.fuselage[5]+.021
    r=.045
    if not extended:
        B("Flush center gear bay doors",(0,y,h),(.067,.116,.012),"Shadowed flap",.004)
        C("Distinct centerline gear door seal",(0,y-.054,h-.007),(0,y+.054,h-.007),
          .0017,.0017,"Rib inset",7)
        return
    B("Open center bogie bay",(0,y,h),(.067,.115,.014),"Well shadow",.004)
    for s in (-1,1):
        B("Open independent center gear door",(s*.032,y,h-.016),(.007,.113,.032),"Shadowed flap",.002,
          (0,s*.407,0))
    C("Center gear physical telescoping strut",(0,y,r),(0,y-.013,h+.022),
      .010,.013,"Landing gear chrome",12)
    C("Center gear brake axle crossing both hubs",(-.035,y,r),(.035,y,r),.005,.005,"Landing gear chrome",10)
    for s in (-1,1):
        xc=s*.019
        vs=[(x,y+r*cos(-pi/2+i*tau/20),r+r*sin(-pi/2+i*tau/20)) for x in (xc-.006,xc+.006) for i in range(20)]
        fs=[tuple(range(20))[::-1],tuple(range(20,40))]+[(i,(i+1)%20,(i+1)%20+20,i+20) for i in range(20)]
        art.close_mesh("Center gear tire exactly at runway datum",vs,fs,["Dull tire"]*2+["Road contact tread"]*20)
        C("Machined exposed center wheel hub",(xc+s*.004,y,r),(xc+s*.008,y,r),
          .022,.016,"Landing gear chrome",12)

def make(q):
    colors=art.PAL|dict(zip(COLORS,q.livery))
    base.PALETTE,base.KEYS=colors,list(colors)
    base.begin()
    bpy.context.preferences.filepaths.save_version=0
    e.export_atlas(q.stem,colors)
    scene=bpy.context.scene
    scene.name=f"LuanTTD | {q.name} · #{q.id}"
    scene["stock_source"]=f"OpenTTD 16.0-RC1 src/table/engines.h #{q.id}, stock {'AIR_CTOL' if q.id==221 else 'AIR_CTOL | AIR_FAST'}"
    scene["original_art"]=q.description+"; original Blender meshes and livery; no external image assets"
    scene["native"]="Nose −Z/game Y up. Ground tires touch Y=0; open/closed undercarriage collections export separately."
    def group(name,draw):
        before=set(scene.objects)
        draw()
        return art.new_collection(scene,name,[obj for obj in scene.objects if obj not in before])
    common=[]
    for name,draw in (("01 · Editable fuselage, windscreen, livery and glazing",body),
                      ("02 · Port and starboard wings, tail and control surfaces",surfaces),
                      ("03 · Individual open fan engine assemblies",propulsion)):
        common.extend(group(name,lambda:draw(q)).objects)
    taxi=group("04 · Deployed landing gear, brake assemblies and wheel bays",lambda:undercarriage(q,True))
    flight=group("05 · Gear-up closed aerodynamic bay doors",lambda:undercarriage(q,False))
    for o in flight.objects:
        o.hide_viewport=True
        o.hide_render=True
    def prepare_stage():
        B("Review concrete slab (not exported)",(0,0,-.041),(6,6,.080),"Studio slab",.005)
        for i in (-2,-1,0,1,2):
            B("Apron expansion join",(i,0,-.0003),(.006,6,.0002),"Studio join")
            B("Apron expansion join",(0,i,-.0003),(6,.006,.0002),"Studio join")
        for name,at in (("Apron",(2.9,3.4,1.84)),("Ventral",(2.7,-3.2,-1.60))):
            bpy.ops.object.camera_add(location=at)
            cam=bpy.context.object
            cam.name=name
            cam.data.type="ORTHO"
            cam.data.ortho_scale=2.85
            cam.rotation_euler=(Vector((0,0,.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    studio=group("90 · Optional look-development stage, not exported",prepare_stage)
    scene.camera=next(o for o in studio.objects if o.name=="Apron")
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1080,740
    scene.render.resolution_percentage=100
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.light="STUDIO"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.28
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=Vector((0,0,.25))
                view.region_3d.view_distance=3.0
                view.region_3d.view_rotation=Vector((1,1.20,.63)).to_track_quat("Z","Y")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/stock_{q.stem}.blend"),compress=True)
    native.write_native(q,scene,common+list(taxi.objects),"ground",colors)
    for o in flight.objects:
        o.hide_viewport=False
        o.hide_render=False
    native.write_native(q,scene,common+list(flight.objects),"flight",colors)
    if dest:=os.getenv("BAKEWELL_REVIEW"):
        Path(dest).mkdir(parents=True,exist_ok=True)
        scene.render.image_settings.file_format="JPEG"
        for pose in ("Apron","Ventral"):
            underside=pose=="Ventral"
            scene.camera=next(o for o in studio.objects if o.name==pose)
            for o in studio.objects:
                if o.type=="MESH": o.hide_render=underside
            for o in taxi.objects: o.hide_render=underside
            for o in flight.objects: o.hide_render=not underside
            scene.render.filepath=str(Path(dest)/f"{q.stem}-{pose.lower()}.jpg")
            bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    subset=set(map(int,os.getenv("BAKEWELL_IDS","").split()))
    for model in FRAMES:
        if not subset or model.id in subset: make(model)
