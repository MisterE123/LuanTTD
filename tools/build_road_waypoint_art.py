"""Original Blender roadside waypoint markers and native axis meshes.

Run: blender -b -t 1 --python tools/build_road_waypoint_art.py
"""
import bpy
from pathlib import Path
from math import hypot
import struct
import zlib

root = Path(__file__).resolve().parents[1]
mod = root / "mods/luanttd_core"
colors = ["53545A", "838780", "705E47", "313D48", "D88739", "F3DA85", "EBEBEB", "6D5849"]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0


def rgb(col):
    return tuple(int(col[i:i+2], 16) for i in (0, 2, 4))


def palette():
    size = len(colors)*8
    data = b"".join(bytes(rgb(c))*8 for c in colors)
    def chunk(name, data):
        return struct.pack("!I",len(data)) + name + data + struct.pack("!I",zlib.crc32(name+data))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR",struct.pack("!2I5B",size,8,8,2,0,0,0))
    png += chunk(b"IDAT",zlib.compress((b"\0"+data)*8,9))
    png += chunk(b"IEND",b"")
    (mod/"textures/bl_road_waypoint_atlas.png").write_bytes(png)


def shapes():
    vertices,faces=[],[]
    def v(u,y,w):
        vertices.append((u,y,w))
        return len(vertices)-1
    def box(x0,y0,z0,x1,y1,z1,k,top):
        f=[v(x,y,z) for y in (y0,y1) for z in (z0,z1) for x in (x0,x1)]
        for i,row in enumerate(((0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5))):
            faces.append(([f[o] for o in row[::-1]],top if i==1 else k))
    def stripe(x0,y0,x1,y1,z,color,front):
        length=hypot(x1-x0,y1-y0)
        u,w=(y1-y0)*.011/length,(x0-x1)*.011/length
        q=[v(x,y,z) for x,y in ((x0+u,y0+w),(x1+u,y1+w),(x1-u,y1-w),(x0-u,y0-w))]
        faces.append((q[::-1] if front else q,color))
    for u,w in ((-.77,-.34),(.77,.34)):
        box(u-.094,-.40,w-.073,u+.094,.029,w+.073,0,1)
        box(u-.072,.027,w-.060,u+.072,.060,w+.060,0,1)
        box(u-.023,.059,w-.021,u+.023,.588,w+.021,2,6)
        box(u-.117,.354,w-.036,u+.117,.584,w+.036,3,2)
        box(u-.102,.369,w-.040,u+.102,.570,w+.040,4,5)
        # Same centered mark on both approaches: a waypoint, not a stop.
        for z,front in ((w-.041,True),(w+.041,False)):
            for y in (.435,.501):
                stripe(u-.064,y,u,y+.047,z,6,front)
                stripe(u,y+.047,u+.064,y,z,6,front)
            stripe(u-.061,.393,u+.061,.393,z,3,front)
    return vertices,faces


vertices,faces=shapes()
palette()
materials=[]
for code in colors:
    mat=bpy.data.materials.new(code)
    mat.diffuse_color=tuple((n/255)**2.2 for n in rgb(code))+(1,)
    materials.append(mat)
for axis in (0,1):
    coords=[]
    for u,y,w in vertices:
        x,z=(u,w) if axis==1 else (w,-u)
        coords.append((x,y,z))
    mesh=bpy.data.meshes.new(f"Road waypoint {axis}")
    mesh.from_pydata([(x,-z,y) for x,y,z in coords],[],
        [indices for indices,_ in faces])
    mesh.update()
    for mat in materials:
        mesh.materials.append(mat)
    for face,(_,k) in zip(mesh.polygons,faces):
        face.material_index=k
    obj=bpy.data.objects.new(mesh.name,mesh)
    bpy.context.collection.objects.link(obj)
    obj.location.x=3*axis
    lines=["# Original LuanTTD directional road waypoint board."]
    lines+=[f"vt {(i+.5)/len(colors):.6f} 0.5" for i in range(len(colors))]
    lines+=[f"v {.5-x:.6f} {y-.5:.6f} {z-.5:.6f}" for x,y,z in coords]
    # Native OBJ import flips X, hence reverse the parity of the authored winding.
    lines+=["f "+" ".join(f"{v+1}/{color+1}" for v in face[::-1]) for face,color in faces]
    (mod/f"models/bl_road_waypoint_{axis}.obj").write_text("\n".join(lines)+"\n")
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art/road_waypoint.blend"))
