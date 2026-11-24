"""Generate stock hub-airport graphic roles from original Blender geometry."""
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
        lines=["# Hub airport; original Blender model.", "o "+self.name]
        lines += [f"vt {(i+.5)/len(palette):.6f} 0.5" for i in range(len(palette))]
        lines += [f"v {-x:.6f} {y:.6f} {z:.6f}" for x,z,y in self.vertices]
        lines += ["f "+" ".join(f"{i+1}/{c+1}" for i in f) for f,c in zip(self.faces,self.colors)]
        path=MOD/"models"/("bl_"+self.name+".obj")
        tmp=path.with_suffix(".tmp")
        tmp.write_text("\n".join(lines)+"\n")
        tmp.replace(path)



def mesh_tile(name,ground=1):
    t=Tile(name)
    t.plane(-.5,-.5,1.5,1.5,-.498,ground)
    return t


def fence(t,side):
    def oriented(u,v):
        if side=="NW": return u,v
        if side=="SE": return u,1-v
        if side=="NE": return v,u
        return 1-v,u
    def box(u,v,r,q,y,h,tone):
        x,z=oriented(u,v);w,k=oriented(r,q)
        t.box(min(x,w),min(z,k),max(x,w),max(z,k),y,h,tone)
    for u in (-.45,-.12,.21,.54,.87,1.20,1.46):
        box(u-.012,-.48,u+.012,-.45,-.50,-.26,8)
    for y in (-.445,-.35,-.27):
        box(-.482,-.471,1.482,-.461,y,y+.009,8)


def strip(name,edges,threshold):
    t=mesh_tile(name,0)
    t.plane(-.5,-.32,1.5,1.29,-.49,2)
    t.plane(-.5,-.24,1.5,1.21,-.485,3)
    for z in (-.23,1.176):
        t.plane(-.5,z,1.5,z+.033,-.48,4)
    if threshold:
        for x in (.04,.21,.39,.62,.79,.96):
            t.plane(x,.09,x+.082,.89,-.477,4)
    else:
        t.plane(-.25,.465,1.25,.518,-.477,4)
    for z in (-.28,1.245):
        for x in (-.35,.22,.81,1.36):
            t.box(x-.015,z-.016,x+.015,z+.016,-.49,-.457,6)
    for side in edges: fence(t,side)
    return t


def pad(name,secondary):
    t=mesh_tile(name)
    t.round(.50,.49,.69,-.496,-.482,2,32)
    t.round(.50,.49,.65,-.482,-.477,5,32)
    t.round(.50,.49,.604,-.477,-.470,3,32)
    for x in (.27,.66):
        t.plane(x,.23,x+.065,.75,-.465,4)
    t.plane(.335,.45,.66,.525,-.465,4)
    for x,z in ((-.28,-.19),(1.28,-.19),(1.28,1.19),(-.28,1.19)):
        t.box(x-.024,z-.025,x+.024,z+.025,-.492,-.452,5)
    if secondary: t.plane(.27,1.28,.76,1.31,-.47,6)
    return t


def radar():
    t=mesh_tile("hub_radar_fence_sw",0)
    t.box(.12,.06,.91,.95,-.50,-.447,1)
    t.round(.53,.52,.15,-.44,.14,7)
    t.round(.53,.52,.285,-.47,-.38,10)
    t.box(.07,.41,.99,.61,.13,.19,8)
    for i in range(9):
        x=.14+i*.092
        t.box(x,.43,x+.057,.595,.19,.43,9)
    t.box(.07,.413,.99,.61,.42,.46,8)
    t.box(.505,.486,.55,.54,.46,.52,11)
    fence(t,"SW")
    return t


parts=[strip("hub_runway_fence_nw",("NW",),False),
       strip("hub_runway_end_fence_nw",("NW",),True),
       pad("hub_helipad_1",False),radar()]
for name,edges in (("ne_nw",("NE","NW")),("ne_se",("NE","SE")),
                   ("nw_sw",("NW","SW")),("se_sw",("SE","SW"))):
    parts.append(strip("hub_runway_end_fence_"+name,edges,True))
parts.append(pad("hub_helipad_2",True))
for name,edges in (("ne_sw",("NE","SW")),("se",("SE",))):
    t=mesh_tile("hub_apron_fence_"+name)
    for edge in edges:fence(t,edge)
    parts.append(t)
for name,x0,x1 in (("east",.52,1.5),("west",-.50,.48)):
    t=mesh_tile("hub_apron_half_"+name,0)
    t.plane(x0,-.50,x1,1.50,-.493,1)
    t.plane(x0+.10,-.50,x1-.10,1.50,-.491,5)
    parts.append(t)
g=mesh_tile("hub_flag_perimeter",0)
fence(g,"NE")
g.round(.42,.47,.020,-.50,.62,9,8)
g.face(((.42,.47,.60),(.81,.47,.56),(.81,.47,.41),(.42,.47,.44)),11)
g.face(((.42,.471,.44),(.81,.471,.41),(.81,.471,.56),(.42,.471,.60)),11)
parts.append(g)
parts.append(mesh_tile("hub_grass",0))
# Stock apron cells share a single pavement plane. Small service paint
# lives at a deliberately larger depth offset than the old fine grit.
for suffix,edge in (("",None),("_fence_nw","NW"),("_fence_sw","SW"),("_fence_ne","NE")):
    tile=mesh_tile("hub_apron"+suffix)
    if edge: fence(tile,edge)
    parts.append(tile)
t=mesh_tile("hub_stand")
for x in (.07,.88): t.plane(x,-.08,x+.035,.98,-.477,5)
t.plane(.07,.96,.925,1.00,-.477,5)
t.plane(.48,-.47,.52,.63,-.475,6)
t.plane(.40,-.13,.60,-.088,-.473,6)
t.plane(.40,.63,.60,.672,-.473,6)
for x in (.107,.84): t.box(x,.87,x+.019,.896,-.497,-.453,6)
parts.append(t)
t=mesh_tile("hub_low_building")
t.box(-.20,-.18,1.22,.70,-.50,-.09,9)
t.box(-.24,-.22,1.26,.74,-.10,-.04,7)
for x in (0,.24,.52,.79):t.box(x,.697,x+.16,.707,-.37,-.21,15)
for x in (.15,.72):t.box(x,.032,x+.28,.36,-.04,.045,10)
t.box(.99,.699,1.13,.715,-.50,-.19,13)
parts.append(t)
for i,part in enumerate(parts):part.finish((i%5)*3.1)
for i,part in enumerate(parts):bpy.data.objects[part.name].location.y=(i//5)*3.1
im=bpy.data.images.new("Hub Airport palette",width=len(palette)*8,height=8,alpha=True)
im.pixels=[c for _ in range(8) for r,g,b in palette for _ in range(8) for c in (r/255,g/255,b/255,1.0)]
im.filepath_raw=str(MOD/"textures"/"bl_hub_airport_atlas.tmp.png")
im.file_format="PNG"
im.save()
Path(im.filepath_raw).replace(MOD/"textures"/"bl_hub_airport_atlas.png")
im.filepath_raw=str(MOD/"textures"/"bl_hub_airport_atlas.png")
im.pack()
for a in [a for screen in bpy.data.screens for a in screen.areas if a.type=="VIEW_3D"]:
    a.spaces.active.shading.color_type="MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"hub_airport_parts.tmp.blend"),compress=True)
(ROOT/"art"/"hub_airport_parts.tmp.blend").replace(ROOT/"art"/"hub_airport_parts.blend")
