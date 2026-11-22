"""Author an original 1930 steel plate girder road bridge for LuanTTD.

blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_girder_art.py
Optional GIRDER_BRIDGE_RENDER=/tmp/girder.png saves a Blender overview.
"""
from math import cos, pi, sin
import os
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_bridge_art as tooling

bpy=tooling.bpy
PREFIX="bl_road_bridge_girder"
COLORS={
    "Asphalt":"4f5255", "Road shoulder":"9a937e", "Road centre marking":"efe3b6",
    "Painted web":"476d78", "Inset plate":"3a5964", "Girder edge":"638492",
    "Steel weathering":"526f71", "Girder shadow":"30464d", "Bolts":"9baeb0",
    "Balustrade":"536b70", "Rail cap":"99aaa7", "Concrete slab":"a49d8a",
    "Infill":"7e8374", "Concrete shade":"717775", "Dressed masonry":"9b8f7e",
    "Footing stone":"b1a693", "Mortar":"636e67", "Spout":"635750",
}
DECK=.5


def assign_style():
    # Only used by this standalone authoring script. Runtime is plain OBJ
    # plus atlas; importing this script doesn't modify the timber module.
    tooling.PREFIX=PREFIX
    tooling.COLORS=COLORS


def one_face(m,g,material,side,u,v0,v1,bottom,top):
    pts=[(u,v0,bottom(v0)),(u,v1,bottom(v1)),(u,v1,top(v1)),(u,v0,top(v0))]
    m.poly(g,material,*(pts if side>0 else pts[::-1]))


def rivet(m, group, side, u, v, h, r=.011):
    # Six machined faces, rounded in two rings, not just pixels or decals.
    def ring(tip,radius):
        return [(u+side*tip,v+radius*cos(q*pi/3),h+side*radius*sin(q*pi/3)) for q in range(6)]
    base,sidewall,cap=ring(-.001,r),ring(.006,r),ring(.011,.58*r)
    m.poly(group,"Bolts",*cap)
    for i in range(6):
        j=(i+1)%6
        m.poly(group,"Painted web",base[i],base[j],sidewall[j],sidewall[i])
        m.poly(group,"Steel weathering",sidewall[i],sidewall[j],cap[j],cap[i])


def prism(m,g,color,base,top,y0,y1,under=True,above=True):
    if under:
        m.poly(g,color,*[(x,z,y0) for x,z in reversed(base)])
    if above:
        m.poly(g,color,*[(x,z,y1) for x,z in top])
    for i in range(len(base)):
        j=(i+1)%len(base)
        m.poly(g,color,(*base[i],y0),(*base[j],y0),(*top[j],y1),(*top[i],y1))


def bevel_footprint(width,depth,c):
    x,z=width/2,depth/2
    return ((-x+c,-z),(x-c,-z),(x,-z+c),(x,z-c),(x-c,z),(-x+c,z),(-x,z-c),(-x,-z+c))


def continuous(m,h,is_head):
    tooling.running_surface(m,h)
    m.box("Composite deck slab","Concrete slab",-.426,.426,-1,1,
          lambda v:h(v)-.112,lambda v:h(v)-.007,end_faces=False,
          face_colors={"under":"Concrete shade"})
    m.box("Structural floor chords","Girder shadow",-.386,.386,-1,1,
          lambda v:h(v)-.237,lambda v:h(v)-.121,end_faces=False)
    for side in (-1,1):
        def bounds(a,b): return sorted((side*a,side*b))
        u0,u1=bounds(.377,.422)
        m.box("Continuous plate girders","Painted web",u0,u1,-1,1,
              lambda v:h(v)-.362,lambda v:h(v)-.078,end_faces=False,
              face_colors={"under":"Girder shadow"})
        u0,u1=bounds(.354,.466)
        for low,high in ((.381,.341),(.111,.074)):
            m.box("Continuous angle flanges","Girder edge",u0,u1,-1,1,
                  lambda v,k=low:h(v)-k,lambda v,k=high:h(v)-k,end_faces=False,
                  face_colors={"under":"Girder shadow","top":"Steel weathering"})
        # Plate field treatments, standing stiffeners, and rows of rivets
        # are all subunits of a repeated span and never occupy the join.
        for i,v in enumerate((-.80,-.40,0,.40,.80)):
            if not is_head or v>-.65:
                one_face(m,"Hollow web pockets","Inset plate" if i%2==0 else "Painted web",
                         side,side*.423,v-.176,v+.176,lambda q:h(q)-.316,lambda q:h(q)-.142)
                u0,u1=bounds(.418,.455)
                for edge in (-.177,.177):
                    pos=v+edge
                    m.box("Riveted transverse stiffeners","Steel weathering",u0,u1,pos-.015,pos+.015,
                          lambda q:h(q)-.337,lambda q:h(q)-.115,
                          face_colors={"top":"Girder edge"})
                for q in (-.147,-.097,.097,.147):
                    pos=v+q
                    rivet(m,"Raised web rivets",side,side*.425,pos,h(pos)-.325)
                    rivet(m,"Raised web rivets",side,side*.425,pos,h(pos)-.131)
        u0,u1=bounds(.386,.449)
        start=-.82 if is_head else -1
        for low,high,color in ((.235,.270,"Rail cap"),(.081,.102,"Girder edge")):
            m.box("Continuous steel handrails",color,u0,u1,start,1,
                  lambda v,k=low:h(v)+k,lambda v,k=high:h(v)+k,end_faces=False,
                  face_colors={"under":"Girder shadow"})
        for i,v in enumerate((-.77,-.55,-.33,-.11,.11,.33,.55,.77)):
            u0,u1=bounds(.392,.447)
            heavy=i%2==0
            r=.027 if heavy else .010
            m.box("Steel balusters","Balustrade" if heavy else "Inset plate",u0,u1,v-r,v+r,
                  lambda q:h(q)-.025,lambda q:h(q)+(.284 if heavy else .245),
                  face_colors={"top":"Rail cap"} if heavy else None)
        if is_head:
            u0,u1=bounds(.379,.46)
            m.box("Approach terminal newel","Girder edge",u0,u1,-.841,-.787,
                  lambda q:h(q)+.03,lambda q:h(q)+.29,
                  face_colors={"top":"Rail cap"})
    if is_head:
        abutment(m,h)
    else:
        pier_cap(m)


def abutment(m,h):
    m.box("Abutment concrete backing","Concrete shade",-.473,.473,-.59,.335,
          lambda q:h(q)-.50,lambda q:h(q)-.379)
    for side in (-1,1):
        a,b=sorted((side*.449,side*.49))
        for j,v in enumerate((-.51,-.33,-.15,.03,.21)):
            m.box("Dressed abutment facing","Dressed masonry" if j%2 else "Footing stone",
                  a,b,v-.083,v+.083,lambda q:h(q)-.505,lambda q:h(q)-.387,
                  face_colors={"top":"Infill"})
    m.box("Sloped deck bearing sill","Footing stone",-.486,.486,-.583,.35,
          lambda q:h(q)-.414,lambda q:h(q)-.371,
          face_colors={"under":"Concrete shade"})


def pier_cap(m):
    m.box("Crosshead bearings","Inset plate",-.465,.465,-.054,.054,.092,.16)
    collar=bevel_footprint(.748,.285,.038)
    column=bevel_footprint(.528,.227,.041)
    prism(m,"Chamfered pier cap","Dressed masonry",collar,collar,-.016,.105)
    prism(m,"Battered cap haunch","Infill",column,collar,-.19,-.016)
    prism(m,"Pier crown","Concrete shade",column,column,-.50,-.19,under=False)


def pier(m):
    foot=bevel_footprint(.528,.227,.041)
    prism(m,"Octagonal concrete pier","Infill",foot,foot,-.5,.5,under=False,above=False)
    band=bevel_footprint(.57,.269,.048)
    prism(m,"Dressed bolster collars","Dressed masonry",band,band,.351,.429)
    prism(m,"Dressed bolster collars","Concrete shade",band,band,-.406,-.338)
    for side in (-1,1):
        u0,u1=sorted((side*.244,side*.269))
        for base in (-.306,-.086,.134):
            m.box("Dressed facing courses","Footing stone" if base>0 else "Dressed masonry",u0,u1,
                  -.070,.07,base,base+.202,face_colors={"right":"Concrete slab","left":"Concrete slab"})


def main():
    assign_style()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | 1930 steel girder road bridge"
    mats=tooling.materials()
    models={}
    for name,head,height in (("span",False,lambda v:DECK),
                             ("head_flat",True,lambda v:DECK),
                             ("head_ramp",True,lambda v:DECK+(v-1)/2)):
        shape=tooling.Mesh()
        continuous(shape,height,head)
        for key,d in (enumerate(range(4)) if head else ((0,2),(1,1))):
            models[f"{name}_{key}"]=shape.oriented(d)
    shape=tooling.Mesh()
    pier(shape)
    for axis,d in ((0,2),(1,1)): models[f"pier_{axis}"]=shape.oriented(d)
    parts={}
    for name,shape in models.items():
        tooling.export(name,shape)
        parts[name]=tooling.author(shape,name,mats)
    tooling.atlas()
    tooling.showcase(parts)
    scene=bpy.context.scene
    scene.display.shading.studio_light="paint.sl"
    scene.display.shading.cavity_ridge_factor=1.55
    scene.display.shading.cavity_valley_factor=.85
    bpy.ops.wm.save_as_mainfile(filepath=str(tooling.ROOT/"art"/"road_bridge_girder.blend"),compress=True)
    if target:=os.environ.get("GIRDER_BRIDGE_RENDER"):
        scene.render.filepath=target
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()
