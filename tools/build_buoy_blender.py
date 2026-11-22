"""Create the editable Blender buoy from its original mesh source.

    blender -b -t 2 --python-exit-code 1 --python tools/build_buoy_blender.py
The runtime mesh and palette are built by build_buoy_art.py.
"""
from pathlib import Path
import bpy
base=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
labels=("Keel oxide","Buoy yellow","Sunlit coating","Oxidized rub strip",
        "Ivory lantern band","Blackened iron","Galvanized iron","Pale amber lamp")
colors=("8a4930","dda749","f2c554","b86f36","f0e5aa","273c41","4f6267","ffeab1")
def linear(x):
    return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
materials=[]
for label,color in zip(labels,colors):
    m=bpy.data.materials.new(label);m.use_nodes=True
    rgba=tuple(linear(int(color[i:i+2],16)/255) for i in (0,2,4))+(1,)
    m.diffuse_color=rgba
    shader=m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=rgba
    shader.inputs["Roughness"].default_value=.72
    materials.append(m)
vertices,faces=[],[]
for line in (base/"mods/luanttd_core/models/bl_ship_buoy.obj").read_text().splitlines():
    bits=line.split()
    if not bits: continue
    if bits[0]=="v":
        x,y,z=map(float,bits[1:])
        vertices.append((x+.5,.5-z,y+.5))
    if bits[0]=="f":
        refs=[tuple(map(int,b.split("/"))) for b in bits[1:]]
        faces.append(([r[0]-1 for r in refs],refs[0][1]-1))
start=0
for label,end in zip(("Float and rub strip","Tapered mast","Daymark assembly","Lantern and weather hood"),(72,120,180,240)):
    subset=[(tuple(i-start for i in f),c) for f,c in faces if start<=f[0]<end]
    mesh=bpy.data.meshes.new(label)
    mesh.from_pydata(vertices[start:end],[],[f for f,_ in subset])
    for m in materials: mesh.materials.append(m)
    for poly,(_,c) in zip(mesh.polygons,subset): poly.material_index=c
    mesh.validate(verbose=False);mesh.update()
    obj=bpy.data.objects.new(label,mesh);bpy.context.collection.objects.link(obj)
    start=end
bpy.context.scene["Asset"]="Original LuanTTD navigational buoy; game waterline Z=0."
bpy.context.scene.unit_settings.system="METRIC"
dest=base/"art/blender/ship_buoy.blend"
dest.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(dest),compress=True)
