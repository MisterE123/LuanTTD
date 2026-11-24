"""Assemble editable, original 2×2 HQ campuses with a packed palette."""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
mod = root / "mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
m = bpy.data.materials.new("Original Headquarters · masonry, glass and gardens")
m.use_nodes = True
img = m.node_tree.nodes.new("ShaderNodeTexImage")
img.image = bpy.data.images.load(str(mod / "textures/bl_stock_company_hq.png"))
img.image.pack()
img.interpolation = "Closest"
m.node_tree.links.new(img.outputs["Color"],m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
for stage,n in enumerate(["Regional office","Brick offices","Civic campus","Modern campus","Glass tower"]):
    group = bpy.data.collections.new(n)
    scene.collection.children.link(group)
    for part in range(1,5):
        f = mod / "models" / f"bl_stock_company_hq_{stage}_{part}.obj"
        bpy.ops.wm.obj_import(filepath=str(f),forward_axis="NEGATIVE_Z",up_axis="Y")
        tile, = bpy.context.selected_objects
        tile.name = f"{n} · parcel {part}"
        tile.location.x += stage * 7 - 2 * ((part-1)%2)
        tile.location.y += 2 * ((part-1)//2)
        for collection in list(tile.users_collection):
            collection.objects.unlink(tile)
        group.objects.link(tile)
        tile.data.materials.clear()
        tile.data.materials.append(m)
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/stock_company_hq.blend"),compress=True)
