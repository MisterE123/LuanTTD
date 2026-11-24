"""Pack the original Temperate monument in an editable Blender scene."""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
mod = root / "mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
m = bpy.data.materials.new("Civic statue · cast bronze and flamed granite")
m.use_nodes = True
image = m.node_tree.nodes.new("ShaderNodeTexImage")
image.image = bpy.data.images.load(str(mod / "textures/bl_stock_town_statue.png"))
image.image.pack()
image.interpolation = "Closest"
bsdf = m.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = .63
m.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
bpy.ops.wm.obj_import(filepath=str(mod / "models/bl_stock_town_statue.obj"),
                      forward_axis="NEGATIVE_Z", up_axis="Y", use_split_groups=True)
for part in bpy.context.selected_objects:
    part.data.materials.clear()
    part.data.materials.append(m)
    part.name = "Cast bronze figure" if "bronze" in part.name.lower() else "Granite footing and plaque"
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/stock_town_statue.blend"), compress=True)
