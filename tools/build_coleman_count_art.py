"""Original native Coleman Count (OpenTTD 14.1 stock small aircraft #216).
Blender: +Y nose, +Z up. Native OBJ: -Z nose, +Y up, ten export units/node.
Set COLEMAN_REVIEW=/path/coleman.png for a workbench apron portrait.
"""
from math import cos, pi, sin
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V
import build_bayshore_trimotor_art as T

ROOT=V.ROOT
B,C,M=V.bevel_box,V.round_between,V.add_mesh
STEM="bl_coleman_count"
PALETTE={
    "porcelain white":"eeeade", "ivory side":"dfded2", "silver top":"afbec2",
    "satin bare alloy":"9daeb4", "low alloy":"788e9b", "spar alloy":"879aa4",
    "deck blue":"4688af", "blue highlight":"6ea9c9", "regulated navy":"2c4c68",
    "border ink":"1f3b51", "windshield":"293f4e", "glass haze":"668c9e",
    "glass rebate":"334956", "silver rim":"c3c5b8",
    "turbine gray":"425259", "exhaust finish":"55575a", "heat bronze":"79695a",
    "steel blade":"495053", "blade back":"5e6870", "sand tips":"f5c572",
    "tyre side":"232c34", "tread rubber":"303a40", "wheel hub":"a0a9a7",
    "gear hydraulic":"687b82", "gear recess":"26343a",
    "port red":"be473e", "starboard jade":"4c8c74", "bright light":"f5edcb",
    "fin band":"c3e3ef", "concrete":"737b7d", "apron joint":"303f44", "grass":"697f61",
}
KEYS=tuple(PALETTE)
FUSELAGE=(
    (-.875,.020,.340,.371,.397),(-.822,.051,.302,.375,.435),(-.739,.077,.274,.387,.471),
    (-.620,.110,.250,.407,.500),(-.490,.145,.237,.436,.531),(-.305,.161,.219,.449,.550),
    (-.070,.165,.214,.451,.554),(.205,.165,.216,.451,.554),(.407,.160,.223,.445,.552),
    (.514,.147,.239,.443,.541),(.598,.128,.257,.425,.521),(.669,.108,.271,.400,.480),
    (.719,.083,.292,.374,.432),(.762,.044,.313,.361,.396),(.776,.015,.335,.358,.375),
)
WING=(
    (.069,.289,-.344,.258,.103),(.221,.243,-.362,.255,.103),
    (.414,.180,-.354,.269,.084),(.645,.092,-.328,.312,.059),
    (.796,.026,-.277,.354,.041),(.886,-.041,-.231,.374,.029),
    (.936,-.082,-.199,.382,.015),(.950,-.108,-.165,.384,.007),
)


def rod(name,a,b,r,mat,n=8):
    return C(name,a,b,r,r,mat,n)


def lerp_profile(y):
    for a,b in zip(FUSELAGE,FUSELAGE[1:]):
        if a[0]<=y<=b[0]:
            t=(y-a[0])/(b[0]-a[0])
            return tuple((1-t)*x+t*z for x,z in zip(a[1:],b[1:]))
    raise ValueError(y)


def contour(w,z,s,t):
    # Smooth cylindrical pressurized tube. Blue cheatline is an actual
    # band of the same external shell, not a sprite applied to a cube.
    band=max(z+.055,s-.102)
    low=min(band-.021,z+.085)
    return [(-w*.59,z+.007),(-w*.31,z),(0,z),(w*.31,z),(w*.59,z+.007),
        (w*.81,z+.025),(w*.94,low),(w*.999,band),(w,s),(w*.926,s+.036),
        (w*.75,t-.028),(w*.46,t-.005),(0,t),(-w*.46,t-.005),
        (-w*.75,t-.028),(-w*.926,s+.036),(-w,s),(-w*.999,band),(-w*.94,low),
        (-w*.81,z+.025)]


def body():
    outer=V.profile_hull("Pressurized tapering Coleman cylindrical alloy fuselage",
      [(y,contour(w,l,m,h)) for y,w,l,m,h in FUSELAGE],"porcelain white",
      ["satin bare alloy"]*5+["silver top","regulated navy","deck blue","blue highlight"]+
      ["porcelain white"]*6+["blue highlight","deck blue","regulated navy","silver top","satin bare alloy"])
    # Deep oval Viscount-style window assemblies follow the actual shell taper.
    for side in (-1,1):
        for y in (-.445,-.351,-.260,-.169,-.078,.014,.105,.197,.283,.369):
            w,l,s,h=lerp_profile(y)
            x=side*(w-.002)
            z=s-.037
            C("Raised oval passenger window sill",(x,y,z),(x+side*.008,y,z),
              .035,.031,"silver rim",16)
            # Cylindrical ends are compressed along longitudinal axis only.
            for name,r,off,mat in (
              ("Oval cabin pressure-glass rebate",.027,.010,"glass rebate"),
              ("Oval passenger pressure glazing",.021,.014,"windshield"),
            ):
                vv=[]
                for dx in (0,side*.003):
                    vv.extend((x+side*off+dx,y+.84*r*cos(a*2*pi/18),
                               z+1.23*r*sin(a*2*pi/18)) for a in range(18))
                n=18
                ff=[tuple(range(n)),tuple(reversed(range(n,n*2)))]
                ff.extend((j,n+j,n+(j+1)%n,(j+1)%n) for j in range(n))
                if side<0:ff=[tuple(reversed(f)) for f in ff]
                M(name,vv,ff,mat)
            rod("Glazing restrained sky return",(x+side*.018,y-.012,z+.016),
               (x+side*.018,y+.008,z+.021),.0027,"glass haze",7)
        for yy,zz in ((.471,.373),(-.532,.359)):
            w,low,s,h=lerp_profile(yy)
            ang=side*(.12 if yy>0 else -.17)
            B("Full-height retractable door pressed seal",(side*(w+.004),yy,zz),
              (.017,.063,.158),"border ink",.009,(0,0,ang))
            B("Pressure cabin door with rolled aluminium face",(side*(w+.010),yy,zz),
              (.010,.053,.146),"ivory side",.006,(0,0,ang))
            rod("Outside miniature handle",(side*(w+.019),yy-.018,zz-.016),
                (side*(w+.019),yy+.012,zz-.015),.0036,"regulated navy",7)
        V.typeface("Raised Coleman local service name","COLEMAN",(side*.161,.274,.479),
                   .029,side*pi/2,"regulated navy")
        # Tiny pitot tube, radio whip and double rear vent, art only.
        rod("Outside pitot tube",(side*.066,.724,.346),(side*.078,.743,.356),.004,"low alloy")
        rod("Cabin ventilation exit",(side*.130,-.501,.288),(side*.128,-.541,.287),.006,"exhaust finish")

    # Contour projecting onto the real pressure shell leaves neither glazing
    # gaps nor phantom flat window planes crossing the curved nose. Raycast
    # against named source faces for this one detached little skin assembly.
    bvh=BVHTree.FromPolygons([v.co for v in outer.data.vertices],
        [tuple(p.vertices) for p in outer.data.polygons])

    def apron_panel(label,quad,axis,side,offset,mat):
        # Subdivide the subtle curved sheets at nearly every panel seam: the
        # mapped glass conforms to the existing exterior without disturbing it.
        m=8
        verts=[]
        for j in range(m+1):
            t=j/m
            for k in range(m+1):
                p=k/m
                a,b,c,d=(Vector(pair) for pair in quad)
                u,h=(1-t)*((1-p)*a+p*b)+t*((1-p)*d+p*c)
                start=(u,1.15,h) if axis==1 else (side*1.10,u,h)
                aim=(0,-1,0) if axis==1 else (-side,0,0)
                xyz,normal,index,_=bvh.ray_cast(start,aim)
                if xyz is None:
                    raise RuntimeError(f"Misplaced Coleman glazing {label}, {start}")
                xyz[axis]+=side*offset
                verts.append(xyz)
        n=m+1
        ff=[(j*n+k,j*n+k+1,(j+1)*n+k+1,(j+1)*n+k)
          for j in range(m) for k in range(m)]
        if axis==1 or side<0:
            ff=[tuple(reversed(f)) for f in ff]
        M(label,verts,ff,mat)

    for side in (-1,1):
        # X/Z forward outline, then Y/Z side windows, each on the real shell.
        # Left-hand quad must still run in ascending world X.
        quad=tuple((side*x,z) for x,z in ((.009,.434),(.086,.425),(.088,.487),(.012,.504)))
        if side<0:
            quad=(quad[1],quad[0],quad[3],quad[2])
        apron_panel("Sculpted panoramic windshield frame",quad,1,1,.0048,"regulated navy")
        ctr=sum((Vector(p) for p in quad),Vector((0,0)))/4
        inner=[ctr+.84*(Vector(p)-ctr) for p in quad]
        apron_panel("Curved front pilot glazing",inner,1,1,.0076,"windshield")
        c,d=inner[2:]
        ab=inner[1]-c
        apron_panel("Soft glass sky highlight",(d+Vector((0,-.010)),c+ab*.16,c+ab*.07,d+Vector((0,-.004))),1,1,.0092,"glass haze")
        for quad in (
            ((.535,.441),(.594,.435),(.604,.474),(.542,.485)),
            ((.609,.434),(.652,.429),(.662,.462),(.614,.473)),
        ):
            apron_panel("Rounded side pressure cockpit frame",quad,0,side,.006,"glass rebate")
            ctr=sum((Vector(p) for p in quad),Vector((0,0)))/4
            apron_panel("Rounded side pressure cockpit glazing",
                [ctr+.81*(Vector(p)-ctr) for p in quad],0,side,.009,"windshield")
    rod("Tiny flat blade radio antenna",(0,.356,.553),(0,.337,.595),.004,"low alloy",6)
    for s in (-1,1):
        rod("Pitot mount below radome",(s*.034,.748,.348),(s*.022,.775,.351),.002,"spar alloy",6)


def airframe():
    for side in (-1,1):
        T.wing_shell(side,WING,"Tapered postwar silver wing","silver top",False)
        # Swept flap and aileron hinge are actual gently changing foil
        # veneers; no embellishment to the below-wing collision envelope.
        flap=((.146,-.227,-.349,.285,.031),(.454,-.236,-.344,.284,.025),
              (.644,-.251,-.324,.319,.011))
        T.wing_shell(side,flap,"Cupped inner Fowler flaps","satin bare alloy",False)
        aileron=((.614,-.231,-.335,.316,.036),(.756,-.199,-.293,.346,.030),
                 (.866,-.173,-.242,.372,.018),(.929,-.151,-.199,.383,.010))
        T.wing_shell(side,aileron,"Balanced outer alloy aileron","spar alloy",False)
        rod("Outboard narrow hinge line",(side*.645,-.246,.325),
          (side*.867,-.172,.377),.0029,"low alloy",6)
        for j,x in enumerate((.252,.444,.582)):
            rod("Machined set-in flap hinge bearing",(side*x,-.294,.256+.025*j),
                (side*x,-.355,.247+.024*j),.007,"low alloy",6)
        B("Transparent port or starboard tip lens",(side*.939,-.111,.388),
          (.036,.044,.020),"port red" if side<0 else "starboard jade",.006)
        B("Upper silver fairing on wing tip light",(side*.937,-.122,.402),
          (.029,.032,.010),"silver rim",.004)
        B("Inset bright edge of landing light",(side*.617,.116,.317),
          (.067,.025,.028),"bright light",.007,(0,0,-side*.31))
        T.wing_shell(side,((.017,-.548,-.843,.385,.046),
              (.178,-.593,-.868,.398,.035),(.270,-.659,-.869,.410,.026),
              (.345,-.736,-.864,.423,.012),(.358,-.767,-.839,.427,.007)),
              "Silver horizontal stabilizer and elevator","silver top",False)
        rod("Tailplane rib and elevator hinge",(side*.069,-.736,.405),
            (side*.351,-.815,.427),.0032,"spar alloy",6)
    profile=[(-.470,.515),(-.561,.541),(-.665,.587),(-.776,.681),
             (-.833,.681),(-.867,.618),(-.877,.394),(-.731,.420),(-.586,.474)]
    points=[(side*(.039-(h-.39)*.079),y,h) for side in (-1,1) for y,h in profile]
    n=len(profile)
    faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
    faces += [(k,n+k,n+(k+1)%n,(k+1)%n) for k in range(n)]
    M("Blue swept dorsal fin with all-metal rudder",points,faces,"deck blue")
    for side in (-1,1):
        for y,h,dx,mat in ((-.763,.583,.069,"fin band"),(-.776,.563,.070,"porcelain white"),
          (-.787,.545,.064,"fin band")):
            B("Original sweeping fin identification bar",(side*(.040-(h-.39)*.077),y,h),
              (.006,dx,.011),mat,.003,(.50,0,0))
        rod("True rudder bearing seam",(side*.012,-.842,.624),
            (side*.038,-.848,.415),.003,"regulated navy",7)
    B("Tail navigation lens",(0,-.876,.374),(.028,.022,.014),"bright light",.005)


def nacelle(half,x,y,h,s):
    main=s==0
    # Viscount-style streamlined gas turbine body and slim intake cuff;
    # no nose motor, no open radial face. Inner stations house the main legs.
    radii=((y-.379,.017,.016),(y-.330,.034,.036),
           (y-.210,.075 if main else .063,.070 if main else .053),(y-.115,.085,.074),
           (y-.032,.081,.074),(y+.013,.066,.065),(y+.049,.055,.056))
    T.tube("Elliptical low drag turbine nacelle",radii,"satin bare alloy",x,h)
    C("Blue anodyzed intake cuff",(x,y+.010,h),(x,y+.041,h),.068,.059,"deck blue",16)
    C("Rolled metal intake front ring",(x,y+.039,h),(x,y+.051,h),.060,.055,"silver rim",18)
    C("Deep turbine intake and bearing",(x,y+.052,h),(x,y+.062,h),.049,.049,"turbine gray",16)
    C("Spinner mounting billet",(x,y+.061,h),(x,y+.074,h),.032,.031,"low alloy",16)
    C("Long tapered forged spinner",(x,y+.072,h),(x,y+.112,h),.031,.021,"silver top",18)
    C("Solid propeller nose cone",(x,y+.112,h),(x,y+.132,h),.021,.0041,"ivory side",18)
    xx=x+half*(.064 if main else .067)
    C("Dark independent level exhaust jet pipe",(xx,y-.149,h-.022),(xx+half*.020,y-.238,h-.029),
        .025,.018,"heat bronze",12)
    C("Engine exhaust aperture",(xx+half*.020,y-.239,h-.029),(xx+half*.021,y-.242,h-.029),
        .014,.013,"exhaust finish",12)
    for j in range(3):
        B("Turbine cooling relief slit",(x-half*.072,y-.089-j*.022,h+.013),
          (.006,.013,.035),"exhaust finish",.001,(0,0,-half*.12))
    # Four real tapered, pitched metal blades with yellow painted tips.
    # Independent mesh parts are editable; the native display is not animated.
    for n in range(4):
        a=(.38 if main else .54)*half+n*pi/2
        verts=[]
        section=((.021,.009,.006),(.043,.016,.010),(.085,.017,.016),
                 (.119,.014,.02),(.139,.010,.017),(.153,.0027,.011))
        for span,chord,angle in section:
            for tang,depth in ((-chord,-.003),(chord,-.003),(chord,.004),(-chord,.004)):
                verts.append((x+span*cos(a)-tang*sin(a),y+.080+depth+angle*tang/chord,
                             h+span*sin(a)+tang*cos(a)))
        faces=[tuple(reversed(range(4))),tuple(range(20,24))]
        colors=["steel blade","sand tips"]
        for j in range(5):
            for k in range(4):
                faces.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
                colors.append("sand tips" if j==4 else "blade back" if k in (1,2) else "steel blade")
        M("Tapered four blade propeller airfoil",verts,faces,colors)


def wheel(x,y,r):
    C("Rounded rubber tyre main body",(x-.016,y,r),(x+.016,y,r),r*.96,r*.96,"tyre side",24)
    C("Level tire tread actual ground contact",(x-.010,y,r),(x+.010,y,r),r,r,"tread rubber",24)
    for side in (-1,1):
        C("Cast stepped visible wheel hub", (x+side*.015,y,r),(x+side*.021,y,r),
          r*.61,r*.51,"wheel hub",16)
        C("Inset center axle hub", (x+side*.021,y,r),(x+side*.024,y,r),
          r*.29,r*.24,"gear hydraulic",12)
        for n in range(5):
            a=2*pi*n/5
            rod("Steel axle lug",(x+side*.022,y+r*.42*cos(a),r+r*.42*sin(a)),
                (x+side*.024,y+r*.42*cos(a),r+r*.42*sin(a)),.0032,"wheel hub",6)


# Gear nodes: airframe checks account for both main bogies and nose tires.
GEAR=((- .326,-.071,.083,.246),( .326,-.071,.083,.246),(0,.552,.062,.260))

def undercarriage(down):
    for i,(x,y,r,z) in enumerate(GEAR):
        main=i<2
        cy=y-.024 if main else y-.008
        gz=.166 if main else .237
        span=.083 if main else .069
        if not down:
            # Forward-flush two-piece door plus aft hinge on the same nacelle.
            # It is physically above the lower edges of the down tires.
            for s in (-1,1):
                B("Closed longitudinal inner gear door",
                  (x+s*span*.232,cy,gz-.002),
                  (span*.462,.134 if main else .123,.015),"satin bare alloy",
                  .006,(.02,0,s*.13))
            rod("Closed longitudinal gear compartment seam",(x,cy-.059,gz-.008),
                (x,cy+.057,gz-.008),.0026,"gear recess",7)
            continue
        V.profile_hull("Recessed landing gear pocket liner",[
           (cy-.083,[(-.035+x,gz),(.035+x,gz),(.044+x,gz+.013),(-.044+x,gz+.013)]),
           (cy+.070,[(-.035+x,gz),(.035+x,gz),(.044+x,gz+.013),(-.044+x,gz+.013)]),
        ],"gear recess")
        for s in (-1,1):
            B("Deployable gear bay shell door leaf",
               (x+s*span*.54,cy,gz-.025),(.024,.150 if main else .12,.056),"satin bare alloy",
               .007,(-.07,s*.48,0))
        C("Lower oleo wheelgear forged front fork",(x,y,r),(x,y+.006,r+.070),
          .012,.015,"gear hydraulic",12)
        C("Shining telescopic oleo piston",(x,y+.006,r+.068),(x,y-.006,z-.033),
          .012,.014,"silver rim",12)
        C("Outer hydraulic cylinder",(x,y-.004,z-.072),(x,y-.013,z+.016),
          .019,.020,"gear hydraulic",12)
        rod("Geared fore-and-aft diagonal retraction arm",
          (x,y+.050,z+.012),(x,y+.007,r+.049),.0082,"gear hydraulic")
        if main:
            rod("Paired main leg articulation",
              (x-.023,y-.081,z),(x,y+.007,r+.057),.0079,"low alloy")
        rod("Load bearing two wheel axle",(x-.058,y,r),(x+.058,y,r),.0147,"gear hydraulic",10)
        for s in (-1,1):
            wheel(x+s*(.033 if main else .024),y,r)


def begin():
    V.PALETTE=PALETTE
    V.KEYS=list(KEYS)
    V.begin()


def plane():
    body()
    airframe()
    for side in (-1,1):
        for n,(x,y,h) in enumerate(((.326,.315,.266),(.614,.217,.310))):
            nacelle(side,x*side,y,h,n)


def group(name,things,hidden=False):
    c=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    for ob in things:
        for other in list(ob.users_collection):
            other.objects.unlink(ob)
        c.objects.link(ob)
    c.hide_viewport=hidden
    c.hide_render=hidden
    return c


def merge(shapes):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in shapes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active=shapes[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    t=ob.matrix_world.copy()
    ob.matrix_world.identity()
    for v in ob.data.vertices:
        v.co=t@v.co
    return ob


def atlas():
    line=b"".join(bytes.fromhex(PALETTE[k])*8 for k in KEYS)
    assert len(KEYS)==32
    def chunk(k,d):
        return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    encoded=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    encoded+=chunk(b"IDAT",zlib.compress((b"\0"+line)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures"/f"{STEM}_atlas.png").write_bytes(encoded)


def export():
    begin()
    plane()
    s=bpy.context.scene
    s.name="LuanTTD · Coleman Count small airliner 216"
    s["stock_engine_id"]=216
    s["tread_contact_z"]=0.0
    s["forward_axis"]="+Y source; Luanti -Z"
    body_parts=list(s.objects)
    undercarriage(True)
    down=[ob for ob in s.objects if ob not in body_parts]
    undercarriage(False)
    up=[ob for ob in s.objects if ob not in body_parts and ob not in down]
    group("Airframe, including all four turbines",body_parts)
    group("Landing gear extended",down)
    g=group("Landing gear retracted (toggle both collections)",up,True)
    bpy.ops.object.select_all(action="DESELECT")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                default=area.spaces.active
                default.region_3d.view_distance=3.4
                default.region_3d.view_location=Vector((0,0,.28))
                default.region_3d.view_rotation=Vector((.89,.66,.49)).to_track_quat("Z","Y")
                default.shading.color_type="MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/coleman_count.blend"),compress=True)
    g.hide_viewport=False
    bpy.context.view_layer.update()
    for label,choices in (("",down),("_flight",up)):
        coll=bpy.context.scene.collection
        clones=[]
        for ob in body_parts+choices:
            copy=ob.copy()
            copy.data=ob.data.copy()
            coll.objects.link(copy)
            clones.append(copy)
        bpy.context.view_layer.update()
        ob=merge(clones)
        ob.name="Coleman_Count_216"+label
        uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
        for p in ob.data.polygons:
            idx=KEYS.index(ob.data.materials[p.material_index].name)
            for l in p.loop_indices:
                uv.data[l].uv=((idx+.5)/len(KEYS),.5)
        ob.data.update()
        bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models"/f"{STEM}{label}.obj"),
          export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
          export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")
        bpy.data.objects.remove(ob,do_unlink=True)


def review(path):
    begin()
    plane()
    undercarriage(True)
    B("Flat grass and field edge", (0,0,-.062),(7.8,6.6,.120),"grass",.026)
    B("Flat concrete for the exact tire datum",(0,0,-.039),(5.6,4.8,.078),"concrete",.015)
    for x in (-2,-1,0,1,2):
        B("Apron expansion joint",(x,0,.001),(.005,4.77,.002),"apron joint")
    for y in (-2,-1,0,1,2):
        B("Apron expansion joint",(0,y,.001),(5.57,.005,.002),"apron joint")
    bpy.ops.object.camera_add(location=(3.50,4.10,2.94))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,-.03,.266))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=2.59
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1400,910
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("Country airport sky")
    s.world.color=(.153,.169,.186)
    sh=s.display.shading
    sh.light="STUDIO"
    sh.color_type="MATERIAL"
    sh.background_type="WORLD"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    s.render.filepath=path
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    atlas()
    export()
    if (p:=os.getenv("COLEMAN_REVIEW")):
        review(p)
