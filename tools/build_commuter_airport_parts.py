"""Generate native Commuter-only graphic roles from original Blender geometry."""
from pathlib import Path
from math import cos,sin,pi
import bpy

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
palette=((79,100,52),(101,110,97),(66,68,70),(49,52,54),(211,211,194),
         (215,179,97),(242,200,77),(38,51,68),(135,153,156),(184,194,182),
         (106,114,116),(182,70,43),(98,63,45),(82,92,88),(60,73,56),
         (88,125,150),(135,130,104),(51,59,65))
bpy.ops.wm.read_factory_settings(use_empty=True)
materials=[]
for i,(r,g,b) in enumerate(palette):
    m=bpy.data.materials.new("Field shade %02d"%i)
    m.diffuse_color=(r/255,g/255,b/255,1)
    materials.append(m)


class Tile:
    def __init__(self,name):
        self.name=name
        self.vertices=[]
        self.faces=[]
        self.colors=[]
    def face(self,pts,tone):
        i=len(self.vertices)
        self.vertices.extend(pts)
        self.faces.append(tuple(range(i,i+len(pts))))
        self.colors.append(tone)
    def plane(self,x0,z0,x1,z1,y,tone):
        self.face(((x0,z0,y),(x1,z0,y),(x1,z1,y),(x0,z1,y)),tone)
    def box(self,x0,z0,x1,z1,y0,y1,tone):
        pts=((x0,z0,y0),(x1,z0,y0),(x1,z1,y0),(x0,z1,y0),
             (x0,z0,y1),(x1,z0,y1),(x1,z1,y1),(x0,z1,y1))
        for f in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):
            self.face(tuple(pts[i] for i in f),tone)
    def round(self,x,z,r,y0,y1,tone,n=10):
        ring=[(x+r*cos(i*2*pi/n),z+r*sin(i*2*pi/n)) for i in range(n)]
        self.face([(u,v,y1) for u,v in ring],tone)
        for i,(u,v) in enumerate(ring):
            w,q=ring[(i+1)%n]
            self.face(((u,v,y0),(w,q,y0),(w,q,y1),(u,v,y1)),tone)
    def finish(self,offset):
        m=bpy.data.meshes.new(self.name)
        m.from_pydata(self.vertices,[],self.faces)
        m.update()
        for mat in materials: m.materials.append(mat)
        for poly,tone in zip(m.polygons,self.colors):poly.material_index=tone
        obj=bpy.data.objects.new(self.name,m)
        bpy.context.collection.objects.link(obj)
        obj.location.x=offset
        lines=["# Commuter airport; original Blender model.", "o "+self.name]
        lines += [f"vt {(i+.5)/len(palette):.6f} 0.5" for i in range(len(palette))]
        lines += [f"v {-x:.6f} {y:.6f} {z:.6f}" for x,z,y in self.vertices]
        lines += ["f "+" ".join(f"{i+1}/{c+1}" for i in f) for f,c in zip(self.faces,self.colors)]
        path=MOD/"models"/("bl_"+self.name+".obj")
        tmp=path.with_suffix(".tmp")
        tmp.write_text("\n".join(lines)+"\n")
        tmp.replace(path)


def concrete():
    t=Tile("commuter_apron_fence_ne")
    t.plane(-.5,-.5,1.5,1.5,-.498,1)
    for x in (-.492,.008,.508,1.008):
        t.plane(x,-.5,x+.008,1.5,-.493,13)
    for z in (-.10,.50,1.10):
        t.plane(-.5,z,1.5,z+.010,-.492,13)
    for z in (-.48,-.10,.28,.66,1.04,1.44):
        t.box(-.49,z-.012,-.461,z+.012,-.5,-.263,8)
    for h in (-.445,-.353,-.271):
        t.box(-.481,-.49,-.467,1.49,h,h+.009,8)
    return t


def pad():
    t=Tile("commuter_helipad_2_fence_nw")
    t.plane(-.5,-.5,1.5,1.5,-.498,1)
    t.round(.50,.49,.67,-.498,-.481,3,32)
    t.round(.50,.49,.623,-.481,-.478,6,32)
    t.round(.50,.49,.574,-.478,-.475,3,32)
    for x in (.31,.61):
        t.plane(x,.25,x+.07,.74,-.473,4)
    t.plane(.38,.455,.61,.53,-.473,4)
    for x in (-.43,-.10,.28,.67,1.06,1.44):
        t.box(x-.013,-.487,x+.013,-.461,-.50,-.27,8)
    for h in (-.449,-.355,-.268):
        t.box(-.49,-.482,1.49,-.466,h,h+.011,8)
    for x,z in ((.09,.01),(.91,.01),(.91,1.05),(.09,1.05)):
        t.box(x-.029,z-.029,x+.029,z+.029,-.48,-.451,6)
    return t


def tower():
    t=Tile("commuter_tower")
    t.plane(-.5,-.5,1.5,1.5,-.498,1)
    t.box(-.08,-.15,.87,.77,-.496,-.438,10)
    t.box(.08,.03,.66,.63,-.44,.14,9)
    t.box(.18,-.052,.55,.042,-.44,-.09,7)
    for i in range(3):
        y=-.31+i*.111
        t.box(.68,.11,.686,.45,y,y+.021,7)
    t.box(-.07,-.10,.81,.78,.13,.20,10)
    t.box(.02,-.013,.72,.67,.195,.416,15)
    for x in (.02,.24,.48,.702):
        t.box(x,-.023,x+.026,-.008,.193,.425,7)
        t.box(x,.669,x+.026,.682,.193,.425,7)
    for z in (.17,.34,.51):
        for x in (.011,.713):
            t.box(x,z,x+.018,z+.022,.193,.425,7)
    t.box(-.022,-.055,.771,.72,.413,.468,8)
    t.round(.38,.327,.026,.465,.694,10)
    for y in (.57,.65):
        t.box(.19,.319,.58,.337,y,y+.014,10)
    t.box(.359,.306,.401,.347,.688,.722,11)
    return t

for i,part in enumerate((concrete(),pad(),tower())): part.finish(i*3.1)
im=bpy.data.images.new("Commuter Airport palette",width=len(palette)*8,height=8,alpha=True)
im.pixels=[c for _ in range(8) for r,g,b in palette for _ in range(8) for c in (r/255,g/255,b/255,1.0)]
im.filepath_raw=str(MOD/"textures"/"bl_commuter_airport_atlas.png")
im.file_format="PNG"
im.save()
im.pack()
for a in [a for screen in bpy.data.screens for a in screen.areas if a.type=="VIEW_3D"]:
    a.spaces.active.shading.color_type="MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"commuter_airport_parts.blend"),compress=True)
