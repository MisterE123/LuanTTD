#!/usr/bin/env python3
"""Author an open, striped airport windsock with a fixed mouth and cloth bones."""
import json
from math import cos, pi, sin
from pathlib import Path
import struct
import zlib
import bpy

root=Path(__file__).resolve().parents[1]
mod=root/"mods"/"luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.fps=30
scene.frame_start,scene.frame_end=0,60
segments=6
sides=12
pts=[]
for j in range(segments+1):
    t=j/segments
    radius=.094-.059*t
    for i in range(sides):
        a=2*pi*i/sides
        pts.append((cos(a)*radius, .039+.53*t, sin(a)*radius-.12*t**2))
faces=[]
for j in range(segments):
    for i in range(sides):
        k=(i+1)%sides
        faces.append((j*sides+i,j*sides+k,(j+1)*sides+k,(j+1)*sides+i))

mesh=bpy.data.meshes.new("Tapered strip-woven cloth")
mesh.from_pydata(pts,[],faces)
mesh.update()
cloth=bpy.data.objects.new("Country windsock", mesh)
scene.collection.objects.link(cloth)
uv=mesh.uv_layers.new(name="Striped fabric")
for poly in mesh.polygons:
    band=poly.index//sides
    for loop in poly.loop_indices:
        uv.data[loop].uv=(.25 if band%2==0 else .75,.5)
    poly.use_smooth=True

skeleton=bpy.data.armatures.new("Fixed swivel and travelling fabric folds")
rig=bpy.data.objects.new("Windsock cloth rig",skeleton)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for j in range(segments+1):
    t=j/segments
    b=skeleton.edit_bones.new(f"Ring {j}")
    b.head=(0,.039+.53*t,-.12*t**2)
    b.tail=(0,.119+.53*t,-.12*t**2)
bpy.ops.object.mode_set(mode="OBJECT")
mod_=cloth.modifiers.new("Cloth skin","ARMATURE")
mod_.object=rig
cloth.parent=rig
for j in range(segments+1):
    key=f"Ring {j}"
    cloth.vertex_groups.new(name=key).add(list(range(j*sides,(j+1)*sides)),1,"REPLACE")
    bone=rig.pose.bones[key]
    t=j/segments
    for frame in range(0,61,3):
        theta=frame*pi/30-5*t
        bone.location=(.067*t*t*sin(theta), .017*t*t*cos(theta), .040*t*sin(theta+.48))
        bone.keyframe_insert(data_path="location",frame=frame,group=key)
rig.animation_data.action.name="Wind sleeve flutter loop"
scene.frame_set(0)
cloth.select_set(True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art"/"country_windsock.blend"),compress=True)
path=mod/"models"/"bl_airport_windsock.glb"
bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",use_selection=True,
    export_yup=True,export_animations=True,export_force_sampling=True,export_frame_step=3,
    export_optimize_animation_size=False,export_materials="NONE")
raw=path.read_bytes()
size=struct.unpack_from("<I",raw,12)[0]
doc=json.loads(raw[20:20+size])
body=raw[20+size:]
# Baked transform keys are linear. Constant Blender channels can be STEP.
for animation in doc["animations"]:
    for sampler in animation["samplers"]:
        if sampler.get("interpolation")=="STEP":
            a=doc["accessors"][sampler["output"]]
            v=doc["bufferViews"][a["bufferView"]]
            n={"VEC3":3,"VEC4":4}[a["type"]]
            start=8+v.get("byteOffset",0)+a.get("byteOffset",0)
            row=struct.unpack_from("<"+"f"*n,body,start)
            for i in range(a["count"]):
                assert struct.unpack_from("<"+"f"*n,body,start+i*4*n)==row
            sampler["interpolation"]="LINEAR"
# Cloth has a real opening at either end; Luanti shows the reverse of the
# same thin woven material using the entity's backface_culling property.
encoded=json.dumps(doc,separators=(",",":")).encode()
encoded+=b" "*((-len(encoded))%4)
path.write_bytes(struct.pack("<4sIII4s",b"glTF",2,20+len(encoded)+len(body),len(encoded),b"JSON")+encoded+body)

# Palette is a regular native texture, not an embedded glTF dependency.
def chunk(tag, data):
    return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
rows=b"\0"+bytes((224,105,42))*8+bytes((239,222,184))*8
(mod/"textures"/"bl_airport_windsock.png").write_bytes(b"\x89PNG\r\n\x1a\n"+
    chunk(b"IHDR",struct.pack(">IIBBBBB",16,4,8,2,0,0,0))+
    chunk(b"IDAT",zlib.compress(rows*4,9))+chunk(b"IEND",b""))
