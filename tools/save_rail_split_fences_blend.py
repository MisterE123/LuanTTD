"""Archive the native stock split-foundation fences in editable Blender form."""
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[1]
mod=root/"mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
s=bpy.context.scene
s.unit_settings.system="METRIC"
s["Source"]="Pinned RC1 DrawTrackDetails and generated physical split-slope cut heights."
m=bpy.data.materials.new("Original welded lattice and pressed coping")
m.use_nodes=True
nd=m.node_tree
atlas=nd.nodes.new("ShaderNodeTexImage")
atlas.image=bpy.data.images.load(str(mod/"textures/bl_rail_ground_fence_atlas.png"))
atlas.image.pack()
bsdf=nd.nodes["Principled BSDF"]
nd.links.new(atlas.outputs["Color"],bsdf.inputs["Base Color"])
nd.links.new(atlas.outputs["Alpha"],bsdf.inputs["Alpha"])
groups={}
for i,path in enumerate(sorted((mod/"models").glob("bl_rail_split_fence_*.obj"))):
    key=path.stem.removeprefix("bl_rail_split_fence_")
    state=key.split("_")[0]
    if state not in groups:
        c=bpy.data.collections.new(f"Stock ground state {state}")
        s.collection.children.link(c)
        groups[state]=c
    bpy.ops.wm.obj_import(filepath=str(path),forward_axis="NEGATIVE_Z",up_axis="Y")
    fence,=bpy.context.selected_objects
    fence.name="Fence "+key
    fence.location.x=(i%8)*3.3
    fence.location.y=(i//8)*3.3
    fence.data.materials.clear()
    fence.data.materials.append(m)
    for group in list(fence.users_collection):
        group.objects.unlink(fence)
    groups[state].objects.link(fence)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art/stock_rail_split_fences.blend"),compress=True)
