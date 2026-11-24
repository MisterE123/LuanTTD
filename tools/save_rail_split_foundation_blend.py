"""Group the exact stock foundation meshes in a reusable Blender scene.

Run after tools/build_rail_split_foundations.lua and build_rail_split_atlas.py:
blender -b -t 2 --python-exit-code 1 --python tools/save_rail_split_foundation_blend.py
"""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
mod = root / "mods/luanttd_core"
files = sorted((mod / "models").glob("bl_rail_foundation_split_*.obj"))
assert len(files) == 64
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
dry = bpy.data.collections.new("OpenTTD RC1 · dry terrain")
wet = bpy.data.collections.new("OpenTTD RC1 · wet terrain")
scene.collection.children.link(dry)
scene.collection.children.link(wet)
material = bpy.data.materials.new("Grass over cut stone")
material.use_nodes = True
texture = material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load(str(mod / "textures/bl_rail_split_foundation_atlas.png"))
texture.image.pack()
texture.interpolation = "Closest"
shader = material.node_tree.nodes["Principled BSDF"]
material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
for i, f in enumerate(files):
    bpy.ops.wm.obj_import(filepath=str(f), forward_axis="NEGATIVE_Z", up_axis="Y")
    obj, = bpy.context.selected_objects
    obj.name = "Foundation " + f.stem.split("_split_")[1]
    obj.data.name = obj.name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    (wet if f.stem.endswith("_wet") else dry).objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    obj.location.x = i % 8 * 2.7
    obj.location.y = i // 8 * 2.7
assert len(dry.objects) == 40 and len(wet.objects) == 24
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/stock_rail_split_foundations.blend"), compress=True)
