"""Build LuanTTD's original early drop-side coal tipper in Blender 4.3+.

blender -b -t 2 --python-exit-code 1 --python tools/build_coal_tipper_art.py
Set BAYLINE_TIPPER_REVIEW=/tmp/coal-tipper.png for a four-view render.

The .blend includes editable coachwork and a separate cargo collection.
The OBJ pair shares the exact same entity origin, palette and geometry
for all non-cargo parts. Local -Z is the nose, tire contact is Y=0,
and the entity convention is ten OBJ units per Luanti node.
"""
from math import cos, pi, sin
import os
from pathlib import Path
from random import Random
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V

ROOT=V.ROOT
PALETTE={
    # Names used by the same reusable vehicle hardware/export helper.
    "chassis":"383839", "rubber":"2b2d32", "tread":"41434a", "silver":"c1c4bd",
    "steel":"788690", "nozzle":"4c5355", "bright lamp":"ffe4a6", "tail":"c94f3d",
    "dark glass":"2d4550", "light glass":"6594a0", "offwhite":"ece0bd", "enamel":"f2e2ba",
    "wine shade":"5e3930", "indicator":"df8f44", "door rubber":"313739",
    "umber":"745426", "golden ochre":"bb8d3d", "warm ochre":"cc9d48", "ochre shade":"87642b",
    "board edge":"898477", "bed paint":"5b5e5d", "oxide":"897658", "deck wood":"7a6851",
    "deck highlight":"9a8466", "bed underside":"545450", "lamp blue":"46626d",
    "coal dark":"292a2b", "coal middle":"3b4142", "coal reflection":"505759",
    "coal dust":"55514a", "ply":"a19682",
}
V.KEYS=list(PALETTE)
V.PALETTE=PALETTE
B=V.bevel_box
C=V.round_between
M=V.add_mesh
LIVERY="golden ochre"


def banded_roof(w,a,b,c):
    return V.roof_contour(w,a,b,c)

def cab_and_chassis():
    B("Drop-centre ladder chassis",(0,-.021,.142),(.445,1.354,.073),"chassis",.013)
    B("Transmission casing",(0,.275,.128),(.245,.447,.087),"nozzle",.018)
    B("Rear differential bridge",(0,-.471,.120),(.201,.188,.080),"chassis",.013)
    C("Exposed driveshaft",(0,-.470,.118),(0,.288,.112),.017,.017,"steel",10)
    for s in (-1,1):
        B("C-channel chassis rail",(s*.191,-.049,.166),(.054,1.286,.087),"nozzle",.007)
        B("Side running board",(s*.248,.145,.141),(.092,.366,.034),"chassis",.005)
        for j in range(5):
            B("Running board traction rib",(s*.247,.032+j*.051,.160),(.063,.014,.007),"tread",.002)
        B("Lamp mounting stem",(s*.192,.700,.240),(.061,.048,.025),"chassis",.003)
        # Separate front pressed-metal fenders and squarer rear wheel arches.
        V.wheel_arch(s*.288,.508,.106,.113,.123,"ochre shade")
        V.wheel_arch(s*.290,-.470,.106,.114,.050,"bed underside")
        B("Tail mudguard",(s*.266,-.607,.132),(.069,.040,.148),"rubber",.006)
    C("Dull exhaust line",(.168,.359,.113),(.187,-.580,.094),.009,.009,"steel",9)

    V.profile_hull("Shaped pressed cab shell",[
        (.070,banded_roof(.215,.192,.519,.579)),
        (.104,banded_roof(.248,.184,.572,.632)),
        (.310,banded_roof(.248,.184,.572,.632)),
        (.478,banded_roof(.226,.203,.553,.597)),
        (.522,banded_roof(.216,.215,.507,.544)),
    ],LIVERY,["ochre shade","ochre shade",LIVERY,LIVERY,"warm ochre","warm ochre",
              "warm ochre","warm ochre","warm ochre","warm ochre",LIVERY,LIVERY,"ochre shade"])
    V.profile_hull("Long narrow bonnet and pressed grille shoulders",[
        (.474,banded_roof(.206,.185,.381,.416)),
        (.533,banded_roof(.149,.185,.373,.393)),
        (.692,banded_roof(.130,.190,.353,.374)),
        (.739,banded_roof(.104,.198,.348,.367)),
    ],LIVERY)
    for s in (-1,1):
        V.side_windows(s*.247,.315,.479,.201,.150)
        B("Coachwork door perimeter", (s*.253,.290,.360),(.011,.253,.177),"ochre shade",.007)
        B("Drawer press inset on metal door",(s*.260,.290,.359),(.008,.235,.159),LIVERY,.005)
        B("Nickel door handle",(s*.267,.224,.404),(.010,.055,.015),"silver",.003)
        B("Quarter-light windscreen pillar",(s*.187,.533,.465),(.025,.023,.143),"ochre shade",.008)
        B("Stamped cab diagonal lower stripe",(s*.260,.254,.322),(.007,.180,.016),"warm ochre",.002)
        B("Door fleet number enamel plate",(s*.264,.299,.342),(.012,.127,.040),"umber",.005)
        V.typeface("Kestrel fleet badge","K  19",(s*.272,.300,.342),.034,s*pi/2,"offwhite")
        B("Vent frame brass trim",(s*.139,.594,.301),(.019,.161,.103),"umber",.009)
        for j in range(6):
            B("Pressed bonnet vent",(s*.150,.535+j*.022,.302),(.009,.010,.067),"ochre shade",.001)
        B("Mirror stem",(s*.251,.432,.494),(.059,.016,.011),"steel",.003)
        B("Wing mirror back",(s*.279,.438,.507),(.031,.022,.049),"lamp blue",.006)
        B("Quarter windscreen frame",(s*.093,.527,.468),(.168,.028,.130),"door rubber",.009,
          (.020,0,0))
        B("Quarter windscreen pane",(s*.093,.546,.468),(.151,.012,.111),"dark glass",.005,
          (.020,0,0))
        B("Reflected horizon in split screen",(s*.094,.553,.500),(.126,.006,.019),"light glass",.003)
        B("Screen wiper arm",(s*.077,.557,.435),(.071,.007,.006),"steel",.002,
          (0,-s*.20,0))
    B("Bold windscreen center rail",(0,.538,.470),(.014,.024,.127),"warm ochre",.004)
    B("Cab rear quarter window",(0,.064,.486),(.257,.024,.122),"door rubber",.008)
    B("Cab rear glazing",(0,.048,.486),(.236,.012,.104),"dark glass",.006)
    B("Tall decorated radiator badge",(0,.742,.288),(.200,.042,.166),"silver",.012)
    B("Shadowed radiator mesh",(0,.775,.291),(.167,.025,.139),"door rubber",.011)
    for j in range(8):
        B("Polished vertical radiator fin",((j-3.5)*.016,.791,.290),(.006,.006,.102),"steel",.001)
    B("Truck grille emblem",(0,.794,.348),(.040,.011,.020),"warm ochre",.004)
    V.lamps(.734,.265,.187,.030)
    B("Shaped front bumper on springs",(0,.764,.144),(.455,.056,.037),"steel",.012)
    B("Folding front towing hook",(0,.780,.121),(.054,.028,.038),"chassis",.005)
    B("Front license tag",(0,.797,.140),(.127,.014,.032),"door rubber",.004)
    V.typeface("Front fleet plate","K 19",(0,.804,.14),.030,pi,"offwhite")
    B("Rear bumper",(0,-.691,.157),(.488,.061,.042),"steel",.010)
    V.wheels((-.470,.508),.239,.106,.106,"silver")


def tipper_bed():
    # The body is an actual open box, not a surface at the tops of the boards.
    ymin,ymax,zfloor=-.722,.110,.229
    w,d=.505,ymax-ymin
    B("Raised tipping platform",(0,(ymin+ymax)/2,zfloor-.018),(w,d,.043),"bed underside",.011)
    B("Steel deck mounting tray",(0,(ymin+ymax)/2,zfloor+.003),(w-.022,d-.019,.022),"bed paint",.008)
    for j in range(7):
        y=ymin+.062+j*.116
        B("Working hardwood deck board",(0,y,zfloor+.017),(w-.049,.111,.019),
          "deck highlight" if j in (1,4) else "deck wood",.003)
        for s in (-1,1):
            C("Flush deck rivet",(s*.197,y,zfloor+.026),(s*.197,y,zfloor+.030),.006,.006,
              "steel",7)
    for s in (-1,1):
        x=s*.257
        B("Hinged drop-side heavy bottom frame",(x,-.303,.258),(.038,.831,.045),"bed paint",.009)
        B("Drop-side pressed shell section",(x,-.303,.332),(.036,.826,.157),"bed paint",.006)
        for j in range(3):
            z=.287+j*.045
            B("Stamped strengthening rib",(x+s*.020,-.303,z),(.010,.799,.014),
              "board edge" if j==2 else "nozzle",.003)
        for y in (-.666,-.441,-.205,.041):
            B("Vertical folded bed stiffener",(x+s*.024,y,.333),(.016,.023,.145),"board edge",.005)
            B("Hinged rail bottom pin",(x+s*.035,y,.257),(.016,.039,.021),"steel",.004)
        B("Rolled top edge of drop-side",(x,-.303,.407),(.043,.837,.027),"board edge",.008)
        B("Cab shield edge pillar",(x,.090,.363),(.046,.051,.253),"bed paint",.007)
        B("Dump bed hoist underbody rail",(s*.169,-.302,.202),(.059,.818,.061),"chassis",.007)
        C("Under-deck hydraulic piston",(s*.085,-.458,.168),(s*.085,-.056,.202),
          .024,.020,"steel",9)
    B("Forward steel load shield",(0,.094,.367),(.505,.062,.265),"bed paint",.009)
    for y in (.064,.122):
        B("Rolled top edge of front load shield",(0,y,.484),(.511,.028,.028),"board edge",.003)
    for x in (-.165,0,.165):
        B("Forward bed upright",(x,.058,.355),(.027,.022,.213),"nozzle",.004)
    B("Rear hinged tailgate five-board section",(0,-.717,.337),(.508,.037,.172),"bed paint",.007)
    for z in (.279,.310,.341,.372,.402):
        B("Tailgate pressed seam",(0,-.738,z),(.483,.007,.011),"nozzle",.002)
    for s in (-1,1):
        B("Tailgate end latching lever",(s*.228,-.743,.356),(.027,.026,.122),"board edge",.006)
        B("Dump tailgate lower hinge tongue",(s*.188,-.742,.278),(.055,.026,.036),"steel",.004)
        B("Left/right rear red lamp mounting",(s*.184,-.733,.205),(.057,.019,.037),"wine shade",.006)
        B("Rear red stop lamp lens",(s*.184,-.749,.206),(.041,.015,.024),"tail",.004)
        B("Rear amber turn lamp lens",(s*.242,-.746,.206),(.034,.014,.018),"indicator",.002)
    B("Rear license plate daylight surround",(0,-.741,.232),(.126,.019,.037),"steel",.007)
    B("Rear license plate face",(0,-.754,.233),(.108,.011,.025),"door rubber",.004)
    V.typeface("Rear fleet plate","K 19",(0,-.762,.233),.029,0,"offwhite")


def load_rock(tag,x,y,z,rx,ry,h,rng):
    # Angular solids with different dark luster on individual facets.
    samples=6
    verts=[]
    for k in range(samples):
        angle=2*pi*k/samples
        r=rng.uniform(.73,1.0)
        verts.append((x+cos(angle)*rx*r,y+sin(angle)*ry*r,z+rng.uniform(-.007,.012)))
    for k in range(samples):
        angle=2*pi*(k+.31)/samples
        r=rng.uniform(.44,.84)
        verts.append((x+cos(angle)*rx*r,y+sin(angle)*ry*r,z+h*rng.uniform(.55,.89)))
    verts.append((x-rx*.13,y+ry*.17,z+h))
    faces=[tuple(reversed(range(samples)))]
    surfaces=["coal dark"]
    for k in range(samples):
        j=(k+1)%samples
        faces += [(k,j,j+samples),(k,j+samples,k+samples),(k+samples,j+samples,2*samples)]
        surfaces += [rng.choice(("coal dark","coal middle","coal middle")),
                     rng.choice(("coal dark","coal middle","coal reflection")),
                      rng.choice(("coal middle","coal reflection","coal reflection","coal dust"))]
    M(tag,verts,faces,surfaces)


def cargo():
    rng=Random(43219)
    # Narrow mound covers most floor and rises above the sides, but always
    # stays within their inside plan bounds and the lorry's top silhouette.
    ext=(.212,.384)
    pts=[]
    for layer,(height,step) in enumerate(((.280,.98),(.400,.97),(.476,.57))):
        for k in range(10):
            angle=k*2*pi/10
            sc=rng.uniform(.89,1.0)
            pts.append((ext[0]*step*sc*cos(angle), -.321+ext[1]*step*sc*sin(angle),
                        height+rng.uniform(-.011,.014)))
    pts.append((-.034,-.328,.517))
    faces=[tuple(reversed(range(10)))]
    surfaces=["coal dark"]
    for l in range(2):
        for i in range(10):
            j=(i+1)%10
            a=l*10+i;b=l*10+j;c=b+10;d=a+10
            faces.extend(((a,b,c),(a,c,d)))
            surfaces.extend((rng.choice(("coal dark","coal middle")),
                             rng.choice(("coal dark","coal middle","coal reflection"))))
    for i in range(10):
        faces.append((20+i,20+(i+1)%10,30))
        surfaces.append(rng.choice(("coal dark","coal middle","coal reflection")))
    M("Full bed irregular coal bulk",pts,faces,surfaces)
    for j in range(5):
        y=-.601+j*.140
        for k in range(5):
            x=(k-2)*.066+rng.uniform(-.010,.012)
            top=max(0,1-(abs(x)/.203)**2-((y+.323)/.410)**2)
            load_rock("Broken coal lump",x,y,.389+.108*top,
                      rng.uniform(.031,.056),rng.uniform(.034,.065),rng.uniform(.025,.055),rng)
    for x,y in ((.110,-.363),(-.125,-.265),(.032,-.462),(-.048,-.208)):
        load_rock("Dull splinter of coal",x,y,.484,.049,.071,.056,rng)


def group(name, objects):
    collection=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    for obj in list(objects):
        for old in tuple(obj.users_collection):
            old.objects.unlink(obj)
        collection.objects.link(obj)
    return collection


def full_scene():
    V.begin()
    cab_and_chassis()
    tipper_bed()
    base=list(bpy.context.scene.objects)
    cargo()
    load=[obj for obj in bpy.context.scene.objects if obj not in base]
    group("A · Coachwork and tipping body",base)
    group("B · Loose coal load (hide for empty body)",load)
    bpy.context.scene.name="LuanTTD / Kestrel Coal Tipper"
    return base,load


def palette():
    values=(list(PALETTE)+["enamel"]*32)[:32]
    assert len(PALETTE)<=32
    row=b"".join(bytes.fromhex(PALETTE[name])*8 for name in values)
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    img=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    img+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/bayline/textures/bl_coal_tipper_palette.png").write_bytes(img)


def joined(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    transform=ob.matrix_world.copy()
    ob.matrix_world.identity()
    for v in ob.data.vertices:
        v.co=transform@v.co
    return ob


def export(stem,objects):
    ob=joined(objects)
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    for face in ob.data.polygons:
        key=ob.data.materials[face.material_index].name
        idx=list(PALETTE).index(key)
        for loop in face.loop_indices:
            uv.data[loop].uv=((idx+.5)/32,.5)
    ob.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/f"mods/bayline/models/bl_{stem}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")


def preview(path):
    V.begin()
    for full in (False,True):
        for reverse in (False,True):
            before=set(bpy.context.scene.objects)
            cab_and_chassis()
            tipper_bed()
            if full:
                cargo()
            obj=joined([o for o in bpy.context.scene.objects if o not in before])
            for v in obj.data.vertices:
                x,y,z=v.co
                v.co=Vector(((x if not reverse else -x)+(0.69 if full else -.69),
                             (y if not reverse else -y)+(1.10 if reverse else -1.10),z))
    B("Stone loading layby", (0,0,-.065),(2.75,4.25,.130),"bed paint",.034)
    for yy in (-1.68,-1.10,-.54,.0,.58,1.16,1.72):
        B("Layby traffic lane dash", (0,yy,.005),(.032,.263,.010),"ply",.001)
    bpy.ops.object.camera_add(location=(5.4,7.6,5.6))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.28))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=5.69
    scene=bpy.context.scene
    scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1470,1030
    scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new("Neutral yard backdrop")
    scene.world.color=(.155,.173,.174)
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
    palette()
    base,load=full_scene()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/coal_tipper.blend"),compress=True)
    export("coal_tipper_loaded",base+load)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/"art/coal_tipper.blend"))
    export("coal_tipper",list(bpy.data.collections["A · Coachwork and tipping body"].objects))
    if (p:=os.getenv("BAYLINE_TIPPER_REVIEW")):
        preview(p)
