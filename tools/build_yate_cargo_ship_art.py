"""Author the original native Yate Cargo Ship (#211, OpenTTD 14.1).

blender -b -t 3 --python-exit-code 1 --python tools/build_yate_cargo_ship_art.py
Optional YATE_REVIEW=/path/name.png renders the ship at its exact water plane.
Blender +Y fore, +Z up; Luanti OBJ -Z fore and +Y up, 10 export units per node.
"""
from math import cos, pi, sin
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V

ROOT = V.ROOT
PALETTE = {
    "boot blue":"20516f", "hull blue":"326c93", "hull sky":"5998b5",
    "hull shaded":"2b6287", "gunwale":"7eb4ca", "rust red":"8f4032",
    "red lower":"643734", "rubber":"322a25", "deck teak":"857152",
    "deck rubbed":"9a835d", "deck weathered":"a48c62", "deck edge":"706450",
    "gray steel":"5c6665", "bright steel":"96a19c", "black steel":"39464a",
    "hatch black":"27363b", "hatch raised":"35464d", "hatch highlight":"5d6d66",
    "derrick orange":"c06a3d", "derrick dark":"905036", "derrick highlight":"df8c57",
    "bridge white":"e9e5d5", "bridge shadow":"bebfb5", "bridge trim":"aaa9a0",
    "window dark":"283c46", "window light":"58818f", "paper":"f4edcf",
    "stack red":"ad4337", "green lens":"5b976f", "red lens":"d8533d",
    "ropes":"554c37", "brass":"b2996a",
}
KEYS = tuple(PALETTE)
B, C, M = V.bevel_box, V.round_between, V.add_mesh
STEM = "bl_yate_cargo_ship"
# Fit the lower closed lock mitre in either heading, keeping the elongated stock silhouette.
BEAM, LENGTH = .925, .923
# z (local Blender +Y), moulded maximum beam / 2, main deck sheer, bottom.
# Long parallel midbody and a soft cruiser stern, raked stem over the forefoot.
HULL = (
    (-.988,.045,.188,-.058),(-.962,.146,.189,-.075),(-.897,.250,.185,-.104),
    (-.787,.321,.177,-.144),(-.632,.365,.166,-.173),(-.446,.373,.158,-.181),
    (-.244,.374,.153,-.184),( .014,.374,.151,-.187),( .273,.367,.153,-.187),
    ( .448,.342,.157,-.181),( .599,.300,.166,-.164),( .749,.228,.181,-.128),
    ( .865,.143,.209,-.082),( .945,.070,.233,-.041),( .989,.012,.248,-.010),
)


def rod(name, a, b, r, mat, n=8):
    return C(name, a, b, r, r, mat, n)


def profile(y):
    for lhs,rhs in zip(HULL,HULL[1:]):
        if lhs[0]-1e-8 <= y <= rhs[0]+1e-8:
            t=(y-lhs[0])/(rhs[0]-lhs[0])
            return tuple(a+(b-a)*t for a,b in zip(lhs[1:],rhs[1:]))
    raise ValueError(y)


def section(w,z,k):
    return [(-w,z),(-w,.093),(-w*.990,.016),(-w*.960,-.011),
            (-w*.885,-.057),(-w*.691,k*.78),(-w*.333,k*.985),
            (w*.333,k*.985),(w*.691,k*.78),(w*.885,-.057),
            (w*.960,-.011),(w*.990,.016),(w,.093),(w,z)]


def hull():
    V.profile_hull("Closed riveted cargo hull",[(y,section(w,z,k)) for y,w,z,k in HULL],"hull blue",
      ["hull sky","hull blue","boot blue","rust red","rust red","red lower",
       "red lower","red lower","rust red","rust red","boot blue","hull blue","hull sky","deck edge"])
    # Outer rubbing band follows the sheer; fore/aft curvature is not faceted
    # into unrelated straight slabs. The centre tinted boot is exactly Y=0.
    for side in (-1,1):
        for a,b in zip(HULL,HULL[1:]):
            for off, radius, color in ((.014,.007,"gunwale"),(.060,.004,"hull shaded")):
                rod("Continuous sheer and rubbing band",(side*a[1],a[0],a[2]-off),
                    (side*b[1],b[0],b[2]-off),radius,color,7)
    # Independently laid tapered timber bands along the real weather deck.
    # Resolve sprung plank strips at every hull station; no floating extremities.
    for i in range(-8,9):
        u0=(i-.48)*.111
        u1=(i+.48)*.111
        verts=[]
        for y,w,h,_ in HULL:
            verts.extend(((u0*w,y,h+.0022),(u1*w,y,h+.0022)))
        faces=[(2*j,2*j+1,2*j+3,2*j+2) for j in range(len(HULL)-1)]
        M("Fitted weather deck plank",[tuple(v) for v in verts],faces,
          [("deck teak","deck rubbed","deck weathered","deck teak")[(i+3*j)%4] for j in range(len(faces))])
    # Screw and rudder are three-dimensional and remain below the blue boot.
    rod("Visible enclosed keel shaft",(0,-.742,-.126),(0,-.949,-.099),.019,"red lower",9)
    rod("Bronze screw hub",(0,-.887,-.112),(0,-.941,-.111),.020,"brass",12)
    for j in range(3):
        a=j*2*pi/3+.2
        def p(r,d,y): return (r*cos(a+d), y, -.112+r*sin(a+d))
        xyz=[p(.013,-.3,-.932),p(.053,-.23,-.930),p(.070,.14,-.921),p(.037,.32,-.913)]
        verts=xyz+[(x,y+.007,z) for x,y,z in xyz]
        M("Raked bronze screw blade",verts,((0,3,2,1),(4,5,6,7),(0,1,5,4),
          (1,2,6,5),(2,3,7,6),(3,0,4,7)),"brass")
    V.profile_hull("Tapered rudder and post",[
      (-.970,[(-.006,-.143),(.006,-.143),(.006,-.024),(-.006,-.024)]),
      (-.945,[(-.012,-.174),(.012,-.174),(.012,-.021),(-.012,-.021)])],"red lower")


def bulwarks():
    # Slender rail posts leave the working deck visible. Ends at two
    # actual break-bulk transfer gates ahead of the aft accommodation.
    for side in (-1,1):
        for run in ((-.931,-.852,-.758,-.645),(-.558,-.438,-.347,-.220,-.110),
                    (-.022,.085,.180,.286,.403,.515,.631,.734,.829,.914,.968)):
            previous=None
            for y in run:
                w,h,_=profile(y)
                foot=(side*w*.965,y,h)
                rod("Riveted deck guard stanchion",foot,(foot[0],y,h+.072),.0055,"bright steel",6)
                if previous:
                    for offset in (.072,.038):
                        rod("Open guard rail between loading breaks",
                          (previous[0],previous[1],previous[2]+offset),
                          (foot[0],y,h+offset),.0042,"gray steel",6)
                previous=foot
        for y,w in ((-.885,.186),(-.581,.319),(.568,.273),(.806,.157)):
            h=profile(y)[1]
            B("Cast double-bitt foot plate",(side*w,y,h+.010),(.047,.056,.014),"gray steel",.004)
            for dy in (-.013,.013):
                C("Forged mooring bitt",(side*w,y+dy,h+.009),(side*w,y+dy,h+.053),.010,.013,"black steel",8)
        for y in (.803,.846):
            w,h,_=profile(y)
            rod("Bow hawse rim",(side*w*.982,y,h-.052),(side*(w+.009),y,h-.052),
              .025 if y<.83 else .020,"gray steel",10)
            rod("Recessed dark hawse aperture",(side*(w+.008),y,h-.052),
              (side*(w+.014),y,h-.052),.014 if y<.83 else .010,"hatch black",10)
        # Forged stock, curving crown and flukes on the starboard bow only.
        if side==1:
            rod("Stocked anchor shank",(.155,.836,.152),(.194,.793,.090),.008,"black steel")
            rod("Forged anchor stock",(.126,.823,.144),(.179,.850,.148),.007,"gray steel")
            for end in ((.163,.781,.097),(.222,.799,.112)):
                rod("Curved crown and exposed anchor fluke",(.194,.793,.090),end,.009,"black steel")
    B("Steam windlass cast mounting",(0,.763,.192),(.159,.068,.022),"black steel",.008)
    rod("Transverse anchor windlass barrel",(-.087,.761,.235),(.087,.761,.235),.026,"gray steel",13)
    for x in (-.073,-.028,.028,.073):
        C("Windlass chain drum flange",(x-.005,.761,.235),(x+.005,.761,.235),.035,.035,"black steel",12)
    for side in (-1,1):
        for j in range(7):
            B("Stud-linked anchor chain stretched on foredeck",
              (side*(.048+.015*j),.780+.010*j,.221+.0035*j),
              (.021,.014,.008),"ropes",.004,(0,0,.48 if j%2 else .73))
    C("Steam supply capstan head",(0,-.874,.188),(0,-.874,.239),
      .027,.024,"gray steel",10)
    B("Emergency steering gear casing",(0,-.914,.206),(.104,.047,.036),"deck edge",.007)


def hold(y, length):
    # Black stock hatches are closed weather covers, not an exposed load.
    # Independently removable-looking raised panel ribs and perimeter girdle.
    B("Welded hatch coaming",(0,y,.181),(.488,length+.038,.070),"gray steel",.014)
    B("Sealed black weather hatch",(0,y,.230),(.470,length,.035),"hatch black",.012)
    for j in range(6):
        yy=y+length*((j+.5)/6-.5)
        B("Individual removable break-bulk hatch cover",(0,yy,.249),
          (.445,length/6-.004,.019),"hatch raised" if j in (1,4) else "hatch black",.005)
        for side in (-1,1):
            x=side*.197
            rod("Deck tackle hatch cover eye",(x-.006,yy,.258),(x,yy,.269),.0038,"hatch highlight",6)
            rod("Deck tackle hatch cover eye",(x,yy,.269),(x+.007,yy,.258),.0038,"hatch highlight",6)
    for side in (-1,1):
        rod("Protective hatch edge rub strip",(side*.230,y-length*.46,.248),
            (side*.230,y+length*.46,.248),.0045,"hatch highlight",6)


def lift(y, drift):
    platez=profile(y)[1]
    C("Cargo kingpost riveted circular plate",(0,y,platez),(0,y,platez+.020),
      .060,.055,"black steel",12)
    C("Orange cargo kingpost base",(0,y,.176),(0,y,.294),.025,.020,"derrick dark",12)
    C("Orange tapered derrick kingpost",(0,y,.268),(0,y,.545),.019,.013,"derrick orange",12)
    C("Derrick kingpost collar",(0,y,.515),(0,y,.541),.021,.020,"derrick highlight",10)
    C("Kingpost crown",(0,y,.540),(0,y,.559),.014,.009,"derrick highlight",10)
    endpoint=(drift,y-.241,.512)
    C("Tapered kingpost derrick boom",(0,y,.362),endpoint,.014,.008,"derrick orange",10)
    rod("Topping lift taut wire",(0,y,.553),endpoint,.0032,"ropes",6)
    rod("Cargo derrick pendant",endpoint,(drift,y-.241,.444),.0032,"ropes",6)
    C("Painted derrick cargo block",(drift,y-.241,.435),(drift,y-.241,.452),
      .012,.009,"derrick highlight",9)
    for a,b in zip(((0,0),(.008,0),(.010,.008),(.003,.013)),
                   ((.008,0),(.010,.008),(.003,.013),(0,.008))):
        rod("Rounded cargo hook",(drift+a[0],y-.241,.422+a[1]),
            (drift+b[0],y-.241,.422+b[1]),.0039,"black steel",7)
    for side in (-1,1):
        x=side*.083
        B("Steam cargo winch cast chassis",(x,y+.053,platez+.029),
          (.089,.065,.042),"gray steel",.008)
        rod("Break-bulk winch barrel",(x-.043,y+.052,platez+.060),
            (x+.043,y+.052,platez+.060),.023,"black steel",10)
        for off in (-.019,.019):
            C("Winch raised flange",(x+off-.004,y+.052,platez+.060),
              (x+off+.004,y+.052,platez+.060),.031,.031,"derrick dark",10)
        rod("Winch line through pin on kingpost",(x,y+.052,platez+.081),
            (0,y,.378),.0025,"ropes",5)


def windows():
    # Deckhouse glazing spans actual three forward facets plus side bays;
    # shallow returns and inset contrast read at both walk and cabin survey.
    for x,y,width,angle in ((-.049,-.426,.063,0),(.049,-.426,.063,0),
            (-.130,-.432,.055,.124),(.130,-.432,.055,-.124)):
        B("Raised wheelhouse window architrave",(x,y,.538),
          (width,.016,.075),"bridge trim",.007,(0,0,angle))
        B("Wheelhouse recessed blue forward glazing",(x,y+.008,.540),
          (width-.010,.015,.064),"window dark",.006,(0,0,angle))
        B("Restrained reflection in wheelhouse glass",(x,y+.015,.557),
          (width-.016,.010,.016),"window light",.002,(0,0,angle))
    for side in (-1,1):
        for y in (-.533,-.610,-.679):
            B("Pressed side wheelhouse window architrave",(side*.196,y,.543),
              (.017,.056,.077),"bridge trim",.006)
            B("Recessed wheelhouse side glazing",(side*.203,y,.543),
              (.012,.044,.062),"window dark",.004)
            B("Side glazing wan sky reflection",(side*.207,y,.559),
              (.007,.039,.014),"window light",.002)
        for y in (-.480,-.560,-.630,-.691):
            C("Cast-brass accommodation porthole rim",(side*.215,y,.306),(side*.230,y,.306),
              .020,.019,"bridge trim",12)
            C("Dark accommodation porthole",(side*.226,y,.306),(side*.233,y,.306),
              .014,.014,"window dark",10)
        B("Open beneath wheelhouse wing",(side*.227,-.527,.466),
          (.117,.111,.020),"bridge shadow",.007)
        for i in range(5):
            B("Outside accommodation stair tread",(side*.258,-.390-i*.019,.211+i*.048),
              (.078,.039,.013),"gray steel",.004)
        for x in (side*.217,side*.298):
            rod("Boat deck stair stringer",(x,-.372,.200),(x,-.476,.420),.008,"bridge shadow")
            rod("Outside stair handrail",(x,-.373,.273),(x,-.476,.485),.0048,"bright steel")
        B("Forward red or green nav-lamp housing",(side*.270,-.479,.513),
          (.035,.058,.046),"black steel",.008)
        B("Wheelhouse navigation lamp lens",(side*.289,-.470,.516),(.018,.033,.022),
          "red lens" if side==-1 else "green lens",.005)


def deckhouse():
    def edges(w,lo,hi):
        return [(-w*.88,lo),(w*.88,lo),(w,lo+.022),(w,hi-.022),
                (w*.92,hi),(-w*.92,hi),(-w,hi-.022),(-w,lo+.022)]
    V.profile_hull("The flared white afterhouse lower accommodation",
      [(y,edges(w,.158,.393)) for y,w in ((-.739,.167),(-.716,.219),(-.461,.221),(-.411,.173))],"bridge white")
    B("Roof of lower aft accommodation", (0,-.581,.395),(.486,.368,.029),"bridge shadow",.011)
    V.profile_hull("Wide aft lower wheelhouse tier",
      [(y,edges(w,.396,.482)) for y,w in ((-.719,.178),(-.699,.200),(-.466,.195),(-.440,.138))],"bridge white")
    V.profile_hull("Forward chamfered wheelhouse with traversing windshields",
      [(y,V.roof_contour(w,.468,.581,.607)) for y,w in
       ((-.704,.163),(-.684,.197),(-.475,.198),(-.438,.147),(-.431,.091))],"bridge white")
    V.profile_hull("Rounded overhanging deckhouse roof",[
      (y,V.roof_contour(w,.591,.625,.640)) for y,w in
      ((-.724,.170),(-.699,.215),(-.460,.212),(-.416,.144))],"bridge white")
    B("Raised teak wheelhouse weather trim",(0,-.556,.474),(.409,.293,.011),"deck teak",.009)
    windows()
    for side in (-1,1):
        x=side*.210
        B("Aft hatch side white steel weather door",(x,-.665,.283),
          (.031,.067,.175),"bridge shadow",.005)
        B("Pressed white weather door face",(side*.229,-.666,.282),
          (.011,.057,.147),"bridge white",.004)
        rod("Outside latch handle",(side*.234,-.689,.281),(side*.238,-.674,.281),
          .0037,"brass",7)
    # Period company nameboard and dry cargo identity, never copied pixel art.
    for side in (-1,1):
        B("Blue wheelhouse name board",(side*.220,-.558,.366),(.013,.227,.046),"hull shaded",.006)
        V.typeface("Raised cast ship class name","YATE",(side*.229,-.559,.369),
                   .038,side*pi/2,"bridge white")
    rod("Open forecastle signal mast",(0,-.495,.643),(0,-.497,.808),.0072,"gray steel")
    rod("Mast horizontal signalling yard",(-.076,-.496,.768),(.076,-.496,.768),.0045,"gray steel",7)
    B("Warm ship masthead lamp",(0,-.495,.815),(.018,.018,.017),"paper",.004)
    for side in (-1,1):
        rod("Bridge mast wire",(side*.075,-.496,.768),(side*.182,-.631,.628),
          .0024,"ropes",5)


def open_funnel(y,x,z,l,r,color):
    # Hollow lip with open top rather than a texture over a solid cylinder.
    n=18
    stations=((y,z,r*1.09),(y-.026,z+l-.019,r),
              (y-.030,z+l,r*1.13),(y-.030,z+l,r*.71),
              (y-.025,z+l-.083,r*.65))
    verts=[(x+radius*cos(i*2*pi/n),yy+radius*sin(i*2*pi/n),h)
           for yy,h,radius in stations for i in range(n)]
    faces=[]
    for level in range(4):
        for i in range(n):
            q=(i+1)%n
            faces.append((level*n+i,level*n+q,(level+1)*n+q,(level+1)*n+i))
    faces.append(tuple(range(4*n,5*n)))
    M("Open raked steam exhaust and black rim",verts,faces,
      [color]*n+["black steel"]*(len(faces)-n))
    C("Engine-room uptake cast mounting",(x,y,z-.031),(x,y,z+.012),r*1.46,r*1.42,"bridge shadow",14)


def lifeboat():
    # Starboard-side aft open clinker life boat, cream shell and rusty red
    # canvas ditch lockers preserve the warm accents present on stock stern.
    sx=.186
    n=7
    rows=(
      (-.839,.018,.018),(-.805,.048,.033),(-.744,.056,.043),
      (-.683,.044,.032),(-.655,.011,.018))
    h=.425
    contour=lambda w,d,z:[(sx-w,z),(sx-w*.82,z-d*.55),(sx-w*.32,z-d),
      (sx,z-d*1.02),(sx+w*.32,z-d),(sx+w*.82,z-d*.55),(sx+w,z)]
    raw=[(x,y,z) for y,w,d in rows for x,z in contour(w,d,h)]
    wall=[(j*n+k,(j+1)*n+k,(j+1)*n+k+1,j*n+k+1)
      for j in range(len(rows)-1) for k in range(n-1)]
    # Inward normals on this independent lift-out clinker liner.
    M("Open cream clinker lifeboat outer shell",raw,[tuple(reversed(x)) for x in wall],"bridge white")
    M("Open clinker boat timber liner",[(sx+.91*(x-sx),y,z+.004) for x,y,z in raw],wall,"deck weathered")
    rod("Lifeboat stem pole",(sx,-.850,.418),(sx,-.836,.430),.007,"deck edge")
    for y in (-.792,-.758,-.719,-.690):
        B("Exposed lifeboat slat seat",(sx,y,.407),(.072,.022,.009),"deck edge",.003)
    for y in (-.806,-.696):
        rod("Graceful bent steel davit",(.236,y,.388),(.248,y,.512),.007,"gray steel")
        rod("Graceful bent steel davit",(.248,y,.512),(.204,y,.542),.006,"gray steel")
        rod("Lifeboat davit fall",(.204,y,.542),(sx,y,.425),.003,"ropes",6)


def ship():
    hull()
    bulwarks()
    hold(.406,.295)
    hold(-.068,.326)
    lift(.609,.043)
    lift(.164,-.036)
    deckhouse()
    open_funnel(-.778,-.087,.401,.251,.055,"stack red")
    open_funnel(-.831,.067,.258,.120,.028,"stack red")
    lifeboat()
    for yy in (-.867,-.711):
        rod("Cowl ventilator return leg",(-.213,yy,.198),(-.213,yy,.325),.010,"bridge shadow")
        rod("Cowl ventilator lip",(-.213,yy,.325),(-.213,yy+.024,.342),.018,"stack red")
    rod("Wood stern ensign staff",(0,-.963,.185),(0,-.973,.364),.0056,"brass")
    a,b,c,d=(0,-.973,.365),(.078,-.985,.351),(.075,-.979,.315),(0,-.972,.326)
    M("Original red coastal ensign", [a,b,c,d], [(0,1,2,3),(3,2,1,0)],"stack red")
    # Bake the moulded proportions into Blender and OBJ consistently, including
    # rotated deck furniture. Every naming/selection/editable part is retained.
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            continue
        t=ob.matrix_world.copy()
        p=t.translation
        for v in ob.data.vertices:
            d=t@v.co-p
            v.co=Vector((BEAM*d.x,LENGTH*d.y,d.z))
        ob.matrix_world.identity()
        ob.location=(BEAM*p.x,LENGTH*p.y,p.z)
        ob.data.update()


def begin():
    V.PALETTE=PALETTE
    V.KEYS=list(KEYS)
    V.begin()


def atlas():
    row=b"".join(bytes.fromhex(PALETTE[k])*8 for k in KEYS)
    assert len(KEYS)==32
    def chunk(k,d):
        return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    encoded=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    encoded+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures"/f"{STEM}_atlas.png").write_bytes(encoded)


def export():
    begin()
    ship()
    scene=bpy.context.scene
    scene.name="LuanTTD · Stock Yate Cargo Ship #211"
    scene["stock_engine_id"]=211
    scene["waterline_local_z"]=0.0
    scene["forward_axis"]="+Y in authoring scene; -Z in native OBJ"
    scene["native_scale"]=1.0
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                area.spaces.active.region_3d.view_distance=3.5
                area.spaces.active.region_3d.view_location=Vector((0,0,.24))
                area.spaces.active.region_3d.view_rotation=Vector((.95,-.62,.60)).to_track_quat("Z","Y")
                area.spaces.active.shading.color_type="MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/yate_cargo_ship.blend"),compress=True)
    shapes=list(ob for ob in scene.objects if ob.type=="MESH")
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
    ob.name="Yate_Cargo_Ship_211"
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    for p in ob.data.polygons:
        idx=KEYS.index(ob.data.materials[p.material_index].name)
        for l in p.loop_indices:
            uv.data[l].uv=((idx+.5)/len(KEYS),.5)
    ob.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models"/f"{STEM}.obj"),
      export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
      export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")


def review(path):
    begin()
    ship()
    V.MATS["Basin water"]=bpy.data.materials.new("Basin water")
    V.MATS["Basin water"].diffuse_color=(.062,.183,.22,1)
    B("Exact datum water plane",(0,0,-.035),(9.0,9.0,.070),"Basin water",.015)
    bpy.ops.object.camera_add(location=(3.0,1.75,2.39))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.27))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=2.83
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1320,910
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("Soft harbour sky")
    s.world.color=(.154,.170,.182)
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
    if (p:=os.getenv("YATE_REVIEW")):
        review(p)
