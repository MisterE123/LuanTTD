#!/usr/bin/env python3
"""Original OpenTTD 16.0-RC1 Temperate residential parcels and street block.

Run with Blender 4.x. RESIDENTIAL_LOOKS='06:0 06:2' limits separate meshes;
RESIDENTIAL_REVIEW=/path produces individual three-quarter JPEGs.
"""
from dataclasses import dataclass
from math import cos,pi,sin
from pathlib import Path
from random import Random
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_town_art as art
from build_scenery_art import ROOT,beam,box,bulbs,chimney,frontdoor,gable,hip,init,mesh,pane,tapered


@dataclass(frozen=True)
class Dwelling:
    name:str
    w:float
    d:float
    h:float
    rise:float
    body:str
    roof:str
    plan:str
    yard:str
    source:int

# The stock stage-3 sprite table contains two looks for #06, four each for
# #18/#1A, and one each for #19/#0E. One independently arranged parcel per
# actual source silhouette; offset/winding must remain compatible with
# the renderer's native +Z roadside front.
BLUEPRINTS={
 (0x06,0):Dwelling("town_houses_brick",.99,.81,.700,.460,"brick","soil","recessed_gabled_terrace","wall",1446),
 (0x06,2):Dwelling("town_houses_hipped_pair",1.10,.76,.530,.302,"plaster","slate","stucco_bungalow_wing","picket",1506),
 (0x18,0):Dwelling("old_houses_red_brick",1.05,.77,.615,.472,"brick","terracotta","side_workshop","hedge",1492),
 (0x18,1):Dwelling("old_houses_limestone",.91,.839,.611,.362,"warm limestone","soil","tight_single_house","open",1494),
 (0x18,2):Dwelling("old_houses_clay_tile",.88,.89,.765,.426,"brick bright","terracotta","tall_sash_cottage","picket",1488),
 (0x18,3):Dwelling("old_houses_masonry",.85,.89,.702,.372,"stone","terracotta","lean_to_end_house","hedge",1490),
 (0x19,0):Dwelling("cottages_sandstone",.91,.82,.722,.433,"pale stone","trail","sandstone_entrance","picket",1496),
 (0x1A,0):Dwelling("houses_gold_cross_roof",1.08,.82,.665,.483,"brick","straw","gold_tiled_front_ell","hedge",1500),
 (0x1A,1):Dwelling("houses_slate_hip",1.12,.80,.736,.405,"brick bright","slate","hipped_home_and_utility","hedge",1575),
 (0x1A,2):Dwelling("houses_red_gable",1.06,.85,.688,.433,"brick","terracotta","twin_heights_and_porch","open",1512),
 (0x1A,3):Dwelling("houses_ochre_gable",1.05,.82,.648,.457,"brick bright","soil","entry_wing_and_window","hedge",1518),
}

def roof(tag,shape,x,y,w,d,eave,peak,wall,roof_tone,trim="cream",gold=False):
    if shape=="hip":
        hip(tag,x,y,w,d,eave,peak,roof_tone)
        return
    if roof_tone in ("straw","soil","trail"):
        # Export physical warm roofs without inventing a second atlas.
        a,b=w/2,d/2
        for sign in (-1,1):
            vs=[(x-a,y+sign*b,eave),(x+a,y+sign*b,eave),(x,y+sign*b,peak)]
            mesh(tag+" brick gable end",vs,((0,1,2),) if sign==-1 else ((0,2,1),),wall)
        a,b=a+.044,b+.052
        ridge="gold" if roof_tone=="straw" else "trail" if roof_tone=="soil" else "warm limestone"
        for sign in (-1,1):
            vs=[(x,y-b,peak+.027),(x+sign*a,y-b,eave),
                (x+sign*a,y+b,eave),(x,y+b,peak+.027)]
            mesh(tag+" pitched warm roof",vs,((0,1,2,3),) if sign==1 else ((3,2,1,0),),roof_tone)
            for edge in (-1,1):
                beam(tag+" rake",(x,y+edge*b,peak+.016),(x+sign*a,y+edge*b,eave-.006),.022,.024,trim)
            box(tag+" eave",(x+sign*a,y,eave-.013),(.027,b*2,.034),trim)
            if not gold:
                for i in range(1,9):
                    f=i/9
                    box(tag+" brown clay course",(x+sign*a*f,y,(1-f)*(peak+.027)+f*eave+.003),
                    (.018,b*2,.006),ridge)
        if not gold:box(tag+" warm ridge cap",(x,y,peak+.032),(.055,b*2,.021),ridge)
    else:
        gable(tag,x,y,w,d,eave,peak,wall,roof_tone,trim,7)
    if gold:
        # Physical warm weathered overlapping clay courses along the roof,
        # not a uniform facade repaint or raster decal.
        a=w/2+.044;b=d/2+.048
        for side in (-1,1):
            for i in range(1,12):
                t=i/12
                xx=x+side*a*t
                hh=(1-t)*(peak+.027)+t*eave+.004
                box(tag+" ochre rainbreak tile course",(xx,y,hh),(.017,2*b,.008),
                    ("wheat","trail","warm limestone","straw")[i%4])
        box(tag+" fired golden ridge cap",(x,y,peak+.043),(.062,2*b,.019),"wheat")
    for side in (-1,1):
        xx=x+side*(w/2+.038)
        yy=y-d/2-.044
        beam(tag+" round rain gutter",(xx,yy,eave-.024),(xx,y+d/2+.039,eave-.012),
             .022,.021,"slate")
        for segment in (
                ((xx,yy+.016,eave-.023),(xx,yy+.016,eave-.090)),
                ((xx,yy+.016,eave-.090),(xx-side*.044,yy+.054,eave-.118)),
                ((xx-side*.044,yy+.054,eave-.118),(xx-side*.044,yy+.054,.12))):
            beam(tag+" independent bent rainwater downpipe",*segment,.017,.018,"metal")

def fence(y,x0,x1,axis=False):
    def pos(u,v):return (v,u) if axis else (u,v)
    for h in (.105,.175):
        x,z=pos((x0+x1)/2,y)
        box("True open picket fence horizontal rails",(x,z,h),
            (.023,x1-x0+.023,.029) if axis else (x1-x0+.023,.023,.029),"cedar")
    for i in range(round((x1-x0)/.085)+1):
        xx=x0+i*(x1-x0)/round((x1-x0)/.085)
        x,z=pos(xx,y)
        box("Individual squared timber garden picket",(x,z,.155),(.026,.030,.230),"sapwood")
        tapered("Picket shaped pointed end",(x,z,.256),(x,z,.292),.020,.003,4,"cedar")

def garden(spec,row):
    rng=Random(row+188901)
    box("Entire level grassy freehold plot",(0,0,.022),(1.882,1.882,.044),"sage")
    box("Mown central lawn",(0,.177,.045),(1.730,1.30,.006),"mint")
    if spec.yard=="picket":
        fence(.842,-.855,.865)
        fence(-.854,-.770,.835,axis=True)
    elif spec.yard=="hedge":
        for x,y,w,d in ((-.835,.199,.108,1.37),(.835,.182,.112,1.39),(0,.842,1.698,.119)):
            box("Clipped boundary hedge with foliage core",(x,y,.128),(w,d,.178),"hedge")
            for j in range(7):
                f=(j+.5)/7-.5
                box("Uneven separately clipped upper hedge leaf blocks",(x+w*f*.91,y+d*f*.86,.225+rng.uniform(-.016,.018)),
                    (.11 if d>w else .22,.22 if d>w else .11,.069),("foliage","foliage sun","mint")[j%3])
    elif spec.yard=="wall":
        for x in (-.846,.846):
            box("Original low garden brick party wall",(x,.277,.150),(.102,1.16,.217),"brick")
            box("Individual coping slab along garden wall",(x,.277,.269),(.121,1.179,.034),"warm limestone")
            for j in range(13):
                box("Offset mortar seam detail in side garden wall",(x,.262+(j-6)*.077,.169),
                   (.106,.008,.116),"brick bright")
    else:
        for x in (-.833,.833):
            for j in range(7):
                box("Set low rounded stone boundary feet defining open lawn",(x,-.01+j*.122,.095),(.068,.106,.085),
                    "warm limestone" if j%3 else "pale stone")
    for a in (-1,1):
        if spec.plan not in ("stucco_bungalow_wing",):
            box("Dressed near-street flower-bed curb",(a*.648,-.605,.082),(.283,.439,.069),"warm limestone")
            box("Stripped soil under flowering groundcover",(a*.648,-.605,.118),(.248,.392,.010),"soil")
            for j in range(2):
                bulbs(a*(.632+rng.random()*.050),-.704+j*.191,rng)
        else:
            for j in range(3):
                art.tree(a*(.710+.022*(j%2)),.328+j*.193,.259+rng.random()*.10)
    # An actual rear bed and gravel/leather utility court detach from the facade.
    xx=.594 if row%2 else -.580
    box("Rear gravel utility pad",(xx,.627,.054),(.316,.274,.018),"trail")
    for j in (-1,0,1):
        box("Rear court masonry single setts",(xx+j*.093,.627,.070),(.087,.209,.018),"pale stone")

def walls(tag,x,y,w,d,height,c,base=.067):
    box(tag+" dressed stone bed",(x,y,base/2+.034),(w+.035,d+.043,base-.010),"warm limestone")
    box(tag+" enclosed building wall",(x,y,base+height/2),(w,d,height),c)
    # Narrow separate lower facade brickwork at every real boundary; not
    # a script-emitted pile of source sprites.
    front=y-d/2
    for sign in (-1,1):
        for j in range(4):
            h=base+.037+j*min(.084,height*.16)
            box(tag+" hand-mortared corner alternation",(x+sign*(w/2-.038),front-.009,h),
                (.078 if j%2 else .110,.030,.029),"warm limestone" if c in ("stone","pale stone") else "brick bright" if c.startswith("brick") else "pale stone")
    box(tag+" down-splash plinth",(x,front-.010,base+.033),(w+.018,.036,.051),"stone")

def windows(spec,r,x,y,f,back):
    w,h=spec.w,spec.h; c=spec.body
    side=[(x-w/2,"left"),(x+w/2,"right")]
    if spec.plan in ("recessed_gabled_terrace","tall_sash_cottage","sandstone_entrance"):
        for s in (-1,1):
            pane("Upper separate paired sash with casing",x+s*w*.235,f,.530+h*.045,w*.17,.171,
                 f="pale stone",divisions=2)
        pane("Upper chamfered attic light",x,f,.820,.139,.118,f="cream",divisions=2)
    elif spec.plan!="stucco_bungalow_wing":
        for s in (-1,1):
            pane("Recessed upper warm facade casement",x+s*w*.23,f,.506+h*.064,w*.185,.142,
                 f="warm limestone" if c in ("stone","pale stone") else "cream",divisions=2)
    for u,q in side:
        pane("Side elevation raised head window",u,y+.058,.448 if h<.68 else .522,.144,.164,q,"pale stone",
             shutters=spec.plan in ("lean_to_end_house","tight_single_house"))
        if h>=.65:
            pane("Open-shadow stone attic end light",u,y+.240,.620,.113,.103,q,"cream")
    for off in (-.238,.219):
        pane("Private rear service window",x+off,back,.403,.121,.150,"back","pale stone")
    if c.startswith("brick"):
        box("True projecting building frontage first-floor brick string moulding",(x,f-.021,.461),(w+.021,.038,.024),"brick bright")
    else:
        box("Dressed stone full width window aprons",(x,f-.014,.402),(w+.021,.039,.027),"warm limestone")

def door_and_walk(x,y):
    frontdoor(x,y-.022,.248,"plaster",floor=.082)
    box("Front garden stepping walk joins road-facing end",
        (x,(y-.070-.898)/2,.052),(.209,y-.070+.898,.020),"trail")
    n=max(2,round((y+.800)/.114))
    for j in range(n):
        q=-.868+(j+.5)*(y+.80)/n
        box("Separately laid front approach cobbles",(x,q,.065),(.159,(y+.80)/n-.009,.013),"pale stone")
    box("Upper single cut dress entrance step",(x,y-.106,.078),(.230,.169,.038),"stone")
    box("Separated low iron-free road-edge threshold",(x,-.903,.066),(.218,.050,.035),"pale stone")

def ext(tag,x,y,w,d,h,rise,c,r,shape,door=False):
    walls(tag,x,y,w,d,h,c)
    roof(tag+" low roof",shape,x,y,w,d,h+.067,h+.067+rise,c,r,
         gold=tag.startswith("L-plan gold"))
    front=y-d/2
    if door:frontdoor(x,front-.013,.185,c,floor=.072)
    else:pane(tag+" small four-light casement",x,front,.277,w*.46,.147,f="pale stone",divisions=2)
    pane(tag+" narrow utility side window",x+w/2,y+.055,.234,.095,.102,"right","cream")

def residential(spec,row,landscaped=True):
    if landscaped: garden(spec,row)
    x,y=.015,.110
    if spec.plan in ("stucco_bungalow_wing","gold_tiled_front_ell","hipped_home_and_utility","twin_heights_and_porch","entry_wing_and_window"):
        x,y=-.123,.168
    if spec.plan in ("side_workshop","lean_to_end_house"):
        x=-.101
    w,d,h,r=spec.w,spec.d,spec.h,spec.rise
    front,back=y-d/2,y+d/2
    walls(spec.name,x,y,w,d,h,spec.body)
    sh="hip" if spec.plan in ("stucco_bungalow_wing","hipped_home_and_utility") else "gable"
    roof(spec.name+" primary roof",sh,x,y,w,d,h+.067,h+.067+r,spec.body,spec.roof,
         "warm limestone" if spec.body=="warm limestone" else "cream",
         gold=spec.plan=="gold_tiled_front_ell")
    windows(spec,row,x,y,front,back)
    door=x-.116
    right=x+.249
    if spec.plan=="recessed_gabled_terrace":
        ext("Tall brick end bay",x+.340,front-.068,.355,.315,.476,.233,"brick bright","shingle","gable")
        door=x-.218
    elif spec.plan=="stucco_bungalow_wing":
        ext("Side stucco bungalow wing",x+.594,front+.132,.391,.660,.459,.229,"plaster","slate","hip")
        door=x-.255
    elif spec.plan=="side_workshop":
        ext("Original gardener masonry side workroom",x+.508,front+.121,.394,.588,.393,.281,"brick bright","terracotta","gable")
        door=x-.205
    elif spec.plan=="tight_single_house":
        box("Old limestone entrance rain hood",(door,front-.104,.390),(.270,.221,.081),"terracotta")
        pane("Tall side-stacked limestone cottage window",right,front,.284,.154,.217,f="cream",shutters=True)
    elif spec.plan=="tall_sash_cottage":
        ext("Tall narrow rear washhouse wing",x+.415,back-.080,.314,.342,.490,.256,"brick","terracotta","gable")
        door=x-.221
        pane("Tall clay-panel parlor sash",right,front,.298,.171,.198,f="cream")
    elif spec.plan=="lean_to_end_house":
        ext("Stone cottage lower tiled utility wing",x+.488,front+.074,.364,.496,.301,.154,"stone","terracotta","gable",True)
        door=x-.227
    elif spec.plan=="sandstone_entrance":
        ext("Small longitudinal roof over cottage canted bay",x+.243,front-.101,.334,.248,.433,.198,"cream board","trail","gable")
        door=x-.227
        for yy in (front-.046,front-.094):
            box("Sandstone cottage hand-cut small flower platform",(door-.172,yy,.142),
                (.103,.143,.143),"pale stone")
    elif spec.plan=="gold_tiled_front_ell":
        ext("L-plan gold secondary roof",x+.528,front+.008,.437,.517,.419,.288,"brick bright","straw","gable")
        door=x-.204
    elif spec.plan=="hipped_home_and_utility":
        ext("Raised grey service wing hipped seam",x+.541,front+.027,.442,.536,.441,.233,"brick","slate","hip")
        door=x-.247
    elif spec.plan=="twin_heights_and_porch":
        ext("Forward small red-brick tripart porch",x+.494,front+.023,.442,.525,.502,.344,"brick bright","terracotta","gable")
        door=x-.192
    elif spec.plan=="entry_wing_and_window":
        ext("Side entry terracotta yard branch",x+.563,front+.050,.384,.565,.415,.229,"brick","soil","gable")
        door=x-.208
    if spec.plan not in ("tight_single_house","tall_sash_cottage"):
        pane("Ground floor paired front parlor window",max(x+.069,door+.267),front,.282,.155,.175,
             f="cream",divisions=2)
    if landscaped: door_and_walk(door,front)
    else:frontdoor(door,front-.022,.248,"plaster",floor=.082)
    c="warm limestone" if spec.body in ("stone","pale stone","plaster","warm limestone") else "brick"
    if spec.plan=="stucco_bungalow_wing":chimney(x-.300,y+.178,h+.205,.227,c)
    else:chimney(x-.175,y+.177,h+.244+r*.37,.229,c)

def office(landscaped=True):
    # 1463 has a dense stone-and-brick commercial frontage with two dark
    # upper masses. No existing shop is recolored or reused.
    if landscaped:
        box("Mixed-use paved curb and concrete parcel foundation",(0,0,.020),(1.900,1.900,.040),"stone")
        for i in range(9):
            art.walk((i-4)*.193,-.790,.180,.257)
    front=-.562; back=.644
    x0,x1=-.730,.699
    roof0=1.615; floor=.421
    box("Five-floor red brick perimeter shell",(0,.041,.824),(1.455,1.210,1.532),"brick")
    box("Full-width tan Bedford block base at pedestrian height",(0,-.527,.252),(1.481,.170,.425),"warm limestone")
    box("Stepped dark rooftop masonry coping",(0,.041,1.615),(1.523,1.262,.113),"burgundy")
    for z in (.365,.661,.944,1.210,1.473,1.631):
        for side in (-1,1):
            box("Pale stone sash row belt course wrapping front or back",(0,front if side<0 else back,z),(1.524,.048,.024),"warm limestone")
            box("Molded stone side wall lintel reveal continued around corner",
                (x0 if side<0 else x1,.043,z),(.052,1.230,.025),"warm limestone")
    for col,x in enumerate((-.572,-.337,-.104,.129,.363,.592)):
        for y,t in ((front,"front"),(back,"back")):
            for z in (.528,.796,1.062,1.337,1.509):
                pane("Original stacked brick office grid sash",x,y,z,.163,.148 if z<1.45 else .120,t,"cream",divisions=2)
            box("Facade vertical pier under separately laid brick courses",(x-.112,y,.961),
                (.041,.059,1.136),"brick bright")
        center=(col-2.5)*.188
        for side in (-1,1):
            pane("Low masonry side repeated commercial office side casement",
                x0 if side<0 else x1,.045+center,.791,.131,.164,
                "left" if side<0 else "right","pale stone",divisions=2)
            for z in (1.055,1.325,1.522):
                pane("Glazed side occupied sash behind pilaster breaks",
                  x0 if side<0 else x1,.045+center,z,.124,.114,
                  "left" if side<0 else "right","warm limestone",divisions=2)
    for x in (-.430,.452):
        pane("Wide actual street show window at period shop floor",x,front-.051,.233,.376,.225,f="teal",divisions=3)
        box("Stone shop sash thick display apron",(x,front-.058,.083),(.383,.072,.089),"brick")
        box("Painted dark shop fascia",(x,front-.064,.426),(.450,.051,.088),"slate")
        for j in range(6):
            u=x+(j-2.5)*.052
            box("Original unlettered brass shop fascia marks",(u,front-.096,.426),(.038,.017,.014*(1+j%2)),"gold")
    # Central stone street entrance is a physical three-leaf staff doorway.
    frontdoor(.011,front-.034,.259,"plaster",floor=.070)
    box("Broad ground floor stone lintel over paired shops",(0,front-.081,.356),(1.421,.062,.048),"pale stone")
    for side in (-1,1):
        z=roof0+.112
        xx=side*.389
        box("Distinct raised office roof shoulder",(xx,.072,z),(.684,1.149,.189),"brick")
        for q in (-1,1):
            box("Cold slate pitched parapet ridge edge",(xx+q*.291,.074,z+.116),(.055,1.199,.050),"slate bright")
        for i in range(8):
            box("Rolled separate dark top roof standing seams",
                (xx+(i-3.5)*.076,.075,z+.095),(.068,1.052,.022),
                "slate" if i%3 else "slate bright")
        for j in (-1,1):
            box("Dressed charcoal tall narrow rooftop riser pipes",(xx+side*.180,.385+j*.138,z+.166),
                (.064,.074,.101),"warm limestone")
    box("Narrow low-service glazed roof light in central valley",(0,.149,1.717),(.137,.321,.130),"glazing")
    for y in (-.03,.082,.199,.310):
        box("Four bright skylight independent glazing stops",(0,y,1.785),(.151,.019,.021),"light metal")
    if landscaped:
        art.lamp(.839,-.729)
        art.bench(-.370,.783)

def scene_name(id,variant,spec):
    if id==0x0E:return "shops_and_offices_brick"
    return spec.name

def publish(id,variant,spec):
    init()
    tag=scene_name(id,variant,spec)
    scene=bpy.context.scene
    scene.name=f"LuanTTD | RC1 #{id:02X} look {variant} | {tag.replace('_',' ')}"
    scene["source_frame"]=1463 if id==0x0E else spec.source
    scene["source_art"]="OpenGFX 7.1 outline studied privately; original geometry/surfaces."
    if id==0x0E:office()
    else:residential(spec,(id<<4)+variant)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active
                v.shading.color_type="MATERIAL";v.region_3d.view_location=Vector((0,0,.58))
                v.region_3d.view_rotation=Vector((.81,-.89,.67)).to_track_quat("Z","Y")
                v.region_3d.view_distance=3.9 if id==0x0E else 3.4
    # Suffix non-zero alterative blend filenames before the descriptive
    # segment so the standard one-default-source check remains meaningful.
    name=f"town_stock_{id:02x}"+(f"v{variant}" if variant else "")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{name}_{tag}.blend"),compress=True)
    if not os.getenv("RESIDENTIAL_REVIEW_ONLY"):
        ob=art.join_into_native()
        art.export_obj(ob,f"town_stock_{id:02x}"+(f"_{variant}" if variant else ""))
    if path:=os.getenv("RESIDENTIAL_REVIEW"):
        # Restart shape rather than attempting to modify any joined export;
        # saved .blend and restarts both retain separable editable objects.
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/"art"/f"{name}_{tag}.blend"))
        sc=bpy.context.scene
        from build_scenery_art import MATS
        # Factory material dictionary objects become invalid after reload.
        MATS.clear();MATS.update({q.name:q for q in bpy.data.materials})
        box("Review ground",(0,0,-.068),(10,10,.135),"stone")
        bpy.ops.object.camera_add(location=(3.13,-4.04,2.93 if id!=0x0E else 3.77))
        cam=bpy.context.object;cam.data.type="ORTHO";cam.data.ortho_scale=2.98 if id!=0x0E else 3.57
        cam.rotation_euler=(Vector((0,0,.53 if id!=0x0E else .87))-cam.location).to_track_quat("-Z","Y").to_euler()
        sc.camera=cam;sc.render.engine="BLENDER_WORKBENCH"
        sc.render.resolution_x,sc.render.resolution_y=840,620
        sc.render.resolution_percentage=100
        sh=sc.display.shading;sh.light="STUDIO";sh.color_type="MATERIAL"
        sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type="BOTH"
        sh.background_type="WORLD"
        sc.world=bpy.data.worlds.new("Quiet rural gray")
        sc.world.color=(.17,.21,.25)
        sc.view_settings.view_transform="Standard";sc.view_settings.exposure=.30
        sc.render.image_settings.file_format="JPEG";sc.render.image_settings.quality=92
        sc.render.filepath=str(Path(path)/f"{name}_{tag}.jpg")
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    select=set(os.getenv("RESIDENTIAL_LOOKS","").split())
    for (id,v),s in sorted({**BLUEPRINTS,(0x0E,0):None}.items()):
        if not select or f"{id:02x}:{v}" in select:publish(id,v,s)
