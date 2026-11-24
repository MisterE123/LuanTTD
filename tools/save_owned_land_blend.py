"""Collect the editable original purchase stakes and pack their palette."""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
mod = root / "mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
material = bpy.data.materials.new("Land stake · timber and enamel")
material.use_nodes = True
nodes = material.node_tree.nodes
palette = nodes.new("ShaderNodeTexImage")
palette.image = bpy.data.images.load(str(mod / "textures/bl_owned_land_atlas.png"))
palette.image.pack()
palette.interpolation = "Closest"
material.node_tree.links.new(palette.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])

for lift in range(3):
    path = mod / "models" / f"bl_owned_land_{lift}.obj"
    bpy.ops.wm.obj_import(filepath=str(path), forward_axis="NEGATIVE_Z", up_axis="Y")
    post, = bpy.context.selected_objects
    post.name = f"Purchase stake · ground lift {lift / 2:g}"
    post.data.materials.clear()
    post.data.materials.append(material)
    post.location.x = lift * 1.5

bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/stock_owned_land.blend"), compress=True)
