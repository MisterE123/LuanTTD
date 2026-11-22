"""Build original early airliner art for Bakewell Cotswald LB-3, stock 219.

blender -b -t 3 --python-exit-code 1 --python tools/build_bakewell_cotswald_art.py
Set BAKEWELL_REVIEW=/workspace/.../bakewell.png to capture an apron portrait.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V
from build_coleman_count_art import group, merge

ROOT = V.ROOT
M, C, B = V.add_mesh, V.round_between, V.bevel_box
STEM = "bl_bakewell_cotswald"
P = {
    "pearl crown":"e8e3d4", "warm shoulder":"d3cbb3", "cast alloy":"acb3af",
    "alloy light":"ced3ce", "wing silver":"aebec0", "alloy shade":"75878d",
    "underside":"8e9da2", "tin ribs":"c4cac1", "wine":"934333", "deep wine":"65362c",
    "gold trim":"d4a262", "side glass":"334852", "front glass":"304046", "sky glass":"65868d",
    "smoke":"3e4c4d", "burnished bronze":"807467", "engine iron":"4d5350", "blade":"465657",
    "blade backs":"65716e", "prop tips":"e3bd67", "tyre":"282f31", "tread":"30393b",
    "hub":"77888b", "main strut":"626d6d", "red light":"a9483d", "green light":"4d826a",
    "land light":"f6db9d", "gear pit":"273130", "apron":"7d7d76", "joint":"4a5654", "grass":"667d63", "alloy reserve":"b5c1bd",
}
KEYS = tuple(P)
# Station in +Y, half-width and floor, side waist, crown (world nodes).
F = (
    (-.734,.018,.108,.141,.172),(-.654,.051,.104,.158,.213),(-.543,.089,.112,.183,.268),
    (-.426,.116,.124,.224,.324),(-.284,.139,.128,.266,.395),(-.142,.149,.131,.290,.433),
    (.014,.153,.135,.301,.449),(.188,.153,.148,.310,.454),(.331,.148,.160,.315,.452),
    (.454,.137,.179,.325,.445),(.535,.125,.196,.330,.427),(.594,.107,.216,.328,.402),
    (.642,.073,.240,.325,.370),(.672,.031,.266,.318,.345),(.682,.009,.287,.315,.329),
)
# Wing stations: span, leading Y, trailing Y, chord height, foil thickness.
W = ((.091,.322,-.409,.236,.078),(.238,.322,-.393,.229,.077),(.405,.303,-.344,.241,.066),
     (.629,.254,-.239,.257,.050),(.811,.170,-.173,.278,.036),(.895,.107,-.139,.289,.024),
     (.930,.058,-.109,.294,.011),(.937,.002,-.061,.295,.004))


def profile(y):
    for a,b in zip(F,F[1:]):
        if a[0]<=y<=b[0]:
            t=(y-a[0])/(b[0]-a[0])
            return [(1-t)*p+t*q for p,q in zip(a[1:],b[1:])]
    raise ValueError(y)


def contour(w,lo,z,hi):
    # CCW as seen in the X/Z plane, with the waist livery in the shell.
    k=hi-z
    return [(-w*.52,lo+.005),(w*.52,lo+.005),(w*.82,lo+.025),(w*.973,z-.060),
            (w,z-.033),(w,z-.014),(w,z+.004),(w*.987,z+.023),(w*.91,z+.42*k),
            (w*.62,z+.87*k),(0,hi),(-w*.62,z+.87*k),(-w*.91,z+.42*k),
            (-w*.987,z+.023),(-w,z+.004),(-w,z-.014),(-w,z-.033),(-w*.973,z-.060),
            (-w*.82,lo+.025)]


def hull():
    colors=("underside","alloy shade","cast alloy","alloy light","deep wine","wine","gold trim",
            "warm shoulder","pearl crown","pearl crown","pearl crown","pearl crown","warm shoulder",
            "gold trim","wine","deep wine","alloy light","cast alloy","alloy shade")
    o=V.profile_hull("Rounded riveted low-belly passenger cabin",
                     [(y,contour(w,k,z,h)) for y,w,k,z,h in F],"cast alloy",list(colors))
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    bvh=BVHTree.FromPolygons([v.co for v in o.data.vertices],[tuple(p.vertices) for p in o.data.polygons])

    def skin(name, pts, direction, mat, lift=.0008, curved=False):
        def project(u,v):
            if direction==0: a,d=(u,1.2,v),(0,-1,0)
            else: a,d=(direction*1.2,u,v),(-direction,0,0)
            xyz,normal,_,_=bvh.ray_cast(a,d)
            assert xyz is not None,(name,pts,(u,v))
            return xyz + normal*lift
        if curved:
            a,b,c,d=map(Vector,pts)
            k=5
            vv=[project(*((1-i/k)*((1-j/k)*a+(j/k)*b)+(i/k)*((1-j/k)*d+(j/k)*c)))
                for i in range(k+1) for j in range(k+1)]
            q=k+1
            faces=[(i*q+j,i*q+j+1,(i+1)*q+j+1,(i+1)*q+j)
                   for i in range(k) for j in range(k)]
        else:
            vv=[project(u,v) for u,v in pts]
            faces=[tuple(range(len(vv)))]
        # Winding follows the actual visible shell on either side.
        outward=Vector((0,1,0) if direction==0 else (direction,0,0))
        faces=[f if (vv[f[1]]-vv[f[0]]).cross(vv[f[2]]-vv[f[0]]).dot(outward)>0
               else tuple(reversed(f)) for f in faces]
        return M(name,vv,faces,mat)

    for side in (-1,1):
        for y in (-.34,-.261,-.182,-.103,-.024,.055,.134,.213,.292):
            w,low,z,hi=profile(y)
            # Octagonal opening follows the fuselage (no protruding flat box).
            verts=[(y+.025*cos(i*pi/4),z+.039+.022*sin(i*pi/4)) for i in range(8)]
            skin("Raised bright passenger window frame",verts,side,"tin ribs")
            points=[(y+(a-y)*.79,z+.039+(b-z-.039)*.73) for a,b in verts]
            skin("Dark unpressurized cabin window",points,side,"side glass",.0021)
            glare=[(y-.013,z+.046),(y+.008,z+.051),(y+.015,z+.047),(y-.007,z+.042)]
            skin("Window sky glint",glare,side,"sky glass",.0027)
        # Slit dark line bordering the tall aft side service door.
        door_y=-.418
        w,lo,z,hi=profile(door_y)
        skin("Pressed aft cabin door shadow",
             [(door_y-.017,z-.070),(door_y+.024,z-.071),(door_y+.027,z+.044),
              (door_y+.012,z+.062),(door_y-.016,z+.054)],side,"deep wine",.0012)
        skin("Warm silver cabin door insert",
             [(door_y-.014,z-.065),(door_y+.021,z-.065),(door_y+.024,z+.041),
              (door_y+.011,z+.057),(door_y-.013,z+.050)],side,"warm shoulder",.0024)
        # Six panes on forward body, safely inside the section profile.
        skin("Angular pilot side quarter glass",[(.493,.370),(.541,.369),(.575,.390),(.530,.402)],
             side,"side glass",.0026,True)
        skin("Side quarter glass return",[(.509,.394),(.530,.397),(.547,.393),(.526,.391)],
             side,"sky glass",.0032,True)
        # Points projected along -Y facing the nose, not laid on top as stickers.
        pane=[(.006*side,.360),(.053*side,.355),(.065*side,.379),(.017*side,.399)]
        skin("Slanted windscreen under silver mullion",list(reversed(pane)) if side<0 else pane,
             0,"front glass",.0027,True)
        C("Twin exhaust cabin vents",(side*.13,-.124,.191),(side*.139,-.141,.184),
          .007,.006,"burnished bronze",6)
    C("Prow aerial",(0,.427,.445),(0,.404,.505),.004,.0018,"alloy shade",7)


def foil(name, rows, side, upper, lower):
    air=((0,.30),(.052,.71),(.20,1),(.52,.69),(.83,.27),(1,.02),
         (.78,-.17),(.27,-.36),(.086,-.22))
    vv=[]
    for x,a,b,z,t in rows:
        vv.extend((side*x,a+(b-a)*u,z+t*h) for u,h in air)
    k=len(air)
    faces=[tuple(reversed(range(k))),tuple(range((len(rows)-1)*k,len(rows)*k))]
    material=[upper,upper]
    for m in range(len(rows)-1):
        for i in range(k):
            j=(i+1)%k
            faces.append((m*k+i,m*k+j,(m+1)*k+j,(m+1)*k+i))
            material.append(upper if i<5 else lower)
    # Cross-section traverses the upper foil forward to aft; side=+1 is a reflection.
    if side>0: faces=[tuple(reversed(f)) for f in faces]
    o=M(name,vv,faces,material)
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    return o


def span():
    for side in (-1,1):
        foil("Swept tapered low-mounted wing",W,side,"wing silver","underside")
        foil("Tailplane and articulated elevator",
             ((.031,-.473,-.694,.175,.033),(.127,-.492,-.714,.180,.027),
              (.241,-.538,-.728,.194,.018),(.334,-.594,-.709,.204,.010),(.357,-.637,-.681,.205,.004)),
             side,"cast alloy","alloy shade")
        # A narrow trailing edge panel matches the wing taper and reads panel engraving.
        foil("Outboard corrugated aileron",
             ((.419,-.323,-.344,.246,.012),(.628,-.222,-.237,.263,.011),
              (.811,-.159,-.172,.283,.010),(.889,-.126,-.138,.294,.005)),
             side,"tin ribs","alloy shade")
        C("Oil radiator under inner wing",(side*.423,.148,.218),(side*.423,.004,.211),
          .025,.017,"alloy shade",10)
        C("Navigation light",(side*.928,.040,.300),(side*.938,.037,.300),.012,.008,
          "red light" if side<0 else "green light",8)
        C("Warm landing light lens",(side*.545,.276,.285),(side*.545,.282,.286),
          .018,.015,"land light",9)
    # Fin and rudder as rounded, tapering bands with a distinct burgundy band.
    vv=[]
    for z,a,b,w in ((.148,-.431,-.689,.051),(.264,-.455,-.720,.042),
                    (.379,-.515,-.731,.034),(.506,-.571,-.732,.025),
                    (.595,-.627,-.722,.017),(.628,-.660,-.701,.006)):
        vv.extend([(0,a,z),(w,a*.68+b*.32,z),(w*.67,a*.19+b*.81,z),(0,b,z),
                   (-w*.67,a*.19+b*.81,z),(-w,a*.68+b*.32,z)])
    faces=[tuple(reversed(range(6))),tuple(range(30,36))]
    mats=["cast alloy","pearl crown"]
    for m,key in enumerate(("cast alloy","wing silver","wine","pearl crown","tin ribs")):
        for i in range(6):
            ii=(i+1)%6
            faces.append((m*6+i,m*6+ii,(m+1)*6+ii,(m+1)*6+i))
            mats.append(key)
    M("Radiused burgundy tail fin",vv,faces,mats)


NACELLE=.322
PROPY=.431
PROPZ=.274


def engine(x):
    sections=((-.254,.018,.226),(-.172,.052,.242),(-.073,.083,.253),
              (.036,.097,.254),(.178,.100,.257),(.307,.103,.265),(.356,.109,.271),
              (.396,.105,.274),(.412,.091,.274))
    stations=[(y,[(x+r*cos(k*2*pi/14),z+r*sin(k*2*pi/14)) for k in range(14)]) for y,r,z in sections]
    o=V.profile_hull("Tapered twin radial nacelle polished annular cowl",stations,"cast alloy")
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    C("Oxblood cowling seam",(x,.349,.271),(x,.362,.272),.111,.112,"deep wine",16)
    C("Dark radial cooling intake",(x,.411,PROPZ),(x,.417,PROPZ),.081,.079,"smoke",14)
    for k in range(9):
        a=k*pi*2/9
        dx,dz=cos(a),sin(a)
        C("Exposed radial fin heads",(x+dx*.023,.418,PROPZ+dz*.023),
          (x+dx*.068,.420,PROPZ+dz*.068),.010,.012,"engine iron",6)
    C("Propeller alloy cap",(x,.417,PROPZ),(x,.454,PROPZ),.029,.009,"alloy light",12)
    for k in range(3):
        a=.18+k*pi*2/3
        dx,dz=cos(a),sin(a)
        tx,tz=-dz,dx
        def q(r,tw,forward): return x+dx*r+tx*tw,PROPY+forward,PROPZ+dz*r+tz*tw
        vertices=[]
        rails=((.020,-.010,.010,-.009,-.016),(.130,-.032,.018,.006,-.009),
               (.172,-.029,.014,.011,-.004),(.201,-.021,.009,.015,.001),
               (.212,-.011,-.005,.019,.014))
        for r,wide,narrow,forward,rear in rails:
            vertices.extend([q(r,wide,forward+.0013),q(r,narrow,rear+.0013),
                             q(r,narrow,rear-.0013),q(r,wide,forward-.0013)])
        faces=[(3,2,1,0),(16,17,18,19)]
        mats=["blade","prop tips"]
        for i in range(len(rails)-1):
            for j in range(4):
                k=(j+1)%4
                faces.append((i*4+j,(i+1)*4+j,(i+1)*4+k,i*4+k))
                mats.append("prop tips" if i>=2 else "blade" if j<2 else "blade backs")
        M("Scimitar three-blade propeller with actual painted tips",vertices,faces,mats)
    sign=1 if x>0 else -1
    C("Stack exhaust pipe",(x+sign*.076,.257,.213),(x+sign*.116,.201,.199),.015,.010,"burnished bronze",9)
    C("Exhaust outlet",(x+sign*.115,.202,.199),(x+sign*.118,.197,.198),.009,.009,"smoke",9)


def wheels(down):
    for x,y,r,width,low in ((-NACELLE,.159,.078,.060,.158),(NACELLE,.159,.078,.060,.158),
                            (0,-.615,.038,.030,.110)):
        pocket_width=.072 if x else .040
        if not down:
            for side in (-1,1):
                B("Flush retracted landing-gear door leaf",(x+side*pocket_width*.253,y,low),
                  (pocket_width*.462,.155 if x else .082,.009),"cast alloy",.004)
            continue
        B("Visible recessed wheel well",(x,y,low),(.079 if x else .046,.155 if x else .078,.009),"gear pit",.005)
        for side in (-1,1):
            C("Main landing strut and axle fork",(x+side*width*.37,y,r),(x+side*.024,y-.041,low+.035),
              .011 if x else .006,.014 if x else .007,"main strut",8)
        # Sixteen segments include a vertex at bottom, with world UP = source Z.
        t=[(ux,y+r*cos(k*pi/8),r+r*sin(k*pi/8))
           for ux in (x-width*.50,x+width*.50) for k in range(16)]
        faces=[tuple(reversed(range(16))),tuple(range(16,32))]
        faces += [(k,(k+1)%16,(k+1)%16+16,k+16) for k in range(16)]
        M("Tail wheel tyre" if x==0 else "Twin main tyre at ground datum",t,faces,["tyre"]*2+["tread"]*16)
        for side in (-1,1):
            C("Wheel pressed hub cover",(x+side*width*.501,y,r),(x+side*(width*.5+.005),y,r),
                r*.53,r*.39,"hub",10)
        C("Oleo reinforcing diagonal",(x,y,r+.018),(x,y+.037,low+.032),
          .008 if x else .004,.010 if x else .005,"alloy light",7)


def start():
    V.PALETTE=P
    V.KEYS=list(KEYS)
    V.begin()


def plane():
    hull()
    span()
    for x in (-NACELLE,NACELLE): engine(x)


def atlas():
    def chunk(k,d): return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    w=len(KEYS)*8
    data=b"".join(bytes.fromhex(P[k])*8 for k in KEYS)
    col=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,8,8,2,0,0,0))
    col+=chunk(b"IDAT",zlib.compress((b"\0"+data)*8,9))+chunk(b"IEND",b"")
    (ROOT/"mods/bayline/textures"/f"{STEM}_atlas.png").write_bytes(col)


def compact_obj(path):
    # Strip text-only precision and duplicates, not authored geometry.
    # Positional error is < .00001 world nodes; normal rounding < .1 degree.
    new=[]
    normal_map,normal_ids=[],{}
    for line in path.read_text().splitlines():
        tag,*values=line.split()
        if tag in ("v","vn"):
            n=4 if tag=="v" else 3
            compact=" ".join((f"{float(v):.{n}f}".rstrip("0").rstrip(".")).replace("-0", "0", 1)
                             if round(float(v),n)==0 else f"{float(v):.{n}f}".rstrip("0").rstrip(".")
                             for v in values)
            if tag=="vn":
                if compact not in normal_ids:
                    normal_ids[compact]=len(normal_ids)+1
                    new.append(f"{tag} {compact}")
                normal_map.append(normal_ids[compact])
            else:
                new.append(f"{tag} {compact}")
        elif tag=="f":
            face=[]
            for v in values:
                a,b,c=v.split("/")
                face.append(f"{a}/{b}/{normal_map[int(c)-1]}")
            new.append("f "+" ".join(face))
        elif tag in ("o","vt","s","g"):
            new.append(line)
    path.write_text("\n".join(new)+"\n")


def export():
    start()
    plane()
    scene=bpy.context.scene
    scene.name="LuanTTD · Bakewell Cotswald LB-3 · stock aircraft 219"
    scene["stock_engine_id"]=219
    scene["baked_gear_contact_z"]=0.0
    scene["coord_frame"]="+Y nose/+Z up in Blender; -Z nose/+Y up in Luanti OBJ"
    main=list(scene.objects)
    wheels(True)
    down=[o for o in scene.objects if o not in main]
    wheels(False)
    up=[o for o in scene.objects if o not in main and o not in down]
    group("Airframe — nose, cabin, wing, rounded fin, twin radials",main)
    group("Ground — main undercarriage and tail wheel",down)
    flight=group("Flight — retracted gear (toggle collections)",up,True)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                frame=area.spaces.active
                frame.region_3d.view_location=Vector((0,0,.24))
                frame.region_3d.view_distance=2.95
                frame.region_3d.view_rotation=Vector((.89,.5,.61)).to_track_quat("Z","Y")
                frame.shading.color_type="MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/bakewell_cotswald.blend"),compress=True)
    flight.hide_viewport=False
    bpy.context.view_layer.update()
    for suffix,gear in (("",down),("_flight",up)):
        copy=[]
        for o in main+gear:
            d=o.copy()
            d.data=o.data.copy()
            scene.collection.objects.link(d)
            copy.append(d)
        bpy.context.view_layer.update()
        o=merge(copy)
        o.name="Bakewell_Cotswald_LB3_219"+suffix
        uv=o.data.uv_layers.active or o.data.uv_layers.new()
        uv.active_render=True
        for face in o.data.polygons:
            idx=KEYS.index(o.data.materials[face.material_index].name)
            for i in face.loop_indices: uv.data[i].uv=((idx+.5)/len(KEYS),.5)
        o.data.update()
        path=ROOT/"mods/bayline/models"/f"{STEM}{suffix}.obj"
        bpy.ops.wm.obj_export(filepath=str(path),export_selected_objects=True,
            export_materials=False,export_uv=True,export_normals=True,export_triangulated_mesh=False,
            global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")
        compact_obj(path)
        bpy.data.objects.remove(o,do_unlink=True)


def review(path):
    start()
    plane()
    wheels(True)
    B("Apron", (0,0,-.06),(5,5,.12),"apron",.01)
    for u in (-1,0,1):
        B("Apron slab joint",(u,0,.001),(.006,4.9,.002),"joint")
        B("Apron slab joint",(0,u,.001),(4.9,.006,.002),"joint")
    bpy.ops.object.camera_add(location=(3.17,3.85,2.70))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,-.03,.24))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=2.42
    s=bpy.context.scene
    s.camera=camera
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1200,800
    s.render.resolution_percentage=100
    shade=s.display.shading
    shade.light="STUDIO"
    shade.color_type="MATERIAL"
    shade.show_shadows=True
    shade.show_cavity=True
    shade.cavity_type="BOTH"
    s.render.filepath=path
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    atlas()
    export()
    if (p:=os.getenv("BAKEWELL_REVIEW")): review(p)
