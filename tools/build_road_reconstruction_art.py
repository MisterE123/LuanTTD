"""Blender: original striped barriers, cones and work patch for stock road works.

Run with blender --background --factory-startup --python tools/build_road_reconstruction_art.py.
The saved .blend uses editable mesh objects; the OBJ variants differ only in orientation.
"""
import binascii
import math
from pathlib import Path
import struct
import zlib

import bpy

root = Path(__file__).resolve().parents[1]
models = root / "mods/luanttd_core/models"
textures = root / "mods/luanttd_core/textures"
palette = (
    (229, 114, 27), (227, 218, 193), (71, 85, 94), (36, 42, 39),
    (169, 53, 35), (103, 93, 80), (133, 121, 104), (240, 181, 67),
)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
materials = []
for name, rgb in zip(("signal orange", "reflective white", "galvanized steel", "rubber",
                      "red warning paint", "worksite gravel", "gravel light", "amber"), palette):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*(v / 255 for v in rgb), 1)
    materials.append(mat)

def finish(name, color):
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(materials[color])
    return obj

def box(name, pos, dimensions, color):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = finish(name, color)
    obj.scale = dimensions
    return obj

def cone(name, x, y):
    box(name + " rubber base", (x, y, .014), (.19, .19, .028), 3)
    for radius1, radius2, height, center, col in (
        (.078, .054, .10, .073, 0), (.054, .040, .052, .149, 1),
        (.04, .017, .10, .225, 0),
    ):
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=radius1, radius2=radius2,
                                        depth=height, location=(x, y, center))
        finish(name + " colored section", col)

box("Reconstruction gravel bed", (0, 0, .016), (.88, 1.14, .031), 5)
for i in range(5):
    box("Fresh gravel pass", (-.37 + .18 * i, -.21 + .047 * i, .033), (.078, .49, .009), 6)
for direction in (-1, 1):
    gate = direction * .68
    for lane in (-.57, .57):
        box("Barrier sleeper foot", (gate, lane, .022), (.29, .12, .044), 3)
        box("Galvanized barrier leg", (gate, lane, .23), (.047, .047, .43), 2)
        cone("Lane warning cone", direction * .89, lane + .08)
    for tier in (.285, .405):
        for index in range(11):
            box("Reflective barrier stripe", (gate, (index-5)*.12, tier),
                (.05, .12, .074), 4 if index % 2 == 0 else 1)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=.055,
                                        location=(gate, .56, .495))
    finish("Amber barricade beacon", 7)

def write_obj(axis, angle):
    from mathutils import Matrix
    rot = Matrix.Rotation(angle, 4, "Z")
    out = ["# Original LuanTTD Blender roadwork furniture. See the repository license."]
    for i in range(len(palette)):
        out.append(f"vt {(i+.5)/len(palette):.6f} 0.500000")
    offset = 1
    for obj in sorted(bpy.context.scene.objects, key=lambda x: x.name):
        mesh = obj.data
        idx = materials.index(mesh.materials[0]) + 1
        world = rot @ obj.matrix_world
        for vert in mesh.vertices:
            x, y, z = world @ vert.co
            out.append(f"v {x:.6f} {z-1.5:.6f} {-y:.6f}")
        for face in mesh.polygons:
            out.append("f " + " ".join(f"{i+offset}/{idx}" for i in face.vertices))
        offset += len(mesh.vertices)
    (models / f"bl_road_reconstruction_{axis}.obj").write_text("\n".join(out)+"\n")

def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", binascii.crc32(tag+data))
pixels = bytes(component for texel in palette for component in texel)
data = b"\x89PNG\r\n\x1a\n"
data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", len(palette), 4, 8, 2, 0, 0, 0))
data += png_chunk(b"IDAT", zlib.compress((b"\x00"+pixels)*4, 9))
data += png_chunk(b"IEND", b"")
(textures / "bl_road_reconstruction_atlas.png").write_bytes(data)
bpy.context.view_layer.update()
write_obj(0, 0)
write_obj(1, math.pi/2)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/road_reconstruction.blend"), compress=True)
