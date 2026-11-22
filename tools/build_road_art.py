"""Original road architecture. Run: blender -b -t 2 --python tools/build_road_art.py."""
from pathlib import Path
import math, struct, zlib
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PALETTE = {
    "Pavement": "a6a298", "Kerbstone": "c5bcb0", "Cast iron": "244a48",
    "Forest enamel": "37756a", "Cream enamel": "e3d5ac", "Oak": "aa6b3d",
    "Lichen trim": "7e9b82", "Poster dark": "314850", "Poster light": "edbd56",
    "Red brick": "9f5542", "Light brick": "b96d55", "Brick shadow": "754638",
    "Slate": "435964", "Slate light": "667685", "Door steel": "698b7e",
    "Window": "8fb7be",
}

def start(label):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.name = label
    bpy.context.scene.view_settings.view_transform = "Standard"
    bpy.context.preferences.filepaths.save_version = 0
    for name, rgb in PALETTE.items():
        vals = [int(rgb[i:i+2], 16)/255 for i in (0, 2, 4)]
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*[q/12.92 if q < .04045 else ((q+.055)/1.055)**2.4 for q in vals], 1)

def slab(name, location, dims, material, bevel=0, tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    ob = bpy.context.object
    ob.name = name
    ob.scale = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = ob.modifiers.new("Edge bevel", "BEVEL")
        mod.width, mod.segments = bevel, 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.rotation_euler.x = tilt
    ob.data.materials.append(bpy.data.materials[material])
    return ob

def shelter():
    # Street is local +Y. Open bays use actual holes rather than painted-on windows.
    slab("Inset concrete waiting platform", (0,0,.030), (1.70,.55,.06), "Pavement", .018)
    for i in range(8):
        slab("Dressed kerb block", (-.735+.21*i,.264,.040), (.205,.05,.075), "Kerbstone", .004)
    for x in (-.49,.49):
        for y in (-.16,.11):
            slab("Cast-iron upright", (x,y,.295), (.035,.035,.47), "Cast iron", .005)
    for h in (.12,.25,.405):
        slab("Rear screen rail", (0,-.169,h), (1.00,.029,.029), "Cast iron", .004)
    for i in range(13):
        slab("Rear screen board", (-.455+.076*i,-.177,.193), (.061,.025,.15), "Forest enamel", .003)
    for x in (-.31,.31):
        slab("Bench cast bracket", (x,-.044,.121), (.035,.13,.13), "Cast iron")
    for y in (-.094,-.045,.004):
        slab("Oak seat slat", (0,y,.194), (.81,.042,.025), "Oak", .004)
    slab("Oak backrest", (0,-.135,.278), (.81,.027,.063), "Oak", .004)
    for y,angle in ((-.114,-.17),(.061,.17)):
        # Pitched standing seam roof.
        slab("Pitched canopy", (0,y,.515), (1.15,.182,.048), "Forest enamel", .009, angle)
    slab("Roof ridge cap", (0,-.026,.542), (1.16,.048,.034), "Lichen trim", .008)
    slab("Contrasting canopy fascia", (0,.151,.501), (1.15,.027,.045), "Cream enamel", .006)
    slab("Flag post", (.685,.072,.341), (.038,.039,.58), "Cast iron", .005)
    slab("Porcelain stop flag", (.685,.081,.615), (.177,.043,.145), "Cream enamel", .015)
    for axis in (-1,1):
        y=.081+.025*axis
        slab("Bus emblem", (.685,y,.632), (.106,.003,.042), "Forest enamel", .004)
        for x in (.654,.716):
            slab("Bus emblem wheel", (x,y,.605), (.022,.004,.021), "Poster dark")
    slab("Timetable backing", (-.665,-.074,.326), (.136,.039,.167), "Poster dark", .006)
    slab("Timetable paper", (-.665,-.051,.328), (.113,.004,.142), "Cream enamel")
    for j in range(5):
        slab("Timetable rule", (-.665,-.048,.282+j*.019), (.078,.003,.005), "Poster light" if j==4 else "Poster dark")

def depot():
    # Door faces local +Y; roof spans an open drive-through-width bay.
    slab("Concrete shop floor", (0,-.065,.030), (1.60,1.73,.061), "Pavement", .016)
    slab("Apron ramp", (0,.83,.017), (.80,.30,.034), "Pavement", .007)
    for x in (-.66,.66):
        slab("Brick side wall", (x,-.19,.34), (.13,1.34,.63), "Red brick", .012)
        slab("Street pilaster", (x,.50,.345), (.23,.22,.65), "Red brick", .009)
        for j in range(7):
            slab("Brick end course", (x,.614,.095+.076*j), (.20,.016,.010), "Brick shadow")
        for j in range(3):
            y=-.59+j*.38
            slab("Stone window sill", (x*1.105,y,.298), (.032,.26,.036), "Kerbstone")
            slab("Workshop window frame", (x*1.098,y,.416), (.025,.237,.200), "Cream enamel", .006)
            for side in (-1,1):
                slab("Workshop window light", (x*1.120,y+side*.050,.418), (.009,.086,.158), "Window")
    slab("Rear wall", (0,-.813,.34), (1.29,.106,.63), "Red brick", .010)
    slab("Steel lintel", (0,.58,.635), (1.39,.16,.107), "Cream enamel", .012)
    slab("Recessed depot sign", (0,.664,.643), (.58,.022,.068), "Forest enamel", .009)
    for j in range(3):
        slab("Paint on workshop sign", (-.114+j*.114,.677,.643), (.069,.006,.019), "Cream enamel")
    # Roof slope runs sideways about a centered ridge.
    for side in (-1,1):
        r=slab("Slate roof slope", (side*.365,-.139,.759), (.772,1.59,.065), "Slate", .013)
        r.rotation_euler.y=side*.32
        for j in range(5):
            x=side*(.08+j*.131)
            line=slab("Standing roof seam", (x,-.139,.884-abs(x)*.326), (.018,1.58,.019), "Slate light", .003)
            line.rotation_euler.y=side*.32
    slab("Ridge flashing", (0,-.139,.898), (.07,1.62,.032), "Slate light", .006)
    for x in (-.49,.49):
        slab("Door guide", (x,.525,.347), (.038,.042,.556), "Door steel", .006)
        slab("Bollard", (x,.699,.147), (.062,.068,.217), "Poster light", .008)
    slab("Retracted overhead door", (0,.493,.576), (.98,.066,.104), "Door steel", .006)
    for x in (-.35,.35):
        slab("Lane stripe", (x,.803,.038), (.018,.25,.004), "Poster light")
    slab("Furnace chimney", (-.51,-.56,.853), (.16,.17,.36), "Light brick", .010)
    slab("Chimney cap", (-.51,-.56,1.033), (.197,.20,.045), "Kerbstone", .009)

def export(key, geometry, variants):
    start("Bayline / "+key.replace("_", " "))
    geometry()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/{key}.blend"), compress=True)
    objs=list(bpy.context.scene.objects)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    mesh=ob.data
    uv=mesh.uv_layers.active or mesh.uv_layers.new()
    for p in mesh.polygons:
        idx=list(PALETTE).index(mesh.materials[p.material_index].name)
        for i in p.loop_indices:
            uv.data[i].uv=((idx+.5)/len(PALETTE),.5)
    coords=[i.co.copy() for i in mesh.vertices]
    world=ob.matrix_world.copy()
    ob.matrix_world=Matrix.Identity(4)
    for suffix, n, x, z, width in variants:
        turn=Matrix.Rotation(math.pi*n/2, 4, "Z")
        # OBJ loader reverses X. The export maps Blender Y to -Z.
        shift=Vector((-x, -z, -.5))
        scale=Matrix.Diagonal(Vector((width, 1, 1, 1)))
        for i, co in zip(mesh.vertices, coords):
            i.co=turn @ scale @ (world @ co)+shift
        mesh.update()
        bpy.ops.wm.obj_export(filepath=str(ROOT/f"mods/luanttd_core/models/bl_{key}{suffix}.obj"),
            export_selected_objects=True, export_materials=False, export_uv=True, export_normals=True,
            export_triangulated_mesh=True, global_scale=1, forward_axis="NEGATIVE_Z", up_axis="Y")

def png_palette():
    colors=[bytes.fromhex(color) for color in PALETTE.values()]
    def chunk(tag, data):
        return struct.pack(">I", len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    pixels=b"".join(c*8 for c in colors)
    payload=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",128,8,8,2,0,0,0))
    payload+=chunk(b"IDAT",zlib.compress((b"\0"+pixels)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures/bl_road_architecture.png").write_bytes(payload)

png_palette()
export("bus_shelter", shelter, [
    ("", 0, .5, .5+.61, 1), ("_quarter", 1, .5-.61, .5, 1),
    ("_corner", 0, .5+.65, .5+.61, .38)])
export("road_depot", depot, [(f"_{n}", n, .5, .5, 1) for n in range(4)])
