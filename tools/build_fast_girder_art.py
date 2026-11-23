"""Original short high-speed girder family for OpenTTD RC1 stock bridge #9.

Both decks share new welded box-girder geometry in editable Blender
collections. Running surfaces meet the existing standard road and rail.
"""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_bridge_art as kit
import build_rail_span_art as rail
import build_road_bridge_girder_art as geometry
from build_bridge_clearance_meshes import clear_span
from build_bridge_pier_feet import write_feet

bpy=kit.bpy
BEARINGS={"Fast_girder_crosshead","Elastomeric_bearing_bank","Pier_throat"}
COLORS={**rail.COLORS,
  "Asphalt":"4f5255","Road shoulder":"9a937e","Road centre marking":"efe3b6",
  "Box steel mid":"526c81","Box steel bright":"7792a0","Box steel under":"364953",
  "Weld seam":"53606a","Handrail":"bdc2b3","Reflector":"c87b4c",
  "Box interior":"293b40","Deck aggregate":"8b8a80","Drain casting":"59676f",
  "Hardened concrete":"989b92","Cast concrete face":"777e78","Base patina":"606b64",
  "Elastomer":"343b3d","Expansion teeth":"898474","Cover panel":"627487",
  "Workshop blue":"677f91","Bolts":"8b999f","Painted web":"526c81","Steel weathering":"647885"}


def endplate(m,h,u,side,v):
    # Small folded inspection hatch at the deep end of each proper steel box.
    # Real fasteners and a narrower relief face, not a painted broad stripe.
    m.box("Gasketed inspection hatch","Cover panel",
          *sorted((u,u+side*.012)),v-.115,v+.115,
          lambda q:h(q)-.333,lambda q:h(q)-.144,
          face_colors={"under":"Box interior","top":"Box steel bright"})
    for a in (v-.085,v+.085):
        for off in (-.298,-.179):
            geometry.rivet(m,"Hatch bolt heads",side,u+side*.013,a,h(a)+off,.009)


def deck(m,h,head,mode):
    width=.482 if mode=="road" else .546
    if mode=="road":
        kit.running_surface(m,h)
    else:
        rail.full_track(m,h,"full" if head else None,guards="head" if head else "span")
    m.box("Continuous deck diaphragm","Deck aggregate",-width,width,-1,1,
          lambda v:h(v)-.096,lambda v:h(v)-.006,end_faces=False,
          face_colors={"under":"Box steel under"})
    for side in (-1,1):
        a,b=sorted((side*(width-.122),side*(width-.016)))
        m.box("Twin closed welded box sections","Box steel mid",a,b,-1,1,
              lambda v:h(v)-.415,lambda v:h(v)-.088,end_faces=False,
              face_colors={"under":"Box steel under","left":"Box steel bright"})
        for lo,hi,w,color in ((-.437,-.408,.026,"Box steel bright"),(-.108,-.077,.024,"Workshop blue")):
            m.box("Continuous flange overhang","Box steel bright",a-w,b+w,-1,1,
                  lambda v,k=lo:h(v)+k,lambda v,k=hi:h(v)+k,end_faces=False,
                  face_colors={"under":"Box steel under","top":color})
        outside=side*(width-.016)
        for v in (-.73,.73):
            endplate(m,h,outside,side,v)
        for v in (-.38,.38):
            m.box("Box support seam","Weld seam",*sorted((outside,outside+side*.006)),v-.006,v+.007,
                  lambda q:h(q)-.400,lambda q:h(q)-.118)
        rail_side=side*(width-.062)
        start=-.80 if head else -1.
        for low,high,color in ((.078,.103,"Box steel mid"),(.196,.231,"Handrail")):
            m.box("Continuous guarded walkway barrier",color,rail_side-.019,rail_side+.019,start,1,
                  lambda v,k=low:h(v)+k,lambda v,k=high:h(v)+k,end_faces=False)
        for v in (-.70,-.23,.24,.71):
            m.box("Pressed steel handrail uprights","Box steel mid",rail_side-.026,rail_side+.026,v-.017,v+.017,
                  lambda q:h(q)-.018,lambda q:h(q)+.223)
        if head:
            m.box("Approach bearing cheeks","Hardened concrete",*sorted((side*.33,side*width)),-.65,.46,
                  lambda q:h(q)-.58,lambda q:h(q)-.437)
            m.box("Approach night marker","Reflector",rail_side-.017,rail_side+.017,-.742,-.708,
                  lambda q:h(q)+.202,lambda q:h(q)+.296)
    if not head:
        m.box("Fast girder crosshead","Hardened concrete",-.515,.515,-.176,.176,-.085,.063)
        for u in (-.36,.36):
            m.box("Elastomeric bearing bank","Elastomer",u-.071,u+.071,-.113,.113,.061,.089)
        section=geometry.bevel_footprint(.45,.34,.050)
        narrow=geometry.bevel_footprint(.32,.28,.042)
        geometry.prism(m,"Pier throat","Cast concrete face",narrow,section,-.50,-.083,under=False)


def pier():
    m=kit.Mesh()
    footprint=geometry.bevel_footprint(.32,.28,.042)
    geometry.prism(m,"Deep pier core","Cast concrete face",footprint,footprint,-.5,.5,under=False,above=False)
    lip=geometry.bevel_footprint(.336,.297,.044)
    for y in (-.28,.22):
        geometry.prism(m,"Shallow cast course","Base patina",lip,lip,y,y+.034)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | High-speed welded girder over two spans"
    kit.COLORS=COLORS
    mats=kit.materials()
    showcase={}
    for mode in ("road","rail"):
        stem=f"{mode}_bridge_fast_girder"
        kit.PREFIX="bl_"+stem
        parts={}
        for variant,height in (("span",lambda v:.5),
                               ("head_flat",lambda v:.5),
                               ("head_ramp",lambda v:v/2)):
            shape=kit.Mesh()
            if mode=="rail" and variant=="head_flat":
                rail.descending_land(shape)
            deck(shape,height,variant!="span",mode)
            orientations=((0,2),(1,1)) if variant=="span" else enumerate(range(4))
            for axis,dir in orientations:
                parts[f"{variant}_{axis}"]=shape.oriented(dir)
        shape=pier()
        for axis,dir in ((0,2),(1,1)): parts[f"pier_{axis}"]=shape.oriented(dir)
        kit.atlas()
        for name,shape in parts.items():
            kit.export(name,shape)
            source=kit.author(shape,mode.capitalize()+" "+name,mats)
            if mode=="road": showcase[name]=source
        for axis in (0,1):
            name=kit.MODELS/f"{kit.PREFIX}_span_{axis}.obj"
            name.with_name(name.stem+"_road_clear.obj").write_text(clear_span(name,BEARINGS))
            for depth in (1,2,"water"):
                write_feet(stem,"Deep_pier_core",axis,depth)
    kit.showcase(showcase)
    scene=bpy.context.scene
    # ID #9 has at most two middle tiles. Show one full two-tile example.
    for ob in list(scene.objects):
        if ob.instance_type=="COLLECTION":
            if abs(ob.location.x)<.01:
                bpy.data.objects.remove(ob,do_unlink=True)
            else:
                ob.location.x+=-1 if ob.location.x>0 else 1
        elif ob.name=="Upper bank": ob.location.x-=1
        elif ob.name=="Lower bank": ob.location.x+=1
    camera=scene.camera
    camera.data.ortho_scale=10.8
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/"art"/"fast_girder.blend"),compress=True)


if __name__=="__main__":
    main()
