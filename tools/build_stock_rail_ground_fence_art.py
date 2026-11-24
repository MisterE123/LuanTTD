#!/usr/bin/env python3
"""Original coil wire and galvanized rail fence for the RC1 RailGroundType forms.

python3 tools/build_stock_rail_ground_fence_art.py [--check]
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_ground_fence_art.py -- --blend --preview /tmp/luanttd-rail-ground-fence.png
"""
from argparse import ArgumentParser
from collections import defaultdict
from math import hypot, sqrt
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_heliport_art import png

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
TEX=ROOT/"mods/luanttd_core/textures"
STEM="rail_ground_fence"
ATLAS_W,H=128,32
COLORS=("3d4e57","647c87","516674","9aadaa","6e7c78","53605a")
OUTER_L=-.375
OUTER_H=1.375
P0=-.480
P1=1.480
DIAG0=-.475
DIAG1=1.475
FLOOR=-.5
POST_TOP=.455
POST_FOOT=-.039
WIRE_BOTTOM=.057
WIRE_TOP=.377
# RC1 1301/02 rails and 1303/04 full tile diagonals. Vert/Horiz pairs have
# different CornerRefs for modified ground in OpenTTD; on flat native
# grade (the only supported profile where they arise) they share their mesh.
BORDERS={
    "nw":((P0,OUTER_L),(P1,OUTER_L)), "se":((P0,OUTER_H),(P1,OUTER_H)),
    "ne":((OUTER_L,P0),(OUTER_L,P1)), "sw":((OUTER_H,P0),(OUTER_H,P1)),
    "vert":((DIAG0,DIAG0),(DIAG1,DIAG1)), "horiz":((DIAG0,DIAG1),(DIAG1,DIAG0)),
}
FORMS={2:("nw",),3:("se",),4:("nw","se"),5:("ne",),6:("sw",),7:("ne","sw"),
       8:("vert",),9:("vert",),10:("horiz",),11:("horiz",)}
CORNER_REFERENCE={8:"W",9:"E",10:"N",11:"S"}
PROFILES={0:tuple(FORMS),3:(2,3,4),12:(2,3,4),6:(5,6,7),9:(5,6,7)}


def height(x,z,p):
    u,v=(x+.5)/2,(z+.5)/2
    return FLOOR+{0:0,3:u,12:1-u,6:v,9:1-v}[p]


def rgb(i):
    return tuple(bytes.fromhex(COLORS[i]))


def texture():
    rows=[]
    for y in range(H):
        s=bytearray()
        for x in range(ATLAS_W):
            if x>=96:
                color=rgb(min((x-96)//5,len(COLORS)-1))
                s.extend((*color,255))
            elif x>=88:
                s.extend((122,134,128,0))
            else:
                # Original painted lattice, two pitches in height. Alpha is
                # intentionally binary for Luanti's color-keyed node clip path.
                t=min((x+y*.70)%11,11-(x+y*.70)%11)
                u=min((x-y*.70)%11,11-(x-y*.70)%11)
                wire=min(t,u)<.92
                c=(143,152,145) if t<u else (116,128,124)
                s.extend((*c,255 if wire else 0))
        rows.append(s)
    return png(ATLAS_W,H,rows,True)


def uv(i):
    return ((96+5*i+2.5)/ATLAS_W,.5)


class Fence:
    def __init__(self):
        self.parts=defaultdict(list)

    def face(self,group,mat,pts,tex=None):
        self.parts[group].append((mat,pts,tex))

    def box(self,group,a,b,low,high,w,d,top=3,colors=(0,2,1,0),bottom=0):
        # Ground follows the post foot centre. Posts stay truly vertical
        # (unlike applying a shear to their widths along with the rails).
        points=[(a-w,low,b-d),(a+w,low,b-d),(a+w,low,b+d),(a-w,low,b+d)]
        points += [(x,high,z) for x,_,z in points]
        self.face(group,top,tuple(points[i] for i in (7,6,5,4)))
        self.face(group,bottom,tuple(points[i] for i in (0,1,2,3)))
        for i,color in enumerate(colors):
            j=(i+1)%4
            self.face(group,color,tuple(points[k] for k in (i,i+4,j+4,j)))

    def rail(self,group,a,b,w,h,top=3,side=2):
        """Square section; conform running axis to the continuous grade."""
        x,y,z=a
        u,v,t=b
        length=hypot(u-x,t-z)
        n,m=-(t-z)/length*w,(u-x)/length*w
        p=[(xx+sx*n,hh+sy*h,zz+sx*m) for xx,hh,zz in (a,b)
           for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))]
        # Cross-section winding from the start (opposite along).
        for i,inds in enumerate(((0,1,2,3),(7,6,5,4),(0,4,5,1),
                                  (1,5,6,2),(2,6,7,3),(3,7,4,0))):
            self.face(group,top if i==4 else side,tuple(p[j] for j in inds))


def build(ground,profile,preview=False):
    assert ground in PROFILES[profile]
    mesh=Fence()
    for part in FORMS[ground]:
        (x,z),(u,v)=BORDERS[part]
        dx,dz=u-x,v-z

        def position(t,raise_y):
            q,r=x+dx*t,z+dz*t
            return (q,height(q,r,profile)+raise_y,r)

        # Five single strong posts are enough for a 2-node tile. There are
        # no duplicate posts at the overlapping end of a double edge.
        for t in (0,.25,.50,.75,1):
            q,h,r=position(t,0)
            mesh.box("Steel posts and exposed zinc caps",q,r,h+POST_FOOT,h+POST_TOP,.015,.015)
        mesh.rail("Pressed coping and low cable rail",position(0,.397),position(1,.397),.012,.012)
        mesh.rail("Pressed coping and low cable rail",position(0,.048),position(1,.048),.008,.009,4,4)
        if preview:
            # Geometric wire proxy for Blender Workbench. Runtime uses just
            # two cutout quads, reducing cost at every tile across the map.
            for sign,phase in ((1,0),(-1,.055)):
                for i in range(-2,10):
                    start=i*.125+phase
                    end=start+sign*.19
                    lo=max(0,min(1,-start/(end-start))) if start<0 or end<0 else 0
                    hi=max(0,min(1,(1-start)/(end-start))) if start>1 or end>1 else 1
                    a,b=sorted((lo,hi))
                    ta,tb=start+(end-start)*a,start+(end-start)*b
                    if not (-1e-8<=ta<=1+1e-8 and -1e-8<=tb<=1+1e-8) or b-a<1e-5:continue
                    ya,yb=WIRE_BOTTOM+(WIRE_TOP-WIRE_BOTTOM)*a,WIRE_BOTTOM+(WIRE_TOP-WIRE_BOTTOM)*b
                    mesh.rail("Editable wire lattice proxy",position(ta,ya),position(tb,yb),.0045,.005,4,3)
        else:
            pts=tuple(position(t,h) for t,h in ((0,WIRE_BOTTOM),(1,WIRE_BOTTOM),(1,WIRE_TOP),(0,WIRE_TOP)))
            tex=((0.5/ATLAS_W,1.5/H),(87.5/ATLAS_W,1.5/H),(87.5/ATLAS_W,30.5/H),(.5/ATLAS_W,30.5/H))
            mesh.face("Stationary cutout galvanized lattice",None,pts,tex)
            mesh.face("Stationary cutout galvanized lattice",None,pts[::-1],tex[::-1])
    return mesh


def serialize(mesh):
    # Luanti reflects X, then the odd native anchor offsets +1 world node.
    # Both effects are compensated here. No per-tile/entity transform needed.
    out=["# Original RC1-ground stock railway fence; tools/build_stock_rail_ground_fence_art.py",
         "o RailwayFence"]
    verts,normals,uvs={}, {}, {}
    polys=[]
    for part,faces in mesh.parts.items():
        polys.append("# "+part)
        for palette,pts,custom in faces:
            points=list(reversed([(1-x,y,z) for x,y,z in pts]))
            vs=[verts.setdefault(tuple(round(v,6) or 0 for v in p),len(verts)+1) for p in points]
            ts=[uvs.setdefault(tuple(round(v,8) for v in t),len(uvs)+1)
                for t in (custom[::-1] if custom else (uv(palette),)*len(pts))]
            a=[points[1][i]-points[0][i] for i in range(3)]
            b=[points[2][i]-points[0][i] for i in range(3)]
            n=tuple(a[i]*b[j]-a[j]*b[i] for i,j in ((1,2),(2,0),(0,1)))
            d=sqrt(sum(q*q for q in n))
            assert d>1e-10
            ni=normals.setdefault(tuple(round(q/d,6) or 0 for q in n),len(normals)+1)
            # All pieces are convex quads, supported by Luanti's OBJ loader.
            polys.append("f "+" ".join(f"{vs[q]}/{ts[q]}/{ni}" for q in range(len(points))))
    def num(q,places):
        return format(q,f".{places}f").rstrip("0").rstrip(".") or "0"
    out.extend("v "+" ".join(num(q,6) for q in p) for p in verts)
    out.extend("vt "+" ".join(num(q,8) for q in t) for t in uvs)
    out.extend("vn "+" ".join(num(q,6) for q in n) for n in normals)
    out.extend(polys)
    return ("\n".join(out)+"\n").encode()


def assets():
    yield TEX/f"bl_{STEM}_atlas.png",texture()
    for profile,forms in PROFILES.items():
        for ground in forms:
            yield MODELS/f"bl_{STEM}_{ground}_{profile}.obj",serialize(build(ground,profile))


def editable(preview):
    import bpy
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.name="Original welded railway fencing — RC1 forms"
    scene["native"]="+(one node X) anchor world=tileX*2+1, y=track level+1; offset compensated in runtime mesh. 0,3,12,6,9 are post-foundation grades."
    colors=[]
    for i in range(len(COLORS)):
        c=bpy.data.materials.new("Fence metal "+str(i))
        def lin(t):return t/12.92 if t<=.04045 else ((t+.055)/1.055)**2.4
        c.diffuse_color=(*[lin(v/255) for v in rgb(i)],1)
        colors.append(c)
    turf=bpy.data.materials.new("Reference grade geometry (not exported)")
    turf.diffuse_color=(.173,.264,.114,1)
    scene_positions=[(g,p) for p,fs in PROFILES.items() for g in fs]
    for index,(g,p) in enumerate(scene_positions):
        xx=(index%6)*2.72
        zz=(index//6)*2.82
        c=bpy.data.collections.new(f"Ground {g}, profile {p}")
        scene.collection.children.link(c)
        for part,polys in build(g,p,True).parts.items():
            points,faces=[],[]
            for palette,verts,custom in polys:
                faces.append(tuple(range(len(points),len(points)+len(verts))))
                points.extend((xx+x,-(zz+z),y) for x,y,z in verts)
            me=bpy.data.meshes.new(part)
            me.from_pydata(points,[],faces)
            me.update()
            for mat in colors:me.materials.append(mat)
            for poly,(idx,_,_) in zip(me.polygons,polys):poly.material_index=idx
            c.objects.link(bpy.data.objects.new(part,me))
        verts=[(x,z) for x,z in ((-.5,-.5),(1.5,-.5),(1.5,1.5),(-.5,1.5))]
        mesh=bpy.data.meshes.new("Grade datum")
        mesh.from_pydata([(xx+x,-(zz+z),height(x,z,p)-.001) for x,z in verts],[],[(0,3,2,1)])
        mesh.materials.append(turf)
        c.objects.link(bpy.data.objects.new("Optional grade datum",mesh))
    aim=Vector((7.44,-4.47,-.22))
    bpy.ops.object.camera_add(location=aim+Vector((8,-15,20)))
    cam=bpy.context.object
    cam.name="Review stock grade and fence sheet"
    cam.rotation_euler=(aim-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=20.5
    scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1200
    scene.render.resolution_y=875
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.50
    sh=scene.display.shading
    sh.color_type="MATERIAL"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                view=a.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=aim
                view.region_3d.view_distance=20
                view.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/stock_rail_ground_fence.blend"),compress=True)
    if preview:
        scene.render.filepath=preview
        bpy.ops.render.render(write_still=True)


def main():
    p=ArgumentParser()
    p.add_argument("--check",action="store_true")
    p.add_argument("--blend",action="store_true")
    p.add_argument("--preview")
    flags=p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else (sys.argv[1:] if "bpy" not in sys.modules else []))
    for file,data in assets():
        if flags.check:assert file.read_bytes()==data,file
        elif not file.exists() or file.read_bytes()!=data:file.write_bytes(data)
    if flags.blend:editable(flags.preview)


if __name__=="__main__":main()
