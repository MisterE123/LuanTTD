"""Original LuanTTD mail and later bus Blender assets (Blender 4.3 or later).

blender -b -t 2 --python-exit-code 1 --python tools/build_extra_road_vehicle_art.py
Set BAYLINE_ROAD_FLEET_REVIEW=/tmp/fleet.png for a four-view likeness sheet.
"""
from pathlib import Path
from math import cos, sin, pi
import os
import struct
import zlib

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
PALETTE = {
    "chassis":"33343a", "rubber":"252931", "tread":"3e424b", "silver":"c5c4b6",
    "steel":"798994", "nozzle":"474c55", "bright lamp":"ffde87", "tail":"d4433b",
    "dark glass":"253e4a", "light glass":"548196", "offwhite":"e8dbb3", "enamel":"f4eace",
    "cab wine":"8f3539", "postal red":"a94643", "wine shade":"682f36", "postal gold":"dca45d",
    "coach blue":"31658c", "coach shadow":"294857", "coach sky":"4b84a3", "coach cream":"f2dfb1",
    "interior":"8b694d", "sign black":"334453", "indicator":"ed9e4c", "door rubber":"333c40",
}
KEYS=list(PALETTE)
MATS={}

def linear(x):
    return x/12.92 if x<.04045 else ((x+.055)/1.055)**2.4

def begin():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.view_settings.view_transform="Standard"
    bpy.context.preferences.filepaths.save_version=0
    MATS.clear()
    for key,hexcolor in PALETTE.items():
        material=bpy.data.materials.new(key)
        material.diffuse_color=tuple(linear(int(hexcolor[i:i+2],16)/255) for i in (0,2,4))+(1,)
        MATS[key]=material

def add_mesh(name, vertices, faces, surfaces):
    data=bpy.data.meshes.new(name)
    data.from_pydata(vertices,[],faces)
    data.update()
    ob=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(ob)
    if isinstance(surfaces,str):
        data.materials.append(MATS[surfaces])
    else:
        ordered=list(dict.fromkeys(surfaces))
        for key in ordered:
            data.materials.append(MATS[key])
        for p,m in zip(data.polygons,surfaces):
            p.material_index=ordered.index(m)
    return ob

def bevel_box(name, p, dims, surf, bevel=0, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    ob=bpy.context.object
    ob.name=name
    ob.scale=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel>=.004:
        mod=ob.modifiers.new("Rolled edge", "BEVEL")
        # Fine door hardware reads without extra silhouette rings at play scale.
        mod.width,mod.segments=bevel,2 if bevel>=.014 else 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if rot:
        ob.rotation_euler=rot
    ob.data.materials.append(MATS[surf])
    return ob

def round_between(name, a, b, r1, r2, surf, n=14):
    a,b=Vector(a),Vector(b)
    heading=(b-a).to_track_quat("Z","Y")
    verts=[]
    for p,r in ((a,r1),(b,r2)):
        for k in range(n):
            angle=k*2*pi/n
            verts.append(p+heading@Vector((r*cos(angle),r*sin(angle),0)))
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    return add_mesh(name,verts,faces+[(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)],surf)

def profile_hull(name, stations, surface, per_side=None):
    # stations: (local y, contour around x/z cross section, CCW in x/z).
    m=len(stations[0][1])
    assert all(len(c)==m for _,c in stations)
    verts=[(x,y,z) for y,c in stations for x,z in c]
    caps=[tuple(range(m)),tuple(reversed(range((len(stations)-1)*m,len(stations)*m)))]
    quads=[(a*m+k,(a+1)*m+k,(a+1)*m+(k+1)%m,a*m+(k+1)%m)
           for a in range(len(stations)-1) for k in range(m)]
    return add_mesh(name,verts,caps+quads,
                    surface if per_side is None else [surface,surface]+per_side*(len(stations)-1))

def roof_contour(w, lower_z, shoulder_z, highest_z):
    # Planar window belt, top shoulders carrying a smooth low-poly cap.
    return [(-w*.87,lower_z), (w*.87,lower_z), (w,lower_z+.031),
            (w,shoulder_z-.036),(w*.88,shoulder_z),(w*.70, highest_z-.016),
            (w*.39,highest_z),(0,highest_z+.004),(-w*.39,highest_z),
            (-w*.70,highest_z-.016),(-w*.88,shoulder_z),(-w,shoulder_z-.036),
            (-w,lower_z+.031)]

def side_windows(x, y, z, width, height, frame="enamel"):
    side=1 if x>0 else -1
    bevel_box("Window surround",(x,y,z),(.014,width+.020,height+.019),"door rubber",.004)
    bevel_box("Window glass",(x+side*.009,y,z),(.010,width,height),"dark glass",.004)
    bevel_box("High glass reflection",(x+side*.016,y-.005,z+height*.292),
              (.005,width*.87,height*.192),"light glass",.002)
    if width>.22:
        bevel_box("Vent sash mullion",(x+side*.017,y+width*.22,z),(.006,.011,height),frame,.002)

def wheels(ys, axle_x, axle_z, radius, trim):
    for y in ys:
        round_between("Live axle",(-axle_x,y,axle_z),(axle_x,y,axle_z),.026,.026,"chassis",12)
        for side in (-1,1):
            x=side*axle_x
            round_between("Tyre sidewall outer", (x-side*.042,y,axle_z),(x+side*.044,y,axle_z),
                          radius*.94,radius*.94,"rubber",20)
            round_between("Crowned tyre tread",(x-side*.032,y,axle_z),(x+side*.032,y,axle_z),
                          radius,radius,"rubber",20)
            round_between("Hub recess",(x+side*.043,y,axle_z),(x+side*.047,y,axle_z),
                          radius*.64,radius*.64,"tread",16)
            round_between("Pressed hub cap",(x+side*.047,y,axle_z),(x+side*.062,y,axle_z),
                          radius*.48,radius*.37,trim,16)
            for p in range(5):
                a=p*2*pi/5
                yy,zz=y+radius*.26*cos(a),axle_z+radius*.26*sin(a)
                round_between("Wheel stud",(x+side*.057,yy,zz),(x+side*.066,yy,zz),
                              .0055,.0055,"steel",5)

def wheel_arch(x, cy, z, r, spread, color):
    # Real curved fender well that leaves the tyre aperture open.
    s=1 if x>0 else -1
    nx=10
    verts=[]
    for xx,offset in ((x-s*spread,0),(x,0),(x,r*.22),(x-s*spread,r*.17)):
        for idx in range(nx+1):
            a=pi*idx/nx
            verts.append((xx,cy+(r+offset)*cos(a),z+(r+offset)*sin(a)))
    faces=[]
    m=nx+1
    for run in range(4):
        nxt=(run+1)%4
        for k in range(nx):
            face=(run*m+k,run*m+k+1,nxt*m+k+1,nxt*m+k)
            faces.append(face if s==1 else tuple(reversed(face)))
    faces += [tuple(i*m for i in (3,2,1,0)),tuple(i*m+nx for i in range(4))]
    ob=add_mesh("Rolled wheel arch and tyre aperture",verts,faces,color)
    # Ensure the right and left fenders keep exterior normals after mirroring.
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

def lamps(y, z, x, radius):
    for side in (-1,1):
        round_between("Headlamp bezel",(side*x,y-.016,z),(side*x,y+.012,z),
                      radius*1.18,radius*1.18,"silver",14)
        round_between("Glass headlamp lens",(side*x,y+.011,z),(side*x,y+.020,z),
                      radius,radius*.86,"bright lamp",14)

def rear_lamps(y,z,x):
    for side in (-1,1):
        bevel_box("Rounded stop lamp mounting",(side*x,y,z),(.053,.019,.048),"wine shade",.010)
        bevel_box("Red tail lamp",(side*x,y-.014,z),(.039,.020,.032),"tail",.008)
        bevel_box("Rear direction indicator",(side*x,y-.015,z+.032),(.038,.016,.018),"indicator",.003)

def typeface(label,text, pos,size,face,surf):
    # Small enamel sign lettering is real mesh, no copyrighted brands.
    cr=bpy.data.curves.new(label,"FONT")
    cr.body=text
    cr.align_x="CENTER"
    cr.align_y="CENTER"
    cr.size=size
    cr.extrude=.00075
    cr.resolution_u=2
    ob=bpy.data.objects.new(label,cr)
    bpy.context.collection.objects.link(ob)
    ob.location=pos
    ob.rotation_euler=(pi/2,0,face)
    ob.data.materials.append(MATS[surf])
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target="MESH")

def envelope(side,y,z):
    x=side*.261
    bevel_box("Raised postal envelope plate",(x,y,z),(.007,.218,.126),"offwhite",.005)
    def seam(u,v,a,b):
        p=(x+side*.006,y+(u+a)*.5,z+(v+b)*.5)
        d=Vector((0,a-u,b-v))
        ob=bevel_box("Envelope flap seam",p,(.004,.009,d.length),"wine shade")
        ob.rotation_euler=d.to_track_quat("Z","Y").to_euler()
    for u,v,a,b in ((-.100,.051,0,-.013),(0,-.013,.100,.051),
                    (-.100,-.049,-.023,.001),(.100,-.049,.023,.001)):
        seam(u,v,a,b)

def mail_van():
    """1940s parcel van with a pressed bonnet and physically separate coachwork."""
    bevel_box("Ladder frame", (0,-.03,.143),(.418,1.316,.091),"chassis",.014)
    # The mail compartment is full-height with a curved pressed roof and lower sill.
    profile_hull("Pressed mail compartment body",
                 [(-.68,roof_contour(.238,.222,.574,.611)),
                  (-.638,roof_contour(.258,.212,.602,.652)),
                  (.145,roof_contour(.258,.212,.602,.652)),
                  (.176,roof_contour(.235,.222,.578,.625))],"postal red",
                 ["wine shade","wine shade","postal red","postal red","offwhite","offwhite","offwhite",
                  "offwhite","offwhite","offwhite","postal red","postal red","wine shade"])
    profile_hull("Coachbuilt steel cab",[ (.138,roof_contour(.230,.196,.565,.609)),
                 (.237,roof_contour(.239,.195,.567,.609)),
                 (.470,roof_contour(.224,.202,.545,.584)),
                 (.544,roof_contour(.200,.217,.491,.519))],"cab wine")
    for y0,w0,y1,w1 in ((.425,.210,.525,.149),(.525,.149,.706,.130),(.706,.130,.767,.106)):
        profile_hull("Tapered side-valve bonnet",
                     [(y0,roof_contour(w0,.199,.374,.401)),
                      (y1,roof_contour(w1,.197,.353,.378))],"cab wine")
    for side in (-1,1):
        wheel_arch(side*.286,.522,.111,.117,.102,"wine shade")
        wheel_arch(side*.286,-.460,.111,.117,.086,"wine shade")
        side_windows(side*.236,.309,.491,.167,.121,"offwhite")
        bevel_box("Single pressed cab door belt",(side*.239,.319,.390),(.015,.267,.022),"offwhite",.003)
        bevel_box("Cab door handle",(side*.252,.251,.394),(.012,.048,.012),"silver",.004)
        bevel_box("Cab running board",(side*.250,.083,.135),(.075,.430,.035),"chassis",.005)
        bevel_box("Painted postal belt",(side*.261,-.253,.393),(.009,.765,.023),"offwhite",.003)
        bevel_box("Gutter at upper box seam",(side*.246,-.254,.590),(.018,.800,.020),"offwhite",.003)
        envelope(side,-.245,.477)
        typeface("Postal door legend","POST", (side*.263,-.246,.313),.065,side*(pi/2),"offwhite")
        for j in range(5):
            bevel_box("Bonnet ventilation stamp",(side*.153,.56+j*.023,.303),(.006,.012,.073),"wine shade",.002)
        bevel_box("Hand mirror arm",(side*.248,.442,.489),(.058,.011,.013),"steel",.002)
        bevel_box("Round mirror surround",(side*.278,.445,.496),(.026,.018,.040),"steel",.005)
    for side in (-1,1):
        bevel_box("Split windshield pane",(side*.092,.549,.478),(.163,.025,.112),"door rubber",.008,
                  (.032,0,0))
        bevel_box("Front windshield glass",(side*.092,.563,.479),(.147,.012,.097),"dark glass",.006,
                  (.032,0,0))
        bevel_box("Reflected windshield sky",(side*.092,.570,.511),(.124,.007,.020),"light glass",.003,
                  (.032,0,0))
        bevel_box("Pressed windscreen wiper",(side*.076,.572,.448),(.069,.008,.008),"steel",.002,
                  (0,-.19*side,0))
    lamps(.748,.272,.181,.035)
    bevel_box("Vertical pressed radiator shell",(0,.774,.275),(.218,.033,.166),"silver",.016)
    bevel_box("Recessed radiator face",(0,.796,.276),(.179,.019,.130),"door rubber",.011)
    for j in range(7):
        bevel_box("Radiator chrome fin",((j-3)*.020,.811,.276),(.006,.009,.109),"silver",.001)
    bevel_box("Curved front steel bumper",(0,.779,.147),(.442,.055,.045),"steel",.014)
    bevel_box("Painted rear door threshold",(0,-.703,.169),(.447,.071,.046),"steel",.009)
    for side in (-1,1):
        bevel_box("Parcel shutter door",(side*.121,-.696,.419),(.223,.031,.361),"cab wine",.006)
        bevel_box("Flush rear ID plate",(side*.121,-.715,.453),(.148,.008,.119),"wine shade",.006)
        for z in (.287,.545):
            bevel_box("External stamped hinge",(side*.219,-.721,z),(.038,.016,.029),"steel",.006)
    bevel_box("Vertical loading door latch",(.015,-.728,.383),(.034,.016,.144),"steel",.005)
    rear_lamps(-.723,.266,.207)
    typeface("Rear postal lettering","MAIL", (0,-.736,.465),.087,0,"offwhite")
    wheels((-.460,.522),.238,.110,.110,"silver")

def flat_cabin_contour(w,low,hi):
    return roof_contour(w,low,hi-.038,hi)

def leopard_bus():
    """Late-1950s under-floor coachwork with articulated panoramic glazing."""
    # Front and rear sections vary width and belt profile. The center is long
    # and horizontal; the nose is straighter and less squared than the Regal.
    ribs=[(-.848,.218),(-.823,.271),(-.766,.290),(.754,.290),(.811,.269),(.846,.230)]
    profile_hull("Gently rounded integral lower coachwork",[(y,flat_cabin_contour(w,.171,.405)) for y,w in ribs],
                 "coach blue",["coach shadow","coach shadow","coach blue","coach sky","coach blue","coach blue",
                               "coach blue","coach blue","coach blue","coach blue","coach blue","coach sky","coach shadow"])
    profile_hull("Cream belt and broad cantrail",[(y,roof_contour(w*.985,.376,.641,.673)) for y,w in ribs],
                 "coach cream")
    profile_hull("Pressed raised roof panel",[(y,roof_contour(w*.88,.602,.671,.686)) for y,w in ribs[1:-1]],"coach cream")
    bevel_box("Roof induction vent forward",(0,.159,.700),(.252,.164,.038),"coach shadow",.016)
    bevel_box("Roof hatch aft",(0,-.451,.700),(.238,.176,.033),"enamel",.016)
    for side in (-1,1):
        wheel_arch(side*.292,.528,.108,.119,.047,"coach shadow")
        wheel_arch(side*.292,-.505,.108,.119,.047,"coach shadow")
        bevel_box("Continuous bright waist rail",(side*.293,-.021,.380),(.014,1.514,.022),"silver",.004)
        bevel_box("Darker skirt lower sill",(side*.292,-.028,.194),(.011,1.487,.030),"coach shadow",.005)
        # With local +Y as the nose, the opening is on the right side after
        # reflected-X OBJ import and the road vehicle orientation transform.
        if side==-1:
            spans=((-.66,.17),(-.43,.203),(-.197,.208),(.045,.213),(.294,.209),(.550,.218))
        else:
            spans=((-.66,.17),(-.435,.203),(-.196,.208),(.041,.209),(.279,.211))
        for y,w in spans:
            side_windows(side*.288,y,.501,w,.161)
        if side==1:
            for y in (.502,.661):
                bevel_box("Folding boarding door opening",(side*.293,y,.387),(.014,.147,.383),"door rubber",.006)
                bevel_box("Door enamel kick panel",(side*.304,y,.276),(.010,.130,.138),"coach blue",.004)
                side_windows(side*.308,y,.451,.122,.173)
            bevel_box("Entrance step nosing",(side*.298,.581,.185),(.048,.317,.031),"silver",.005)
        bevel_box("Lower luggage central hatch",(side*.294,-.165,.272),(.012,.442,.091),"coach sky",.008)
        bevel_box("Luggage lock",(side*.303,-.164,.289),(.010,.031,.015),"silver",.002)
        bevel_box("Mirror arm",(side*.278,.729,.528),(.073,.016,.018),"silver",.003)
        bevel_box("Panoramic mirror body",(side*.300,.745,.543),(.044,.024,.078),"coach shadow",.011)
    # A polygonal panoramic screen projects through the rounded front end.
    for side in (-1,1):
        # Front band accent bends between forward and side body faces.
        v=[(side*.014,.853,.453),(side*.176,.852,.447),(side*.235,.842,.441),
           (side*.233,.835,.585),(side*.173,.851,.602),(side*.015,.854,.605)]
        f=[tuple(reversed(range(6))) if side==1 else tuple(range(6))]
        add_mesh("Three-dimensional front wrap screen",v,f,"door rubber")
        center=Vector((side*.125,.856,.524))
        pane_v=[center+.91*(Vector(p)-center)+Vector((0,.007,0)) for p in v]
        add_mesh("Three-dimensional panoramic windshield",pane_v,f,"dark glass")
        bevel_box("Panoramic windshield reflection",(side*.088,.867,.572),(.145,.011,.019),"light glass",.004)
    bevel_box("Front divided mullion",(0,.869,.528),(.019,.018,.161),"enamel",.004)
    bevel_box("Inset destination blind",(0,.840,.622),(.316,.028,.061),"sign black",.010)
    typeface("Destination blind: Coast route","07 COAST",(0,.858,.624),.057,pi,"coach cream")
    bevel_box("Front grille silver trim",(0,.847,.286),(.306,.030,.096),"silver",.015)
    bevel_box("Front grille recess",(0,.864,.287),(.264,.017,.068),"coach shadow",.011)
    for j in range(4):
        bevel_box("Pressed grille fin",(0,.876,.263+j*.015),(.223,.008,.006),"silver",.001)
    lamps(.845,.295,.208,.035)
    bevel_box("Front curved bumper",(0,.846,.184),(.488,.059,.055),"steel",.014)
    for side in (-1,1):
        bevel_box("Front indicator lens",(side*.211,.867,.238),(.064,.016,.027),"indicator",.006)
        bevel_box("Rear corner window",(side*.130,-.851,.503),(.184,.019,.137),"dark glass",.014)
        bevel_box("Rear window reflection",(side*.128,-.863,.544),(.152,.006,.022),"light glass",.004)
    bevel_box("Rear engine service cover",(0,-.855,.289),(.339,.021,.154),"coach shadow",.006)
    for j in range(6):
        bevel_box("Rear cover louver",(0,-.869,.242+j*.019),(.244,.008,.006),"steel",.001)
    bevel_box("Rear impact rail",(0,-.856,.181),(.473,.052,.053),"steel",.012)
    rear_lamps(-.865,.296,.212)
    wheels((-.505,.528),.238,.108,.108,"silver")

MODELS=(("mail_van",mail_van),("leopard_bus",leopard_bus))

def export_palette():
    width,height=256,8
    padded=(KEYS+["enamel"]*32)[:32]
    line=b"".join(bytes.fromhex(PALETTE[key])*8 for key in padded)
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    img=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,2,0,0,0))
    img+=chunk(b"IDAT",zlib.compress((b"\0"+line)*height))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures/bl_road_fleet_palette.png").write_bytes(img)

def export(stem,create):
    begin()
    create()
    bpy.context.scene.name="LuanTTD / "+stem.replace("_"," ")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/{stem}.blend"),compress=True)
    objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    source=obj.matrix_world.copy()
    obj.matrix_world.identity()
    for vert in obj.data.vertices:
        vert.co=source@vert.co
    uv=obj.data.uv_layers.active or obj.data.uv_layers.new()
    for polygon in obj.data.polygons:
        idx=KEYS.index(obj.data.materials[polygon.material_index].name)
        for k in polygon.loop_indices:
            uv.data[k].uv=((idx+.5)/32,.5)
    obj.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/f"mods/luanttd_core/models/bl_{stem}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")

def review(path):
    begin()
    for name,creator in MODELS:
        for turn in (0,1):
            prior={o.name for o in bpy.context.scene.objects}
            creator()
            objects=[o for o in bpy.context.scene.objects if o.name not in prior]
            bpy.ops.object.select_all(action="DESELECT")
            for o in objects:
                o.select_set(True)
            bpy.context.view_layer.objects.active=objects[0]
            bpy.ops.object.join()
            ob=bpy.context.object
            source=ob.matrix_world.copy()
            ob.matrix_world.identity()
            for v in ob.data.vertices:
                p=source@v.co
                v.co=Vector((p.x*(-1 if turn else 1)+(.70 if name=="leopard_bus" else -.70),
                             p.y*(-1 if turn else 1)+(1.12 if turn else -1.12),p.z))
    bevel_box("Asphalt plinth",(0,0,-.064),(2.78,4.22,.128),"steel",.031)
    for yy in (-1.9,-1.37,-.82,-.27,.27,.82,1.37,1.90):
        bevel_box("Display lane paint",(0,yy,.0035),(.029,.24,.007),"enamel",.002)
    bpy.ops.object.camera_add(location=(5.12,7.45,6.66))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,.30))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=5.76
    scene=bpy.context.scene
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1470,1060
    scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new("Fleet model preview background")
    scene.world.color=(.14,.162,.17)
    sh=scene.display.shading
    sh.light="STUDIO"
    sh.color_type="MATERIAL"
    sh.background_type="WORLD"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    scene.render.filepath=path
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    export_palette()
    for key,f in MODELS:
        export(key,f)
    if (preview:=os.getenv("BAYLINE_ROAD_FLEET_REVIEW")):
        review(preview)
