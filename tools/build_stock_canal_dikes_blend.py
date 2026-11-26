"""Run from repository root: blender -b -t 1 -P tools/build_stock_canal_dikes_blend.py."""
from pathlib import Path
import bpy

root=Path.cwd()
mod=root/"mods/luanttd_core"
bpy.ops.wm.read_factory_settings(use_empty=True)
material=bpy.data.materials.new("Original dressed limestone")
material.diffuse_color=(.48,.41,.31,1)
material.use_nodes=True
texture=material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image=bpy.data.images.load(str(mod/"textures/bl_canal_dike_limestone.png"))
texture.image.pack()
material.node_tree.links.new(texture.outputs["Color"],material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
items=sorted((mod/"models").glob("bl_canal_dike_*.obj"),key=lambda p:int(p.stem.rsplit("_",1)[-1]))
for index,path in enumerate(items):
    before=set(bpy.data.objects)
    if bpy.app.version >= (4,0,0):
        bpy.ops.wm.obj_import(filepath=str(path))
    else:
        bpy.ops.import_scene.obj(filepath=str(path))
    item,=set(bpy.data.objects)-before
    item.name="RC1 dike mask "+path.stem.rsplit("_",1)[-1]
    item.location.x=(index%8)*2.75
    item.location.y=(index//8)*2.75
    item.data.materials.clear()
    item.data.materials.append(material)
    item.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art/stock_canal_dikes.blend"),compress=True)
