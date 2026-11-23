"""Build the original LuanTTD street pedestrian in Blender, then export a GLB."""
import bpy
from math import cos, sin, pi
from pathlib import Path
from struct import pack
from zlib import compress, crc32

R = Path(__file__).resolve().parents[1]
game = R / "mods" / "luanttd_core"
atlas = game / "textures" / "bl_street_pedestrian_atlas.png"
colors = [
    (53, 84, 88), (75, 105, 104), (41, 68, 74), (104, 126, 118), # coat
    (199, 179, 139), (165, 144, 107), (112, 77, 50), (147, 105, 62), # sweater + leather
    (60, 66, 73), (76, 82, 88), (82, 58, 45), (48, 39, 35), # trousers + boots
    (190, 139, 102), (220, 165, 124), (146, 94, 77), (64, 44, 34), # skin + hair
    (106, 87, 67), (132, 107, 79), (173, 147, 110), (40, 41, 41), # hat, brass, eye
    (213, 196, 167), (113, 91, 70), (86, 70, 60), (174, 136, 96)] # shirt/pocket details
def chunk(k,v):
    return pack("!I",len(v)) + k + v + pack("!I",crc32(k+v)&0xffffffff)
palette=[c for c in colors]+[colors[0]]*(32-len(colors))
row=b"".join(bytes(rgb)*4 for rgb in palette)
atlas.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",pack("!IIBBBBB",128,8,8,2,0,0,0))+
                  chunk(b"IDAT",compress((b"\0"+row)*8,9))+chunk(b"IEND",b""))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

# Author in Blender Z-up with -Y forward. All dimensions are 10 model
# units per walking node. Limbs are built in the same resting space as bones.
verts,faces,parts,mat=[],[],[],[]
def model(points, polys, material, bone, colored_facets=None):
    first=len(verts)
    verts.extend(points)
    parts.extend([bone]*len(points))
    for i,q in enumerate(polys):
        faces.append(tuple(first+j for j in q))
        mat.append(material if not colored_facets else colored_facets(i,material))
def octagon(x,y,z,w,d):
    return [(x+w*a,y+d*b,z) for a,b in
        ((-.76,-1),(.76,-1),(1,-.67),(1,.67),(.76,1),(-.76,1),(-1,.67),(-1,-.67))]
def loft(rings, c, bone, accent=None):
    n=len(rings[0])
    sides=[tuple(range(n-1,-1,-1))]
    for j in range(len(rings)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n
            sides.append((a,b,b+n,a+n))
    sides.append(tuple(range(len(rings)*n-n,len(rings)*n)))
    model(sum(rings,[]),sides,c,bone,accent)
def parcel(x,y,z,w,d,h,c,bone):
    loft([octagon(x,y,z-h,w,d),octagon(x,y,z+h,w,d)],c,bone)
def orb(x,y,z,rx,ry,rz,c,bone,n=10):
    # Lower and upper corners use compact poles, not duplicate coincident ring vertices.
    ps=[(x,y,z-rz)]
    for elev in (-pi/3,-pi/6,0,pi/6,pi/3):
        ps += [(x+rx*cos(elev)*cos(2*pi*i/n),y+ry*cos(elev)*sin(2*pi*i/n),
                z+rz*sin(elev)) for i in range(n)]
    top=len(ps);ps.append((x,y,z+rz))
    polys=[]
    for i in range(n):
        j=(i+1)%n
        polys.append((0,1+j,1+i))
        for ring in range(4):
            a=1+ring*n
            polys.append((a+i,a+j,a+j+n,a+i+n))
        polys.append((1+4*n+i,1+4*n+j,top))
    model(ps,polys,c,bone)
def lapel(points,c):
    model(points,[(0,1,2)],c,"Body")

# Fitted wool jacket follows the shoulders rather than reading as a cube.
loft([octagon(0,0,2.30,.49,.28),octagon(0,0,2.47,.56,.34),
      octagon(0,0,2.92,.53,.32),octagon(0,0,3.55,.66,.36),
      octagon(0,0,3.85,.60,.33),octagon(0,0,3.99,.39,.30)],
     0,"Body",lambda i,m: {3:1,5:2,8:2}.get(i%8,m))
loft([octagon(0,0,2.21,.40,.28),octagon(0,0,2.58,.54,.31)],8,"Body")
# Worn collar and scarf, understated pockets, button placket and shoulder seam.
lapel([(-.36,-.324,3.93),(-.26,-.391,3.58),(-.055,-.403,3.78)],3)
lapel([(.36,-.324,3.93),(.23,-.397,3.53),(.048,-.405,3.78)],1)
lapel([(-.15,-.416,3.88),(.20,-.417,3.87),(.02,-.424,3.46)],4)
parcel(0,-.355,3.08,.033,.025,.40,2,"Body")
for z in (2.71,2.98,3.22):
    parcel(.047,-.383,z,.026,.012,.027,18,"Body")
for x in (-.34,.34):
    parcel(x,-.326,2.70,.128,.020,.035,2,"Body")
# Cross-body strap, dark leather back satchel, separate flap and rim.
lapel([(-.44,-.372,3.86),(-.31,-.392,3.88),(.48,-.365,2.47)],6)
lapel([(-.31,-.392,3.88),(.48,-.365,2.47),(.57,-.350,2.48)],7)
parcel(.045,.368,3.10,.36,.098,.344,6,"Body")
parcel(.045,.461,3.28,.34,.034,.17,7,"Body")
parcel(.046,.493,3.17,.046,.017,.038,18,"Body")
# Neck, modeled head silhouette, nose, ears, hair and molded cap.
orb(0,-.008,4.02,.171,.153,.175,12,"Head",8)
loft([octagon(0,-.024,4.12,.16,.17),octagon(0,-.032,4.26,.238,.216),
      octagon(0,-.025,4.44,.263,.231),octagon(0,0,4.66,.264,.233),
      octagon(0,.014,4.83,.195,.19),octagon(0,.025,4.88,.09,.105)],
     12,"Head",lambda i,m: 13 if i%8 in (1,2,8) else m)
orb(0,-.253,4.43,.063,.062,.087,13,"Head",8)
for side in (-1,1):
    orb(side*.265,.009,4.45,.045,.066,.076,12,"Head",8)
    orb(side*.116,-.252,4.53,.033,.018,.019,20,"Head",6)
    orb(side*.114,-.267,4.53,.016,.007,.015,19,"Head",6)
    parcel(side*.116,-.239,4.575,.039,.011,.010,15,"Head")
parcel(.004,-.247,4.30,.061,.011,.012,14,"Head")
loft([octagon(0,.068,4.56,.241,.209),octagon(0,.041,4.73,.267,.231),
      octagon(0,.023,4.91,.182,.181)],15,"Head",lambda i,m: 14 if i%8==5 else m)
loft([octagon(0,.019,4.80,.281,.26),octagon(0,.028,4.97,.296,.252),
      octagon(0,.036,5.08,.221,.201),octagon(0,.037,5.105,.08,.078)],16,"Head",
     lambda i,m: 17 if i in (10,11,13,19,20,25) else m)
loft([octagon(0,-.144,4.782,.237,.263),octagon(0,-.144,4.822,.241,.269)],22,"Head")

bones={"Body":((0,0,2.30),(0,0,3.92)), "Head":((0,0,3.95),(0,0,4.92),"Body")}
for side in (-1,1):
    key="L" if side<0 else "R"
    up="UpperArm."+key; low="Forearm."+key
    top="Thigh."+key; knee="Shin."+key; foot="Boot."+key
    bones[up]=((side*.64,0,3.76),(side*.77,-.005,3.06),"Body")
    bones[low]=((side*.77,-.005,3.06),(side*.81,-.034,2.48),up)
    bones[top]=((side*.26,0,2.40),(side*.28,0,1.42),"Body")
    bones[knee]=((side*.28,0,1.42),(side*.29,0,.38),top)
    bones[foot]=((side*.29,0,.38),(side*.29,-.24,.18),knee)
    loft([octagon(side*.77,0,3.00,.117,.133),octagon(side*.74,0,3.28,.149,.154),
          octagon(side*.665,0,3.67,.158,.164),octagon(side*.60,0,3.81,.123,.146)],0,up)
    loft([octagon(side*.81,-.024,2.49,.097,.105),octagon(side*.79,-.01,2.79,.111,.117),
          octagon(side*.77,0,3.10,.122,.134)],1,low)
    parcel(side*.81,-.024,2.515,.101,.103,.037,2,low)
    orb(side*.813,-.027,2.399,.085,.080,.123,12,low,8)
    loft([octagon(side*.282,.01,1.37,.147,.174),octagon(side*.264,.014,1.74,.181,.195),
          octagon(side*.252,.02,2.44,.204,.222)],8,top,lambda i,m:9 if i%8==1 else m)
    loft([octagon(side*.29,.032,.34,.119,.134),octagon(side*.284,.04,.76,.149,.152),
          octagon(side*.282,.033,1.51,.151,.17)],8,knee)
    loft([octagon(side*.291,-.073,0,.153,.263),octagon(side*.291,-.078,.066,.159,.27)],11,foot)
    loft([octagon(side*.291,-.075,.060,.154,.258),octagon(side*.291,-.047,.19,.14,.22),
          octagon(side*.291,.007,.355,.121,.154)],10,foot)
    for lace in range(3):
        parcel(side*.291,-.156+.065*lace,.206+.021*lace,.083,.014,.009,21,foot)

mesh=bpy.data.meshes.new("Seam-stitched jacket, boots and cap")
# Bake the player's native facing into the skin. Luanti's importer
# consumes rigid skin meshes without the Blender armature-object facing.
def native_facing(point):
    x,y,z=point
    return -x,-y,z

mesh.from_pydata([native_facing(v) for v in verts],[],faces);mesh.update()
uv=mesh.uv_layers.new(name="Original palette UV")
for poly,i in zip(mesh.polygons,mat):
    for ln in poly.loop_indices:
        uv.data[ln].uv=((i+.5)/32,.5)
matobj=bpy.data.materials.new("Wool, canvas and leather swatches")
matobj.use_nodes=True
tex=matobj.node_tree.nodes.new("ShaderNodeTexImage")
tex.image=bpy.data.images.load(str(atlas))
tex.image.pack()
tex.image.filepath="//../mods/luanttd_core/textures/bl_street_pedestrian_atlas.png"
tex.interpolation="Closest"
bsdf=matobj.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value=.93
matobj.node_tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
mesh.materials.append(matobj)
m=bpy.data.objects.new("Street pedestrian",mesh)
bpy.context.collection.objects.link(m)

armature=bpy.data.armatures.new("Street pedestrian gait rig")
arm=bpy.data.objects.new("Street pedestrian rig",armature)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm;arm.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for key,spec in bones.items():
    b=armature.edit_bones.new(key)
    b.head,b.tail=map(native_facing,spec[:2])
    if len(spec)==3:
        b.parent=armature.edit_bones[spec[2]]
bpy.ops.object.mode_set(mode="OBJECT")
for key in bones:
    group=m.vertex_groups.new(name=key)
    group.add([i for i,k in enumerate(parts) if k==key],1,"REPLACE")
mod=m.modifiers.new("Rig deformation","ARMATURE");mod.object=arm
m.parent=arm
arm.show_in_front=True

# Export one Luanti glTF timeline in seconds. Idle 0..1; walk 2..14.
# Use widely spaced authored frames so the compact keys remain editable.
scene=bpy.context.scene
scene.render.fps=24
scene.frame_start=0
scene.frame_end=14*24
action=arm.animation_data_create()
poses=[(0,0),(24,0)]
poses += [(48+i*36,2*pi*i/8) for i in range(9)]
for frame,phase in poses:
    stride=frame>=48
    body=arm.pose.bones["Body"]
    body.rotation_mode="XYZ"
    body.rotation_euler=(.031*sin(phase) if stride else 0,0,.03*cos(phase) if stride else 0)
    # Body bone Y axis points up.
    body.location=(0,.033*(1-cos(2*phase)) if stride else 0,0)
    body.keyframe_insert(data_path="rotation_euler",frame=frame,group="Body")
    body.keyframe_insert(data_path="location",frame=frame,group="Body")
    for side in (-1,1):
        k="L" if side<0 else "R"
        x=phase+(pi if side<0 else 0)
        state={ "UpperArm": -.39*cos(x), "Forearm": .10+.17*(1-sin(x)),
                "Thigh": .44*cos(x), "Shin": -.54*max(0,sin(x)),
                "Boot": .16*sin(x)-.09*cos(x)}
        for key,value in state.items():
            b=arm.pose.bones[key+"."+k]
            b.rotation_mode="XYZ"; b.rotation_euler=(value if stride else 0,0,0)
            b.keyframe_insert(data_path="rotation_euler",frame=frame,group=key+"."+k)
if arm.animation_data and arm.animation_data.action:
    arm.animation_data.action.name="Street Idle and Walk"
scene.frame_set(0)
bpy.context.view_layer.objects.active=m
m.select_set(True);arm.select_set(True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(R/"art"/"street_pedestrian.blend"),compress=True)
bpy.ops.export_scene.gltf(filepath=str(game/"models"/"bl_street_pedestrian.glb"),
    export_format="GLB",use_selection=True,export_yup=True,
    export_animations=True,export_force_sampling=True,export_frame_step=6,
    export_optimize_animation_size=True,export_materials="EXPORT")

# The Luanti 5.10 glTF reader accepts LINEAR curves only. Blender writes
# STEP for constant baked channels (uniform scales/rest translations).
# Confirm each STEP channel really is constant before normalizing metadata.
import json
from struct import unpack_from
glb=game/"models"/"bl_street_pedestrian.glb"
raw=glb.read_bytes()
jlen=unpack_from("<I",raw,12)[0]
doc=json.loads(raw[20:20+jlen])
body=raw[20+jlen:]
for clip in doc["animations"]:
    for channel in clip["samplers"]:
        if channel.get("interpolation") == "STEP":
            a=doc["accessors"][channel["output"]]
            v=doc["bufferViews"][a["bufferView"]]
            assert a["componentType"]==5126 and "sparse" not in a
            width={"VEC3":12,"VEC4":16}[a["type"]]
            begin=8+v.get("byteOffset",0)+a.get("byteOffset",0)
            rows=[unpack_from("<"+"f"*(width//4),body,begin+i*width) for i in range(a["count"])]
            assert all(abs(x-y)<1e-5 for row in rows for x,y in zip(row,rows[0])), "STEP channel not constant"
            channel["interpolation"]="LINEAR"
# Native properties supply the same palette file. Don't request an
# embedded texture the 5.10 glTF reader cannot use. The Blender source
# retains the packed image for material editing and normal export.
for material in doc.get("materials",[]):
    material.get("pbrMetallicRoughness",{}).pop("baseColorTexture",None)
for unused in ("images","textures","samplers"):
    doc.pop(unused,None)
payload=json.dumps(doc,separators=(",",":")).encode("utf-8")
payload+=b" "*((-len(payload))%4)
glb.write_bytes(pack("<4sIII4s",b"glTF",2,20+len(payload)+len(body),len(payload),b"JSON")+payload+body)
