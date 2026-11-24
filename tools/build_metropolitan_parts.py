"""Author the three Metropolitan-only stock graphic roles in Blender.

blender -b --factory-startup --python tools/build_metropolitan_parts.py
The other stock tile graphics already have native City meshes.
"""
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
        lines=["# Metropolitan airport; original Blender model.", "o "+self.name]
        lines += [f"vt {(i+.5)/len(palette):.6f} 0.5" for i in range(len(palette))]
        lines += [f"v {-x:.6f} {y:.6f} {z:.6f}" for x,z,y in self.vertices]
        lines += ["f "+" ".join(f"{i+1}/{c+1}" for i in f) for f,c in zip(self.faces,self.colors)]
        path=MOD/"models"/("bl_"+self.name+".obj")
        tmp=path.with_suffix(".tmp")
        tmp.write_text("\n".join(lines)+"\n")
        tmp.replace(path)


def runway(name,threshold):
    g=Tile(name)
    g.plane(-.5,-.5,1.5,1.5,-.498,0)
    g.plane(-.5,-.38,1.5,.80,-.494,2)
    g.plane(-.5,-.32,1.5,.73,-.490,3)
    for z in (-.315,.707):
        g.plane(-.5,z,1.5,z+.024,-.486,4)
    if threshold:
        for j in range(4):
            z=-.23+j*.21
            g.plane(-.07,z,.40,z+.095,-.484,4)
            g.plane(.63,z,1.04,z+.095,-.484,4)
    else:
        g.plane(-.04,.106,.98,.153,-.484,4)
        # A narrow yellow exit stripe marks the crossing taxiway.
        g.plane(-.5,.758,1.5,.780,-.482,6)
    for x in (-.28,.28,.92,1.39):
        for z in (-.352,.776):
            g.box(x-.020,z-.018,x+.020,z+.018,-.490,-.460,6)
    return g


radar=Tile("metro_radar_fence_ne")
radar.plane(-.5,-.5,1.5,1.5,-.498,0)
radar.box(.05,.12,.86,.92,-.498,-.465,1)
radar.box(.14,.26,.42,.58,-.465,-.30,13)
radar.box(.15,.25,.43,.59,-.31,-.281,8)
radar.round(.63,.57,.16,-.46,-.39,10)
radar.round(.63,.57,.075,-.39,.178,7)
radar.round(.63,.57,.13,.162,.211,10)
# Slotted tracking panel with inset mounts and red position beacon.
radar.box(.24,.52,1.02,.62,.19,.23,10)
for i in range(7):
    x=.27+i*.111
    radar.box(x,.491,x+.057,.65,.23,.417,9)
radar.box(.25,.515,1.01,.626,.403,.434,8)
radar.box(.59,.55,.66,.614,.429,.473,11)
for i in range(11):
    x=-.46+i*.18
    radar.box(x-.013,1.433,x+.013,1.465,-.50,-.263,8)
for y in (-.443,-.35,-.269):
    radar.box(-.48,1.438,1.48,1.458,y,y+.010,8)
parts=(runway("metro_runway_5",False),runway("metro_runway_end",True),radar)
for i,part in enumerate(parts):
    part.finish(i*3.1)
im=bpy.data.images.new("Metropolitan Airport palette",width=18*8,height=8,alpha=True)
im.pixels=[c for _ in range(8) for r,g,b in palette for _ in range(8) for c in (r/255,g/255,b/255,1.0)]
tex=MOD/"textures"/"bl_metropolitan_airport_atlas.png"
im.filepath_raw=str(tex)
im.file_format="PNG"
im.save()
im.pack()
for a in [a for s in bpy.data.screens for a in s.areas if a.type=="VIEW_3D"]:
    a.spaces.active.shading.color_type="MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"metropolitan_airport_parts.blend"),compress=True)
