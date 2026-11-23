"""Build the editable ride-interior source library in Blender 4.3+.

Run: blender -b -t 2 --python tools/build_ride_vehicles_blender.py
The production OBJ/PNG exports are independently reproducible without Blender.
"""
from collections import defaultdict
from pathlib import Path
import sys

import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "tools"))
import build_ride_interiors as source

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
world = bpy.data.worlds.new("Workshop daylight")
world.use_nodes = True
world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.222, .345, .450, 1)
world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .64

def studio_position(point):
    x, y, z = point
    return (x * 10, z * 10, y * 10)

def linear(channel):
    value = channel / 255
    return value / 12.92 if value < .04045 else ((value+.055)/1.055)**2.4

def material_for(scene, paint, hexstr, pattern):
    mat = bpy.data.materials.new(f"{scene} · {paint.replace('_',' ').title()}")
    col = (*[linear(int(hexstr[i:i+2],16)) for i in (0,2,4)],1)
    mat.diffuse_color = col
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = col
    shader.inputs["Roughness"].default_value = .37 if paint in {"brass","metal","steel"} else .68
    shader.inputs["Metallic"].default_value = .52 if paint in {"brass","metal","steel"} else 0
    if paint=="lit":
        shader.inputs["Emission Color"].default_value = col
        shader.inputs["Emission Strength"].default_value = .65
    if pattern in {"wood","leather","brush","carpet"}:
        grain = mat.node_tree.nodes.new("ShaderNodeTexNoise")
        grain.inputs["Scale"].default_value = 100
        bump = mat.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .15
        bump.inputs["Distance"].default_value = .0018
        mat.node_tree.links.new(grain.outputs["Fac"],bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"],shader.inputs["Normal"])
    return mat

def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat("-Z","Y").to_euler()

scenes = []
for build, name in ((source.bus,"Bus passenger"),(source.coach,"Rail passenger"),(source.cab,"Steam driver's cab")):
    spec = build()
    scene = bpy.data.scenes.new(name)
    scenes.append(scene)
    scene.world = world
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = 1120
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    collection = bpy.data.collections.new(f"{name} editable components")
    scene.collection.children.link(collection)
    grouped = defaultdict(list)
    for label, paint, face in spec.faces:
        grouped[label].append((paint,face))
    materials = {paint:material_for(name, paint, *color) for paint,color in spec.materials.items()}
    for label, faces in grouped.items():
        vertices=[]; lookup={}; polygons=[]; paints=[]
        for paint, face in faces:
            refs=[]
            for p in reversed(face):
                p=studio_position(p)
                if p not in lookup:
                    lookup[p]=len(vertices)
                    vertices.append(p)
                refs.append(lookup[p])
            polygons.append(refs)
            paints.append(paint)
        mesh = bpy.data.meshes.new(label)
        mesh.from_pydata(vertices,[],polygons)
        mesh.update()
        obj = bpy.data.objects.new(label,mesh)
        collection.objects.link(obj)
        indices={}
        for polygon,paint in zip(mesh.polygons,paints):
            if paint not in indices:
                indices[paint]=len(mesh.materials)
                mesh.materials.append(materials[paint])
            polygon.material_index=indices[paint]
    cam = bpy.data.objects.new("Calibrated first-person seat",bpy.data.cameras.new("Seat camera"))
    scene.collection.objects.link(cam)
    cam.location=studio_position(source.EYES[spec.kind])
    cam.data.lens=20
    cam.data.clip_start=.06
    aim(cam,cam.location+Vector((0,8,-.45)))
    scene.camera=cam
    key = bpy.data.objects.new("Soft cabin bounce",bpy.data.lights.new("Soft cabin bounce","AREA"))
    scene.collection.objects.link(key)
    key.data.energy=44
    key.data.size=2.2
    key.location=(0,-.7,3.5)
    aim(key,(0,.2,.5))
    for prop,value in {
        "game_local_eye":source.EYES[spec.kind],
        "game_floor_over_actor":source.FLOORS[spec.kind],
        "game_export_clip_margin":source.CLIP_CLEARANCE[spec.kind],
    }.items():scene[prop]=value

original=bpy.context.window.scene
bpy.context.window.scene=scenes[0]
bpy.data.scenes.remove(original)
for area in bpy.context.screen.areas:
    if area.type=="VIEW_3D":
        area.spaces.active.shading.color_type="MATERIAL"
        area.spaces.active.region_3d.view_perspective="CAMERA"
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/ride_interiors.blend"),compress=True)
