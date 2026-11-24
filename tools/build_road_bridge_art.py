"""Build LuanTTD's original timber road bridge library and Luanti OBJ assets.

blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_art.py
Optional ROAD_BRIDGE_RENDER=/tmp/bridge.png produces a Blender overview.
"""
from collections import defaultdict
from math import cos, pi, sin
from pathlib import Path
import os
import struct
import zlib

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT/"mods"/"luanttd_core"/"models"
TEXTURES = ROOT/"mods"/"luanttd_core"/"textures"
PREFIX = "bl_road_bridge_wood"
COLORS = {
    "Asphalt": "4f5255", "Road shoulder": "9a937e", "Road centre marking": "efe3b6",
    "Timber — cut ends": "b88456", "Timber — upper edge": "986442",
    "Timber — warm": "79533a", "Timber — mid": "694831", "Timber — grain": "895d41",
    "Timber — creosote": "4d3b30", "Timber — dark": "553b2b", "Timber — shadow": "382d27",
    "Steel straps": "505956", "Iron bolts": "9ba19a",
    "Ashlar — cold": "6f7263", "Ashlar — warm": "86806b",
    "Ashlar — cap": "a29a80", "Ashlar — dark": "575b51",
}
DIRECTIONS = ((-1,0),(0,1),(1,0),(0,-1))  # OpenTTD DIAGDIR_NE,SE,SW,NW
NAMES = ("Asphalt","Road shoulder","Road centre marking")
STRIPES = ((2,4),(7,10),(22,25),(28,30))
ASPHALT = .3125
SHOULDER = .375
RAIL = .426
DECK = .5


class Mesh:
    """Authoring coordinates X, Z, elevation; export in Luanti node units."""
    def __init__(self):
        self.groups = defaultdict(list)

    def poly(self, group, color, *points):
        for i in range(1,len(points)-1):
            self.groups[group].append((color,(points[0], points[i], points[i+1])))

    def section(self, group, color, u0, u1, v0, v1, h):
        self.poly(group,color,(u0,v0,h(v0)),(u1,v0,h(v0)),(u1,v1,h(v1)),(u0,v1,h(v1)))

    def box(self, group, color, u0, u1, v0, v1, h0, h1, *, end_faces=True, face_colors=None):
        def h(f,v): return f(v) if callable(f) else f
        # Standard outward winding in X/Z/elevation.
        points=((u0,v0,h(h0,v0)),(u1,v0,h(h0,v0)),(u1,v1,h(h0,v1)),(u0,v1,h(h0,v1)),
                (u0,v0,h(h1,v0)),(u1,v0,h(h1,v0)),(u1,v1,h(h1,v1)),(u0,v1,h(h1,v1)))
        faces=(("under",(0,3,2,1)),("top",(4,5,6,7)),("front",(0,1,5,4)),
               ("right",(1,2,6,5)),("back",(2,3,7,6)),("left",(3,0,4,7)))
        for side, ids in faces:
            if not end_faces and side in ("front","back"):
                continue
            self.poly(group,(face_colors or {}).get(side,color),*(points[i] for i in ids))

    def bar(self, group, color, a, b, thickness, depth):
        """Rectangular structural member, with real end grain visible."""
        qa,qb=Vector(a),Vector(b)
        direction=(qb-qa).normalized()
        axis=Vector((0,1,0)) if abs(direction.y)<.86 else Vector((1,0,0))
        normal=direction.cross(axis).normalized()*thickness/2
        transverse=normal.normalized().cross(direction).normalized()*depth/2
        rr=(normal+transverse, -normal+transverse, -normal-transverse, normal-transverse)
        self.poly(group,"Timber — cut ends",*(tuple(qa+r) for r in rr))
        self.poly(group,"Timber — cut ends",*(tuple(qb+r) for r in reversed(rr)))
        for i in range(4):
            j=(i+1)%4
            self.poly(group,color,tuple(qa+rr[j]),tuple(qa+rr[i]),tuple(qb+rr[i]),tuple(qb+rr[j]))

    def bolt(self, group, u, v, h, side):
        """Forged hex nut on exterior of timber plate, width across flats .035."""
        p0,p1=[],[]
        for i in range(6):
            phi=pi*i/3
            p0.append((u,v+.021*cos(phi),h+side*.021*sin(phi)))
            p1.append((u+side*.014,v+.021*cos(phi),h+side*.021*sin(phi)))
        self.poly(group,"Iron bolts",*p1)
        for i in range(6):
            j=(i+1)%6
            self.poly(group,"Steel straps",p0[i],p0[j],p1[j],p1[i])

    def oriented(self, direction):
        dx,dz=DIRECTIONS[direction]
        m=Mesh()
        # Positive u is locally right of positive v. Determinant +1.
        for g,data in self.groups.items():
            for color,points in data:
                m.groups[g].append((color,tuple((dz*u+dx*v,-dx*u+dz*v,h) for u,v,h in points)))
        return m


def running_surface(m, h):
    # The marked pattern exactly follows the central pixels of the existing
    # flat straight road atlas, so rotation cannot introduce a stripe seam.
    for side in (-1,1):
        a,b=sorted((side*ASPHALT,side*SHOULDER))
        m.section("Shoulder slab","Road shoulder",a,b,-1,1,h)
    bounds=sorted({0,32,*(n for pair in STRIPES for n in pair)})
    for a,b in zip(bounds,bounds[1:]):
        v0,v1=a/16-1,b/16-1
        if (a,b) in STRIPES:
            m.section("Running asphalt","Asphalt",-ASPHALT,-.0625,v0,v1,h)
            m.section("Inlaid centre markings","Road centre marking",-.0625,.0625,v0,v1,h)
            m.section("Running asphalt","Asphalt",.0625,ASPHALT,v0,v1,h)
        else:
            m.section("Running asphalt","Asphalt",-ASPHALT,ASPHALT,v0,v1,h)


def superstructure(m, h, head):
    running_surface(m,h)
    m.box("Structural deck core","Timber — mid",-.456,.456,-1,1,
          lambda v:h(v)-.126,lambda v:h(v)-.005,end_faces=False)
    # Draw individual edge grains/planks rather than one uninterrupted wall.
    # A diagonal reflection on two outer corners is not baked into the atlas.
    grain=("Timber — warm","Timber — mid","Timber — grain","Timber — upper edge")
    for side in (-1,1):
        for i in range(16):
            v0=-1+i*.125;v1=v0+.122
            want = side*SHOULDER
            u0,u1=sorted((want,side*.457))
            m.box("Exposed crosswise deck planks",grain[(i+side+4)%4],
                  u0,u1,v0,v1,lambda v:h(v)-.13,lambda v:h(v)-.006,
                  face_colors={"front":"Timber — cut ends","under":"Timber — shadow"})

        a,b=sorted((side*.281,side*.399))
        m.box("Continuous timber stringers","Timber — dark",a,b,-1,1,
              lambda v:h(v)-.266,lambda v:h(v)-.124,end_faces=False,
              face_colors={"under":"Timber — shadow","left":"Timber — mid"})
        a,b=sorted((side*.395,side*.463))
        start=-.83 if head else -1
        for above,below in ((.29,.234),(.153,.116)):
            m.box("Continuous railings","Timber — warm",a,b,start,1,
                  lambda v:h(v)+below,lambda v:h(v)+above,end_faces=False,
                  face_colors={"top":"Timber — upper edge","left":"Timber — grain"})
        for v in (-.78,-.28,.27,.78):
            a,b=sorted((side*.392,side*.475))
            m.box("Guardrail posts","Timber — mid",a,b,v-.041,v+.041,
                  lambda q:h(q)-.095,lambda q:h(q)+.320,
                  face_colors={"top":"Timber — cut ends","front":"Timber — grain"})
            m.bolt("Visible guardrail hardware",side*.477,v,h(v)+.266,side)
        if head:
            # A capped, beveled first rail post and no wood sitting on the
            # adjoining road. The final section's rails start below lane edge.
            a,b=sorted((side*.390,side*.475))
            m.box("Head approach rail end","Timber — cut ends",a,b,-.836,-.823,
                  lambda v:h(v)+.108,lambda v:h(v)+.315)

    # Visible structural ends on the outside. Duplicating the seam geometry
    # leaves end heads composable with directly adjacent heads too.
    for v in (-.91,-.46,0,.46,.91):
        m.box("Heavy transverse bearers","Timber — grain",-.482,.482,v-.044,v+.044,
              lambda q:h(q)-.225,lambda q:h(q)-.128,
              face_colors={"left":"Timber — cut ends","right":"Timber — cut ends"})
    if head:
        # The uphill head may overhang a descending terrain face; keep its
        # visually grounded masonry separate from game foundation decisions.
        for i in range(3):
            v=-.48+i*.24
            a=.50-i*.021
            # On a natural bank the low edge is one level beneath the
            # deck. Seat the masonry there rather than hanging from it.
            bottom=lambda q, k=i:h(q)-1.035-k*.014
            top=lambda q:h(q)-.274
            m.box("Head ashlar abutment","Ashlar — dark",-a,a,v-.111,v+.111,bottom,top)
            for j in (-1,1):
                u0,u1=sorted((j*(a-.018),j*(a+.012)))
                shade="Ashlar — warm" if (i+j)%2 else "Ashlar — cold"
                m.box("Head ashlar facing",shade,u0,u1,v-.104,v+.104,
                      lambda q,k=i:h(q)-.981-k*.014,lambda q:h(q)-.282,
                      face_colors={"top":"Ashlar — cap"})
        m.box("Head bearing sill","Ashlar — cap",-.50,.50,-.63,.16,
              lambda q:h(q)-.312,lambda q:h(q)-.259)
    else:
        # First drop to the stackable bent, below the deck at local y=.5.
        m.box("Pier cap timber","Timber — upper edge",-.445,.445,-.123,.123,
              -.151,.239,face_colors={"front":"Timber — grain","under":"Timber — dark"})
        for u in (-.286,.286):
            m.box("Pier cap king posts","Timber — creosote",u-.066,u+.066,-.068,.068,-.5,-.151)


def pier(m):
    for u in (-.286,.286):
        m.box("Trestle legs","Timber — creosote",u-.066,u+.066,-.068,.068,-.5,.5,
              face_colors={"front":"Timber — warm","left":"Timber — mid"})
    for h in (-.401,.39):
        m.box("Trestle collars","Timber — mid",-.367,.367,-.089,.089,h-.035,h+.035,
              face_colors={"front":"Timber — grain","top":"Timber — upper edge"})
    for side in (-1,1):
        m.bar("Diagonal sway braces","Timber — warm",(side*.293,side*.081,-.425),
              (-side*.293,side*.081,.423),.065,.045)
    for side in (-1,1):
        for h in (-.414,.41):
            for v in (-.051,.051):
                m.bolt("Forged pier tie bolts",side*.354,v,h,side)


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    colors=[bytes.fromhex(c) for c in COLORS.values()]
    row=b"".join(c*8 for c in colors)
    out=b"\x89PNG\r\n\x1a\n"
    out+=chunk(b"IHDR",struct.pack(">IIBBBBB",len(colors)*8,8,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (TEXTURES/(PREFIX+".png")).write_bytes(out)


def export(name, m):
    indices={color:i+1 for i,color in enumerate(COLORS)}
    lines=["# LuanTTD original stock-compatible timber bridge art",
           *(f"vt {(i+.5)/len(COLORS):.7f} .5" for i in range(len(COLORS)))]
    v_count,n_count=1,1
    for group,data in m.groups.items():
        lines.append("o "+group.replace(" ","_"))
        vertices,normals,faces={},{},[]
        for color, points in data:
            # Y-up OBJ then engine X reflection; combined mapping keeps winding.
            points=[tuple(round(q,6) for q in (-x-.5,h,z+.5)) for x,z,h in points]
            a,b,c=map(Vector,points)
            perpendicular=(b-a).cross(c-a)
            if perpendicular.length_squared<1e-12:
                raise RuntimeError(f"Degenerate {name} {group}")
            n=tuple(round(q,6) for q in perpendicular.normalized())
            normal=normals.setdefault(n,n_count+len(normals))
            refs=[vertices.setdefault(v,v_count+len(vertices)) for v in points]
            faces.append((refs,indices[color],normal))
        lines.extend("v %.6f %.6f %.6f"%p for p in vertices)
        lines.extend("vn %.6f %.6f %.6f"%n for n in normals)
        for refs,color,n in faces:
            lines.append("f "+" ".join(f"{index}/{color}/{n}" for index in refs))
        v_count+=len(vertices);n_count+=len(normals)
    (MODELS/f"{PREFIX}_{name}.obj").write_text("\n".join(lines)+"\n")


def materials():
    mats={}
    for name,color in COLORS.items():
        mat=bpy.data.materials.new(name)
        rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        rgb=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in rgb]
        mat.diffuse_color=(*rgb,1)
        mats[name]=mat
    return mats


def author(m, name, mats):
    coll=bpy.data.collections.new(name)
    coll.use_fake_user=True
    for group,data in m.groups.items():
        part=bpy.data.meshes.new(group)
        vertices={}
        faces=[tuple(vertices.setdefault(v,len(vertices)) for v in pts) for _,pts in data]
        part.from_pydata(list(vertices),[],faces)
        assigned=list(dict.fromkeys(color for color,_ in data))
        for c in assigned: part.materials.append(mats[c])
        for p,(color,_) in zip(part.polygons,data):
            p.material_index=assigned.index(color)
        part.update()
        o=bpy.data.objects.new(group,part)
        coll.objects.link(o)
    return coll


def instance(collection, location):
    ob=bpy.data.objects.new(collection.name,None)
    ob.instance_type="COLLECTION";ob.instance_collection=collection
    ob.location=location
    bpy.context.scene.collection.objects.link(ob)
    return ob


def showcase(parts):
    for x, name in ((-4,"head_ramp_2"),(-2,"span_0"),(0,"span_0"),(2,"span_0"),(4,"head_flat_0")):
        instance(parts[name],(x,0,1.4))
        if name.startswith("span"):
            instance(parts["pier_0"],(x,0,.4))
            instance(parts["pier_0"],(x,0,-.6))

    def scenery(name, loc, scale, rgb):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        obj=bpy.context.object;obj.name=name;obj.scale=scale
        mat=bpy.data.materials.new(name);mat.diffuse_color=(*rgb,1)
        obj.data.materials.append(mat)
    scenery("Showcase river", (0,0,-.45),(19,16,.18),(.075,.175,.205))
    scenery("Lower bank",(-6.6,0,.22),(3.2,9.0,1.36),(.195,.258,.099))
    scenery("Upper bank",(6.6,0,.94),(3.2,9.0,1.92),(.195,.258,.099))

    bpy.ops.object.camera_add(location=(10.3,-11.7,6.2))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,.8))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=13.3
    scene=bpy.context.scene;scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1500;scene.render.resolution_y=790
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.studiolight_rotate_z=.65
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Bridge sky")
    scene.world.color=(.12,.16,.21)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | Timber road bridge"
    mats=materials()
    sources={}
    for name, head, height in (("span",False,lambda v:DECK),
                              ("head_flat",True,lambda v:DECK),
                              ("head_ramp",True,lambda v:DECK+(v-1)/2)):
        m=Mesh();superstructure(m,height,head)
        if head:
            for direction in range(4):
                sources[f"{name}_{direction}"]=m.oriented(direction)
        else:
            for axis,direction in ((0,2),(1,1)):
                sources[f"{name}_{axis}"]=m.oriented(direction)
    m=Mesh();pier(m)
    for axis,direction in ((0,2),(1,1)):
        sources[f"pier_{axis}"]=m.oriented(direction)
    parts={}
    for name,m in sources.items():
        export(name,m)
        parts[name]=author(m,name,mats)
    atlas()
    showcase(parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"road_bridge_wood.blend"),compress=True)
    if target:=os.environ.get("ROAD_BRIDGE_RENDER"):
        bpy.context.scene.render.filepath=target
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()
