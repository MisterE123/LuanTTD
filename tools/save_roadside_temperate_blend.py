"""Assemble the authored Luanti roadside models into an editable gallery."""
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[1]
mod=root/"mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
m=bpy.data.materials.new("Original road furniture palette")
m.use_nodes=True
texture=m.node_tree.nodes.new("ShaderNodeTexImage")
texture.image=bpy.data.images.load(str(mod/"textures/bl_roadside_temperate_atlas.png"))
texture.image.pack()
texture.interpolation="Closest"
m.node_tree.links.new(texture.outputs["Color"],m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
for group,group_id in (("Trees",0),("Street lights",1)):
    collection=bpy.data.collections.new(group)
    scene.collection.children.link(collection)
    kind=group.lower().replace(" ","_")
    entries=sorted((mod/"models").glob(f"bl_roadside_{kind}_*.obj"))
    assert len(entries)==14
    for i,p in enumerate(entries):
        bpy.ops.wm.obj_import(filepath=str(p),forward_axis="NEGATIVE_Z",up_axis="Y")
        obj,=bpy.context.selected_objects
        obj.name=group+" "+p.stem.rsplit("_",2)[-2]+"/"+p.stem.rsplit("_",1)[-1]
        for c in list(obj.users_collection): c.objects.unlink(obj)
        collection.objects.link(obj)
        obj.data.materials.clear()
        obj.data.materials.append(m)
        obj.location.x=i%7*2.8
        obj.location.y=(group_id*3+i//7)*2.8
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art/stock_temperate_roadside.blend"),compress=True)
