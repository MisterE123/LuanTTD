#!/usr/bin/env python3
"""Original one-tile office-tower heliport based on RC1 APT_HELIPORT.

python3 tools/build_heliport_art.py [--check]
blender -b -t 3 --python-exit-code 1 --python tools/build_heliport_art.py -- --blend [--preview /tmp/heliport.png]
"""
from argparse import ArgumentParser
from collections import defaultdict
from math import cos, pi, sin, sqrt
from pathlib import Path
from struct import pack
import sys
from zlib import compress, crc32

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/luanttd_core"
DECK = 7.0
# Named, independent swatches. No OpenGFX pixels or palette are reused.
COLORS = {
    "retaining stone":"706b64", "plaza paving":"918a7b", "pavement joint":"6a6c63",
    "ivory aggregate":"beb8a4", "concrete return":"a8a696", "concrete drip":"7a827b",
    "bronze coping":"907342", "entry bronze":"a98e58", "structural steel":"536461",
    "glazed panel":"4c596c", "glazed highlight":"66758a", "glazed warm":"737890",
    "glass recess":"293845", "glass sky edge":"8994a0", "soffit":"505955",
    "asphalt":"3e4846", "roof aggregate":"646c63", "roof bond":"545f55",
    "landing enamel":"ebe3c9", "auxiliary paint":"cfb16a", "door":"526561",
    "beacon red":"ef8762", "beacon cream":"f7dc99", "lobby light":"d6b781",
}
NAMES = list(COLORS)
FLOOR = -.5


class Art:
    def __init__(self):
        self.parts = defaultdict(list)

    def face(self, part, material, *points):
        self.parts[part].append((material,points))

    def slab(self, part, material, boundary, y0, y1, side=None):
        """CCW X/Z footprint. Face winding is outward in game coordinates."""
        side = side or material
        self.face(part,material,*[(x,y1,z) for x,z in reversed(boundary)])
        self.face(part,side,*[(x,y0,z) for x,z in boundary])
        for (x,z),(u,v) in zip(boundary,boundary[1:]+boundary[:1]):
            self.face(part,side,(x,y0,z),(x,y1,z),(u,y1,v),(u,y0,v))

    def box(self, part, material, x0,x1,y0,y1,z0,z1, side=None):
        self.slab(part,material,[(x0,z0),(x1,z0),(x1,z1),(x0,z1)],y0,y1,side)

    def plate(self, part, material, x0,x1,z0,z1,y):
        self.face(part,material,(x0,y,z0),(x0,y,z1),(x1,y,z1),(x1,y,z0))

    def wall(self, part, material, edge, depth, t0,t1,y0,y1):
        if edge=="west":
            q=[(depth,y0,t0),(depth,y0,t1),(depth,y1,t1),(depth,y1,t0)]
        elif edge=="east":
            q=[(depth,y0,t1),(depth,y0,t0),(depth,y1,t0),(depth,y1,t1)]
        elif edge=="north":
            q=[(t1,y0,depth),(t0,y0,depth),(t0,y1,depth),(t1,y1,depth)]
        elif edge=="south":
            q=[(t0,y0,depth),(t1,y0,depth),(t1,y1,depth),(t0,y1,depth)]
        self.face(part,material,*q)


def drum(x0,x1,z0,z1,c):
    return [(x0+c,z0),(x1-c,z0),(x1,z0+c),(x1,z1-c),(x1-c,z1),(x0+c,z1),(x0,z1-c),(x0,z0+c)]


def create():
    a=Art()
    a.box("01 Granite plaza and entrance apron","plaza paving",-.49,1.49,-.524,-.463,-.49,1.49,"retaining stone")
    a.box("01 Granite plaza and entrance apron","retaining stone",-.41,1.39,-.49,-.344,-.42,1.42)
    for i in range(6):
        x=-.35+i*.175
        a.plate("01 Granite plaza and entrance apron","pavement joint",x,x+.009,1.348,1.474,-.460)
    # Main block with the reference's lower attached annex and taller office.
    # Rooftop and lobby are distinct from a commercial runway or a depot.
    a.box("02 Main cast concrete core","ivory aggregate",-.365,.982,-.348,6.925,-.413,1.366)
    a.box("03 Lower stepped terminal annex","concrete return",.98,1.381,-.341,2.713,-.39,1.347)
    a.box("03 Lower stepped terminal annex","roof aggregate",.984,1.422,2.71,2.783,-.414,1.374,"soffit")
    for n in range(6):
        zz=-.34+n*.248
        a.box("03 Lower stepped terminal annex","roof bond",1.027,1.389,2.783,2.790,zz,zz+.011)
    a.box("03 Lower stepped terminal annex","structural steel",1.12,1.272,2.784,2.894,.22,.50)
    for n in range(4):
        zz=.252+n*.057
        a.plate("03 Lower stepped terminal annex","concrete drip",1.153,1.243,zz,zz+.020,2.895)
    # Separate facades with shadow reveals, window jambs and mid-century vanes.
    for floor in range(8):
        low=-.09+floor*.835
        for edge,depth,start,end,panes in (
            ("west",-.368,-.313,1.266,6),("north",-.416,-.276,.883,5),
            ("south",1.369,-.277,.881,5),("east",.984 if floor>=3 else 1.384,-.287,1.230,6),
        ):
            out=-1 if edge in ("west","north") else 1
            span=(end-start)/panes
            for i in range(panes):
                left=start+(i+.08)*span
                right=start+(i+.94)*span
                title="04 Upper bronze mullions, shade vanes and recessed ribbon glass" if floor>=3 else "05 Lower terminal glazing"
                y0=low+.096
                y1=low+.681
                material=("glazed panel","glazed highlight","glazed warm","glazed panel","glazed highlight")[(2*i+floor+(edge=="north"))%5]
                if floor==0 and edge=="south" and i in (1,2,3):
                    material="door"
                    y0=-.335
                a.wall(title,"glass recess",edge,depth,left,right,y0,y1)
                a.wall(title,material,edge,depth+.003*out,left+.019,right-.012,y0+.043,y1-.026)
                a.wall(title,"glass sky edge",edge,depth+.005*out,left+.021,right-.014,y1-.083,y1-.057)
                mid=(left+right)*.5
                a.wall(title,"structural steel",edge,depth+.007*out,mid-.013,mid+.011,y0+.025,y1-.020)
        y=low+.735
        a.box("06 Cantilever floor bands","bronze coping",-.395,1.011,y,y+.034,-.435,1.388,"entry bronze")
        if floor<3:
            a.box("06 Cantilever floor bands","bronze coping",1.009,1.399,y,y+.034,-.417,1.370,"entry bronze")
    # Entrance recess, corner awning and rail. No tall obstructions on flight deck.
    a.box("07 Sheltered passenger entrance","soffit",-.099,.661,.244,.335,1.367,1.487)
    a.box("07 Sheltered passenger entrance","entry bronze",-.099,.661,.335,.365,1.367,1.487)
    for x in (-.043,.28,.605):
        a.box("07 Sheltered passenger entrance","structural steel",x-.014,x+.014,-.444,.250,1.407,1.441)
    a.box("07 Sheltered passenger entrance","lobby light",.134,.439,.237,.248,1.412,1.448)
    a.slab("08 Eight-sided reinforced landing deck","roof aggregate",
           drum(-.48,1.102,-.47,1.429,.165),6.786,6.936,"soffit")
    a.slab("08 Eight-sided reinforced landing deck","bronze coping",
           drum(-.49,1.114,-.480,1.444,.183),6.936,6.958,"concrete return")
    a.slab("08 Eight-sided reinforced landing deck","asphalt",
           drum(-.479,1.103,-.468,1.433,.180),6.958,DECK,"concrete drip")
    # Circular edge guidance around the RC1 terminal point (5,9); the airborne
    # approach lies just beyond the footprint, so the west edge stays clear.
    cx,cz=5/8-.5,9/8-.5
    def paint_ring(part,material,inner,outer,index,count,delta,y):
        p,q=(index+delta)*2*pi/count,(index+1-delta)*2*pi/count
        a.face(part,material,
            (cx+inner*cos(p),y,cz+inner*sin(p)),
            (cx+inner*cos(q),y,cz+inner*sin(q)),
            (cx+outer*cos(q),y,cz+outer*sin(q)),
            (cx+outer*cos(p),y,cz+outer*sin(p)))
    # Circular hazard markings retain enough clearance from the west roof edge.
    for i in range(32):
        paint_ring("09 Landing ring and touchdown surface","landing enamel",.506,.551,i,32,0,DECK+.002)
    # International landing mark, formed from three painted strips, not UI text.
    p="09 Landing ring and touchdown surface"
    a.plate(p,"landing enamel",cx-.172,cx-.098,cz-.211,cz+.211,DECK+.003)
    a.plate(p,"landing enamel",cx+.098,cx+.172,cz-.211,cz+.211,DECK+.003)
    a.plate(p,"landing enamel",cx-.098,cx+.098,cz-.034,cz+.034,DECK+.003)
    for n,(x,z) in enumerate(((-.285,-.372),(.885,-.373),(.980,.573),(.876,1.322),(-.282,1.318),(-.411,.360))):
        a.box("10 Recessed perimeter approach beacons","structural steel",x-.035,x+.035,6.999,7.044,z-.032,z+.032)
        a.box("10 Recessed perimeter approach beacons","beacon cream" if n in (1,4) else "beacon red",
              x-.025,x+.025,7.044,7.072,z-.023,z+.023)
    return a


def rgb(key):
    return tuple(bytes.fromhex(COLORS[key]))


def png(w,h,rows,alpha=False):
    def block(t,data):
        return pack(">I",len(data))+t+data+pack(">I",crc32(t+data)&0xffffffff)
    return b"\x89PNG\r\n\x1a\n"+block(b"IHDR",pack(">IIBBBBB",w,h,8,6 if alpha else 2,0,0,0))+\
        block(b"IDAT",compress(b"".join(b"\0"+r for r in rows),9))+block(b"IEND",b"")


def atlas():
    width=128
    row=b"".join(bytes(rgb(n))*5 for n in NAMES)
    row+=bytes(rgb(NAMES[-1]))*(width-len(row)//3)
    return png(width,16,[row]*16)


def icon():
    # 4x supersampled 32 px icon: stepped tower with bronze glazing, deck circle,
    # and its own silhouette. The completed visual remains clear at hotbar size.
    scale=4
    w=32
    size=scale*w
    pixels=bytearray(size*size*4)
    def polygon(points,color):
        xys=[(x*scale,y*scale) for x,y in points]
        x0,x1=int(min(p[0] for p in xys)),int(max(p[0] for p in xys))+1
        y0,y1=int(min(p[1] for p in xys)),int(max(p[1] for p in xys))+1
        c=bytes.fromhex(color)+b"\xff"
        for iy in range(max(0,y0),min(size,y1)):
            for ix in range(max(0,x0),min(size,x1)):
                y,x=iy+.5,ix+.5
                edge=False
                for (a,b),(u,v) in zip(xys,xys[1:]+xys[:1]):
                    if (b>y)!=(v>y) and x<(u-a)*(y-b)/(v-b)+a: edge=not edge
                if edge:
                    p=(iy*size+ix)*4
                    pixels[p:p+4]=c
    polygon([(2,25),(4,22),(4,14),(7,12),(7,6),(12,2),(19,1),(28,6),(28,23),(30,25),(15,31)],"202e38")
    polygon([(3,25),(15,29),(29,25),(20,21)],"a59b79")
    polygon([(7,7),(18,11),(18,27),(7,24)],"b5ad96")
    polygon([(18,11),(27,7),(27,24),(18,27)],"cec6aa")
    polygon([(5,15),(16,18),(16,27),(5,24)],"938f78")
    polygon([(5,15),(16,18),(19,16),(8,13)],"66746e")
    for i in range(3):
        y=9+i*2.05
        polygon([(8,y),(17,y+2.7),(17,y+3.9),(8,y+1.2)],"546984")
    for i in range(6):
        y=10.5+i*2.31
        polygon([(19,y),(26,y-2.5),(26,y-1.2),(19,y+1.3)],"58748c" if i%2 else "435a72")
    for i in range(3):
        y=16.5+i*2.38
        polygon([(6,y),(15,y+2.3),(15,y+3.45),(6,y+1.15)],"4e627a")
    polygon([(7,6),(13,3),(20,2),(27,6),(26,8),(19,11),(12,10)],"76847c")
    polygon([(9,6),(14,3.8),(19.6,3.1),(25.2,6),(19,9.7),(13,9)],"32474c")
    for i in range(18):
        p,q=i*2*pi/18,(i+1)*2*pi/18
        polygon([(17.2+r*cos(t),6.45+r*.52*sin(t)) for r,t in ((6.5,p),(6.5,q),(4.95,q),(4.95,p))],"fff5d0")
    polygon([(13.9,5.45),(15.55,5.1),(18.1,7.65),(16.65,8.05)],"fff5d0")
    polygon([(17.1,4.85),(18.75,4.55),(21.3,6.96),(19.8,7.35)],"fff5d0")
    polygon([(15.8,6.38),(19.6,5.62),(20.2,6.31),(16.55,7.15)],"fff5d0")
    polygon([(8,24.7),(12,25.7),(12,26.7),(8,25.7)],"e1bd7f")
    lines=[]
    for y in range(w):
        line=bytearray()
        for x in range(w):
            start=(y*scale*size+x*scale)*4
            colors=[pixels[start+4*(u+v*size):start+4*(u+v*size)+4] for u in range(scale) for v in range(scale)]
            solid=[c for c in colors if c[-1]]
            if solid:
                line.extend(round(sum(c[k] for c in solid)/len(solid)) for k in range(3))
                line.append(round(255*len(solid)/(scale*scale)))
            else: line.extend(b"\0\0\0\0")
        lines.append(line)
    return png(w,w,lines,True)


def obj(a):
    # Irrlicht's OBJ importer flips X. Blender master remains world orientation.
    out=["# Original LuanTTD RC1 heliport; generated by tools/build_heliport_art.py","o Heliport"]
    for i in range(len(COLORS)):
        out.append(f"vt {(5*i+2.5)/128:.8f} .5")
    vertices,normals,polygons={},{},[]
    for part,faces in a.parts.items():
        polygons.append("# "+part)
        for mat,face in faces:
            pts=list(reversed([(-x,y,z) for x,y,z in face]))
            keys=[tuple(round(v,6) or 0 for v in p) for p in pts]
            ids=[vertices.setdefault(p,len(vertices)+1) for p in keys]
            u=[pts[1][j]-pts[0][j] for j in range(3)]
            v=[pts[2][j]-pts[0][j] for j in range(3)]
            n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            d=sqrt(sum(q*q for q in n))
            assert d>1e-9,(mat,face)
            n=tuple(round(q/d,7) or 0 for q in n)
            ni=normals.setdefault(n,len(normals)+1)
            ti=NAMES.index(mat)+1
            for i in range(1,len(face)-1):
                polygons.append("f "+" ".join(f"{ids[j]}/{ti}/{ni}" for j in (0,i,i+1)))
    out.extend("v "+" ".join(f"{q:.6f}" for q in v) for v in vertices)
    out.extend("vn "+" ".join(f"{q:.7f}" for q in n) for n in normals)
    out.extend(polygons)
    return ("\n".join(out)+"\n").encode()


def blend(a,preview):
    import bpy
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene["design"]="16.0-RC1 single-tile Heliport; local deck Y=7.0 at level+1"
    def material(name,color):
        m=bpy.data.materials.new(name)
        def srgb(x): return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
        m.diffuse_color=(*[srgb(c/255) for c in color],1)
        return m
    materials={key:material(key,rgb(key)) for key in COLORS}
    for name,records in a.parts.items():
        vertices,indices=[],[]
        for mat,face in records:
            indices.append(tuple(range(len(vertices),len(vertices)+len(face))))
            vertices.extend((x,-z,y) for x,y,z in face)
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(vertices,[],indices)
        mesh.update()
        keys=list(dict.fromkeys(k for k,_ in records))
        for key in keys: mesh.materials.append(materials[key])
        for face,(mat,_) in zip(mesh.polygons,records): face.material_index=keys.index(mat)
        scene.collection.objects.link(bpy.data.objects.new(name,mesh))
    scene.render.engine="BLENDER_WORKBENCH"
    sh=scene.display.shading
    sh.color_type="MATERIAL"
    sh.light="STUDIO"
    sh.show_shadows=True
    sh.studiolight_rotate_z=.33
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    sh.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Slate");
    scene.world.color=(.056,.070,.077)
    bpy.ops.object.camera_add(location=(9,-14,10.3))
    cam=bpy.context.object
    cam.name="Review camera"
    cam.rotation_euler=(Vector((.45,-.48,3.24))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=9.35
    scene.camera=cam
    scene.render.resolution_x=560
    scene.render.resolution_y=600
    scene.view_settings.exposure=.45
    scene.view_settings.view_transform="Standard"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/heliport.blend"),compress=True)
    if preview:
        scene.render.filepath=preview
        bpy.ops.render.render(write_still=True)


def assets(a):
    return {
        MOD/"models/bl_heliport_0_0.obj":obj(a),
        MOD/"textures/bl_heliport_atlas.png":atlas(),
        MOD/"textures/bl_dispatch_heliport.png":icon(),
    }


def main():
    p=ArgumentParser()
    p.add_argument("--check",action="store_true")
    p.add_argument("--blend",action="store_true")
    p.add_argument("--preview")
    flags=p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else (sys.argv[1:] if "bpy" not in sys.modules else []))
    a=create()
    for path,payload in assets(a).items():
        if flags.check: assert path.read_bytes()==payload,path
        elif not path.exists() or path.read_bytes()!=payload: path.write_bytes(payload)
    if flags.blend: blend(a,flags.preview)


if __name__=="__main__":
    main()
