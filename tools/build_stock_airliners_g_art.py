#!/usr/bin/env python3
"""Original RC1 #220 LB-8 / #228 Darwin 300, source shape and 3D texture palette."""
from math import cos,sin,tau,pi,sqrt
from pathlib import Path
import os,sys
import bpy
from mathutils import Vector as V
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_airliners_e_art as e

base,art=e.base,e.art
M,B,C=art.M,e.B,art.C
P=dict()
lb8=e.Shape("bakewell_luckett_lb8","Bakewell Luckett LB-8",220,
    "Original DC-8-era four slim turbojets; low first generation cabin and tailplane.",
    {"Crown ivory":"eeeae0","Panel ivory":"dbe9e6","Lit blue":"527d9e",
     "Dark coastal cobalt":"2b516e","Blue taper":"427398","Copper pinstripe":"ac6649",
     "Silver pressure hull":"c0c8cb","Bellying brushed alloy":"8e9ba0","Rib inset":"626a6e"},
    ((-.997,.006,.206,.008,.006),(-.974,.024,.208,.029,.017),(-.928,.048,.210,.052,.037),
     (-.855,.077,.213,.073,.060),(-.743,.106,.214,.102,.080),(-.600,.128,.214,.116,.099),
     (-.416,.135,.213,.121,.102),(.383,.135,.212,.121,.101),(.534,.132,.213,.119,.100),
     (.682,.122,.216,.109,.087),(.786,.103,.215,.094,.067),(.873,.080,.208,.078,.052),
     (.940,.055,.201,.056,.038),(.982,.024,.192,.030,.021),(1.008,.004,.190,.007,.005)),
    ((.104,.264,-.416,.183,.080),(.211,.220,-.407,.187,.072),(.365,.145,-.406,.197,.059),
      (.503,.042,-.400,.213,.040),(.665,-.066,-.399,.226,.028),(.823,-.205,-.400,.241,.013),(.896,-.260,-.393,.247,.006)),
    ((.018,-.634,-.964,.272,.039),(.105,-.658,-.970,.280,.034),(.207,-.724,-.963,.291,.026),
      (.295,-.792,-.966,.304,.015),(.346,-.827,-.956,.310,.007)),
    ((.012,.254,-.563,-.966),(.033,.296,-.620,-.972),(.037,.368,-.698,-.973),
       (.035,.457,-.750,-.971),(.026,.521,-.807,-.962),(.019,.572,-.847,-.941),(.009,.589,-.872,-.936)),
    (0,0,0,0,0),.0,
    ((-.228,-.154,.052,.022,.159),(.228,-.154,.052,.022,.159),(0,.698,.035,.015,.126)),
    (24,.663,.046,.251,"square"),((.739,.239,.030),(-.564,.243,.029),(-.107,.251,.020)))
d300=e.Shape("darwin_300","Darwin 300",228,
    "Original first-generation jumbo interpretation: integrated stepped upper deck, four broad turbofans, low tailplane.",
    {"Crown ivory":"d9e5e3","Panel ivory":"bbd6dc","Lit blue":"5293af",
     "Dark coastal cobalt":"2b5e81","Blue taper":"3a6d91","Copper pinstripe":"caab66","Silver pressure hull":"9cbbcc",
     "Bellying brushed alloy":"74939e","Rib inset":"516a76","Wing leading trim":"d4dedd","Shadowed nacelle steel":"6e8792"},
    ((-1.080,.006,.247,.008,.007),(-1.049,.027,.248,.026,.021),(-.998,.052,.250,.048,.043),
      (-.927,.087,.254,.069,.064),(-.840,.123,.255,.102,.099),(-.730,.161,.255,.132,.121),
      (-.566,.180,.254,.153,.133),(-.370,.185,.254,.157,.139),(.236,.185,.255,.157,.140),
      (.355,.185,.256,.168,.139),(.465,.185,.257,.210,.137),(.571,.181,.257,.251,.132),
      (.667,.177,.257,.264,.126),(.755,.165,.255,.260,.113),(.836,.145,.251,.234,.099),
      (.915,.113,.246,.189,.083),(.981,.085,.239,.144,.064),(1.045,.050,.234,.090,.038),
      (1.073,.023,.229,.043,.020),(1.088,.007,.227,.013,.007)),
    ((.130,.359,-.504,.188,.115),(.228,.317,-.492,.192,.098),(.384,.209,-.495,.204,.074),
     (.543,.089,-.491,.220,.054),(.689,-.026,-.488,.235,.037),(.838,-.151,-.485,.254,.021),
     (.913,-.216,-.461,.264,.011),(.941,-.244,-.442,.270,.006)),
    ((.024,-.661,-1.053,.293,.046),(.120,-.697,-1.055,.296,.039),(.221,-.757,-1.055,.312,.031),
      (.332,-.830,-1.043,.330,.017),(.404,-.883,-1.021,.339,.009)),
    ((.014,.306,-.498,-1.041),(.049,.360,-.548,-1.055),(.047,.443,-.635,-1.055),
      (.040,.523,-.719,-1.045),(.032,.596,-.793,-1.035),(.021,.651,-.844,-1.024),(.013,.682,-.889,-1.004)),
    (0,0,0,0,0),0,
    ((-.390,-.195,.046,.019,.185),(.390,-.195,.046,.019,.185),
     (-.164,-.332,.046,.019,.124),(.164,-.332,.046,.019,.124),(0,.743,.036,.017,.135)),
    (28,.813,.0564,.307,"square"),((.884,.290,.032),(.470,.302,.027),(-.192,.305,.025),(-.617,.302,.031)))
# author yaw +Y is forward. Each tuple = side spread, fore lip, aft nozzle,
# pylon axis height, outer thickness, exit thickness. Distinct profiles.
PODS={
  220:((.294,.233,-.270,.133,.051,.045),(.566,.015,-.373,.158,.046,.039)),
  228:((.339,.238,-.217,.127,.071,.060),(.666,-.030,-.374,.161,.065,.052))}
COCKPIT={220:(.784,.910,.42),228:(.884,1.030,.45)}
def hull(q):
    n=48
    ang=[tau*j/n for j in range(n)]
    inks=[]
    hump=q.engine==228
    for t in ang:
        c=sin(t+pi/n)
        inks.append("Crown ivory" if c>.85 else "Panel ivory" if c>.67 else "Lit blue" if c>.36 else
                    "Dark coastal cobalt" if c>.23 else "Copper pinstripe" if -.09<c<.02 else
                    "Silver pressure hull" if c>-.70 else "Bellying brushed alloy")
    art.sections("Continuous wide pressure shell with integral forward upper deck" if hump else
                 "Original continuous slim rolled aluminum pressure shell",
        [(y,[(w*cos(t),b+(top if sin(t)>0 else bottom)*sin(t)) for t in ang])
         for y,w,b,top,bottom in q.fuselage],"Silver pressure hull",inks)
    def surface(side,y,h,depth=.003):
        w,b,top,bottom=e.interp(q.fuselage,y)
        t=(h-b)/(top if h>=b else bottom)
        if abs(t)>=1:raise ValueError((q.stem,y,h,t))
        return (side*(w*sqrt(1-t*t)+depth),y,h)
    def decal(name,mat,s,y,h,a,b,depth=.004,edge=False):
        z=((-1,-.50),(-.58,-1),(.58,-1),(1,-.50),(1,.50),(.58,1),(-.58,1),(-1,.50))
        if edge:
            f=[(j,(j+1)%8,(j+1)%8+8,j+8)[::s] for j in range(8)]
            fac=(1.,.90)
        else:
            f=[tuple(range(8))[::s]];fac=(1.,)
        v=[surface(s,y+a*u*k,h+b*w*k,depth) for k in fac for u,w in z]
        return M(name,v,f,mat)
    count,first,interval,h,_=q.window
    for s in (-1,1):
        for i in range(count):
            y=first-i*interval-.012*(i>=9)-.013*(i>=17)
            if i in (2,8,16,25):continue
            decal("Individual pressure frame cabin window bezel","Aluminium bezel",s,y,h,.015,.015,.003)
            decal("Separate single level cabin windows glazing","Cab glass",s,y,h,.011,.0108,.0046)
            decal("Small highlight in conforming cabin pane","Window glint",s,y-.002,h+.004,.0044,.0014,.0061)
        for y,h,w in q.doors:
            a=.051 if w>=.025 else .029
            decal("Stowed anti-slip folding passenger cabin door seam","Pressure door seal",s,y,h,w,a,.0046,True)
            decal("Passenger entry door small peephole","Cab glass",s,y+.003,h+.014,.010,.012,.0069)
            decal("Passenger entry door flush metal grip","Rib inset",s,y-.009,h-.007,.008,.0025,.0076)
        for y in (-.489,.432):
            decal("Independent belly cargo offload hatch moulding","Pressure door seal",s,y,.176,.046,.024,.0079,True)
            decal("Belly cargo hatch metal handle","Rib inset",s,y,.174,.019,.0023,.0087)
        if hump:
            for n in range(7):
                y=.773-n*.043
                decal("Forward independent second-deck cabin pane upper bevel",
                      "Aluminium bezel",s,y,.430,.012,.012,.0049)
                decal("Genuine upper deck window row for early jumbo","Cab glass",s,y,.430,.0099,.010,.0067)
        lo,hi,breadth=COCKPIT[q.engine]
        # Multiple curved independently partitioned cockpit glass sections
        # on the actual upper pressure shell, not a painted sticker.
        def cockpit(key,c,a,b,f,g,lift):
            v=[]
            for j in range(10):
                y=a+(b-a)*j/9
                w,z,top,_=e.interp(q.fuselage,y)
                for i in range(7):
                    u=f+(g-f)*i/6+(i/6-.5)*j*.016
                    v.append((s*w*u,y,z+top*sqrt(1-u*u)+lift))
            faces=[(j*7+i,j*7+i+1,(j+1)*7+i+1,(j+1)*7+i)[::s] for j in range(9) for i in range(6)]
            return M(key,v,faces,c)
        cockpit("Dark pressure-forged pilot windshield seating","Glazing bezel",lo,hi,.102,.890,.0038)
        cockpit("Forward pilot window glazed conforming shell","Cab glass",lo+.007,hi-.008,.151,.818,.0053)
        cockpit("Early eye-line reflection in repeated front surfaces","Window glint",lo+.027,lo+.048,.24,.58,.0071)
        for u in (.35,.637):
            def p(y):
                w,b,t,_=e.interp(q.fuselage,y);return (s*w*u,y,b+t*sqrt(1-u*u)+.0085)
            C("Independent cockpit structural intermediate mullion",p(lo+.011),p(hi-.011),.0029,.0022,"Glazing bezel",7)
    h=.316 if q.engine==220 else .408
    B("Tuned roof communication dorsal fin behind pressure crest",(0,.317,h),(.018,.074,.030),"Aluminium bezel",.007)
    B("Underside short antenna on commercial transport",(0,.370,.098),(.014,.061,.023),"Rib inset",.004)

def jets(q):
    era=q.engine==220
    for s in (-1,1):
        for ax,a,b,h,r,t in PODS[q.engine]:
            x=s*ax
            def k(v,rad,dy,c):return a+(b-a)*v,rad,h+dy,c
            sections=(k(0,r*.88,0,"Wing leading trim"),k(.062,r,0,"Skinned wing alloy"),
                k(.26,r*.99,-.003,"Silver pressure hull"),
                k(.49,(t+r)*.50,-.005,"Lit blue" if not era else "Silver pressure hull"),
                k(.64,t*.97,-.009,"Shadowed nacelle steel"),
                k(.83,t*.86,-.011,"Exhaust patina bronze"),
                k(1.,t*.68,-.012,"Dark intake"),k(.994,t*.54,-.012,"Warm burner rivets"),
                k(.86,t*.45,-.012,"Dark intake"),k(.17,r*.79,-.001,"Dark intake"),
                k(.018,r*.706,0,"Shadowed nacelle steel"))
            art.turbojet("LB-8 one of four true early distinct long turbojets" if era else
                         "Darwin 300 one of four open late high-bypass turbines",x,sections,"Exhaust patina bronze")
            # Connect from the nacelle top into the actual shaped wing's
            # underside, never the top. No rectangular bumps on lifting skin.
            leg,trailing,center,thick=e.interp(q.wing,ax)
            bottom=min(h+r*.81,center-.017)
            top=center+.010
            mount=a*.36+b*.64
            B("Real cantilever underwing engine pylon and mounts",
              (x,mount,(bottom+top)/2),(.040 if era else .065,.127 if era else .167,top-bottom),
              "Shadowed nacelle steel",.011,(0,0,-s*.10))
            B("Clean shallow pylons near the wing leading edge",
              (x,mount+.046,(top+bottom)/2-.004),(.055 if era else .076,.086 if era else .105,top-bottom-.008),
              "Silver pressure hull",.007,(0,0,-s*.10))
            for f in (.29,.61):
                y=a+(b-a)*f
                C("Inline separate engine fire system seam hull housing",
                  (x+s*r*.88,y,h+.019),(x+s*r*.80,y-.032,h+.029),.004,.003,"Rib inset",10)

def gear(q):
    if q.engine==220:
        legs=q.gear
    else:
        # Four individual 4-wheel sets (two axles each), one nose dual.
        legs=tuple((x,y+d,r,w,mount) for x,y,r,w,mount in q.gear[:-1] for d in (-.047,.047))+(q.gear[-1],)
    for x,y,r,w,mount in legs:
        B("Underbody deep retracted bay case work",(x,y,mount+.018),(w*3.6,r*1.87,.040),
           "Silver pressure hull",.012)
        B("Wheel-well dark recessed roof shadow",(x,y,mount+.005),(w*4.7,r*2.4,.014),"Well shadow",.005)
        for s in (-1,1):
            B("Operable-looking separated suspended gear bay door",(x+s*w*2.10,y,mount-.010),
              (.007,r*2.22,.042),"Shadowed flap",.003,(0,-s*.26,0))
        C("Bright honed steel structural primary oleo",(x,y,r),(x,y-.011,mount+.021),
          .009,.013,"Landing gear chrome",11)
        C("Real aircraft wheel and forged link on lower u-joint",(x,y+.011,r+.004),
          (x,y+.045,mount+.005),.0045,.007,"Fan deep metal",9)
        C("Solid axle passes both tire hubs",(x-w*1.51,y,r),(x+w*1.51,y,r),.007,.007,"Landing gear chrome",12)
        if q.engine==228 and x:
            C("Longitudinal articulated main bogie undercarriage side beam",
              (x,y-.041,r+.009),(x,y+.043,r+.019),.008,.008,"Shadowed flap",9)
        for s in (-1,1):
            xx=x+s*w*.786;n=20
            ang=[-pi/2+j*tau/n for j in range(n)]
            pts=[(u,y+r*cos(t),r+r*sin(t)) for u in (xx-w*.5,xx+w*.5) for t in ang]
            fs=[tuple(range(n))[::-1],tuple(range(n,n*2))]
            fs.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
            art.close_mesh("Independent runway contact tire at exact native datum",pts,fs,["Dull tire"]*2+["Road contact tread"]*n)
            C("Independent sunlit forged wheel rim",(xx+s*w*.49,y,r),(xx+s*w*.56,y,r),r*.48,r*.41,"Landing gear chrome",13)
            C("Recessed central machined hub aperture",(xx+s*w*.56,y,r),(xx+s*w*.60,y,r),
               r*.19,r*.16,"Fan deep metal",10)

def make(q):
    pal=art.PAL|q.palette
    base.PALETTE=pal;base.KEYS=list(pal)
    assert len(pal)==32
    e.ROOT=ROOT;e.export_atlas(q.stem,pal)
    base.begin()
    scene=bpy.context.scene;scene.name=f"LuanTTD | #{q.engine} {q.title}"
    scene["source"]=f"OpenTTD 16.0-RC1 #{q.engine}; original geometry; fast CTOL stock direction-only sprite"
    scene["native_pose"]="Scale 1.0, local nose -Z, wheels Y=0 in native model. In Blender, nose +Y."
    for i,(title,fn) in enumerate((("Pressure hull, cockpit and separate doors",hull),
                                   ("Sweep and low rear stabilizer bank",e.wings),
                                   ("Independent underwing open inlet engine pods",jets),("Grounded wheeled gear and bays",gear)),1):
        before=set(scene.objects);fn(q)
        art.new_collection(scene,f"{i:02} | {title}",[o for o in scene.objects if o not in before])
    raw=list(scene.objects)
    camera=bpy.data.cameras.new("Jet profile");cam=bpy.data.objects.new("Jet profile",camera)
    scene.collection.objects.link(cam);scene.camera=cam;camera.type="ORTHO";camera.ortho_scale=2.70
    cam.location=(3.1,3.3,1.95);cam.rotation_euler=(V((0,0,.24))-cam.location).to_track_quat("-Z","Y").to_euler()
    scene.world=bpy.data.worlds.new("Jet apron sky");scene.world.color=(.12,.18,.22)
    scene.render.engine="BLENDER_WORKBENCH"
    sh=scene.display.shading;sh.light="STUDIO";sh.color_type="MATERIAL";sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type="BOTH"
    sh.background_type="WORLD";scene.view_settings.view_transform="Standard";scene.view_settings.exposure=.33
    for a in (a for screen in bpy.data.screens for a in screen.areas if a.type=="VIEW_3D"):
        v=a.spaces.active;v.shading.color_type="MATERIAL";v.region_3d.view_location=V((0,0,.23))
        v.region_3d.view_distance=3.05;v.region_3d.view_rotation=V((.85,1.,.52)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/stock_{q.stem}.blend"),compress=True)
    copies=[]
    for o in raw:
        x=o.copy();x.data=o.data.copy();scene.collection.objects.link(x);copies.append(x)
    bpy.context.view_layer.update()
    ob=art.merge(copies);ob.name=f"Stock_{q.stem}_{q.engine}"
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new();uv.active_render=True
    for p in ob.data.polygons:
        i=base.KEYS.index(ob.data.materials[p.material_index].name)
        for k in p.loop_indices:uv.data[k].uv=((i+.5)/len(pal),.5)
    target=ROOT/f"mods/luanttd_core/models/bl_stock_{q.stem}.obj"
    bpy.ops.wm.obj_export(filepath=str(target),export_selected_objects=True,export_materials=False,export_uv=True,
        export_normals=True,export_triangulated_mesh=False,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")
    art.compact_obj(target)
    bpy.data.objects.remove(ob,do_unlink=True)
    if dest:=os.getenv("AIR_G_REVIEW"):
        scene.render.image_settings.file_format="JPEG";scene.render.resolution_x=1040;scene.render.resolution_y=740
        scene.render.resolution_percentage=100
        B("Review apron not part of production mesh",(0,0,-.042),(12,12,.083),"Studio slab",.009)
        apron=bpy.context.object
        for tag,xyz in (("front",(3.1,3.3,1.95)),("side",(-3.4,1.1,1.76)),("ventral",(2.9,-2.9,-1.4))):
            cam.location=xyz;cam.rotation_euler=(V((0,0,.24))-cam.location).to_track_quat("-Z","Y").to_euler()
            if apron:apron.hide_render=tag=="ventral"
            sh.show_shadows=tag=="front"
            scene.render.filepath=str(Path(dest)/f"{q.stem}-{tag}.jpg")
            bpy.ops.render.render(write_still=True)
if __name__=="__main__":
    requested=os.environ.get("AIR_G_STEM")
    for q in (lb8,d300):
        if not requested or requested==q.stem:make(q)
