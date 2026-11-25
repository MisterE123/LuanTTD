#!/usr/bin/env python3
"""Original 3D site scenes for the pinned RC1 Temperate house draw rows.

LUA=/path/to/lua5.1 blender -b -t 2 --python-exit-code 1 --python \
  tools/build_stock_construction_art.py

TOWN_SITE_FILTER=regular-expression limits scene builds; TOWN_SITE_REVIEW
sets an optional directory for assembled three-quarter proof pictures.
"""
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from random import Random
from subprocess import check_output
import os
import re
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_town_art as town
import build_stock_residential_art as residential
from build_scenery_art import ROOT, beam, box, init, mesh, tapered


@dataclass(frozen=True)
class Mass:
    """On-site footprint in editable Blender X,Y, front -Y."""
    x:float
    y:float
    w:float
    d:float
    h:float
    color:str
    bays:int=4
    floors:int=3


@dataclass(frozen=True)
class Phase:
    name:str
    root:int
    slot:int
    stage:int
    ground:int
    upper:int
    look:int


def source_scenes()->Iterator[Phase]:
    lua=os.environ.get("LUA","lua5.1")
    data=check_output([lua,"tools/list_town_construction_art.lua"], cwd=ROOT,text=True)
    for line in data.splitlines():
        name,*vals=line.split()
        yield Phase(name,*(int(i) for i in vals))


# The footprint remains that of each site's mature original model.
# Compound shells use several physically adjoining structures, not
# a recoloured generic stage. Heights are in native Luanti nodes.
OFFICES={
 0x00:(Mass(0,.10,1.36,1.28,2.51,"stone",5,7),),
 0x01:(Mass(0,.10,1.38,1.24,1.44,"brick",5,4),),
 0x02:(Mass(0,.10,1.37,1.12,1.46,"warm limestone",4,4),),
 0x04:(Mass(0,.10,1.49,1.32,2.05,"stone",6,6),),
 0x0d:(Mass(0,.10,1.49,1.33,1.72,"brick",5,4),),
 0x0e:(Mass(-.352,.042,.683,1.229,1.66,"brick",4,5),
        Mass(.352,.042,.683,1.229,1.54,"brick bright",4,5)),
 0x0f:(Mass(-.46,.078,.59,1.35,1.10,"brick",3,3),
        Mass(.295,.078,.9,1.35,1.38,"stone",4,5)),
 0x10:(Mass(-.46,.078,.59,1.35,1.13,"warm limestone",3,4),
        Mass(.295,.078,.90,1.35,1.51,"brick",4,5)),
 0x13:(Mass(-.374,.101,.733,1.34,1.36,"warm limestone",4,4),
        Mass(.337,.136,.75,1.23,1.60,"brick",4,5)),
 0x1b:(Mass(0,.104,1.39,1.31,1.48,"brick",5,4),
        Mass(.48,.717,.53,.24,.92,"brick bright",2,2)),
 0x1c:(Mass(0,.099,1.34,1.27,2.25,"stone",5,7),),
 0x1e:(Mass(0,.085,1.47,1.37,1.52,"warm limestone",6,5),),
}
PLOT_STONE={1530,1532,1540,1542,1546,1548,1562}
PLOT_PARTIAL_SOD={1498,1503,1509,1515,1520,1526,1572}


def grounds(p):
    if p.name=="town_site_paved" or p.ground in PLOT_STONE:
        box("Poured or paved reserved civic lot",(0,0,.017),(1.890,1.890,.034),"stone")
        for j in range(11):
            for k in range(10):
                xx=-.859+k*.166+(j%2)*.071
                yy=-.860+j*.171
                box("Offset stone setts on actual stock-paved site",(xx,yy,.035),
                  (.153,.152,.008),("warm limestone","stone","pale stone","metal")[(j+5*k)%4])
        return
    sod=p.ground in PLOT_PARTIAL_SOD
    box("Level exposed stock house lot",(0,0,.016),(1.895,1.895,.032),"sage" if sod else "soil")
    rng=Random((p.ground+501)*51+p.upper)
    y=.092
    if sod:
        # A future house footprint is dug out but the grass and verge
        # on this source phase have already reached the plot boundary.
        q=((-.69,-.55),(.63,-.52),(.735,-.253),(.701,.637),(.481,.766),
           (-.568,.716),(-.693,.567),(-.747,-.312))
        mesh("Uneven excavated hole inside grassy stock plot",[(x,z,.0334) for x,z in q],
             (tuple(range(8)),),"soil shade")
        mesh("Freshly cut ochre soil along one edge",
             [(-.749,-.31,.034),(-.693,-.541,.034),(-.596,-.54,.034),
              (-.622,-.303,.034),(-.594,.651,.034),(-.665,.618,.034)],
             ((0,1,2,3),(0,3,4,5)),"soil")
    count=76 if p.name=="town_site_bare" else 40
    for piece in range(count):
        x,z=rng.uniform(-.86,.86),rng.uniform(-.85,.87)
        if sod and (abs(x)>.60 or not -.50<z<.61):
            continue
        sx,sz=rng.uniform(.010,.064),rng.uniform(.009,.052)
        zz=(.0338 if sod else .0325)+piece*.000005
        mesh("Compact grit and mottled exposed earth",
             ((x-sx,z,zz),(x,z-sz,zz),(x+sx,z+.013,zz),(x+.01,z+sz,zz)),((0,1,2,3),),
             rng.choice(("soil shade","soil","trail","warm limestone") if rng.randrange(5)==0 else ("soil shade","soil")))
    if p.ground>=0 and not sod:
        box("Stock excavation's rectangular recessed dark floor",(0,y,.033),(1.292,1.17,.004),"soil shade")
    if p.upper or p.ground>=0:
        for j in range(4):
            box("Unpaved construction access from the road",(-.19,-.879+j*.068,.036),
                (.224,.058,.008),"trail")


def footing(m, z=.144, *, white=False):
    w,d=m.w,m.d
    color="pale stone" if white else "warm limestone"
    box("Dark excavated recess under footing",(m.x,m.y,.049),(w+.055,d+.065,.031),"soil shade")
    for k in (-1,1):
        box("Side strip footing concrete core",(m.x+k*(w-.082)*.5,m.y,.07),
            (.083,d,.094),color)
        box("End strip footing concrete core",(m.x,m.y+k*(d-.079)*.5,.071),
            (w-.166,.081,.095),color)
        for i in range(max(3,round(d/.136))):
            n=max(3,round(d/.136))
            yy=m.y+(i+.5-n*.5)*(d-.057)/n
            box("Placed individual peripheral foundation blocks",(m.x+k*(w-.084)*.5,yy,z*.65),
                (.097,(d-.066)/n-.011,z*.69),("pale stone","stone",color)[(i+k)%3])
        for i in range(max(3,round(w/.14))):
            n=max(3,round(w/.14))
            xx=m.x+(i+.5-n*.5)*(w-.14)/n
            box("Individually laid front or back masonry blocks",(xx,m.y+k*(d-.080)*.5,z*.65),
                ((w-.15)/n-.012,.091,z*.70),("pale stone","stone",color)[(i+k)%3])
    for a in (-1,1):
        for b in (-1,1):
            box("Load path corner pilaster base",(m.x+a*(w-.091)*.5,m.y+b*(d-.091)*.5,z*.75),
                (.139,.133,z*.86),color)


def raw_access(m, p, frame=False):
    yy=m.y-m.d*.5-.065
    xs=(m.x-m.w*.5+.047,m.x+m.w*.5-.047)
    for side,x in enumerate(xs):
        for y in (yy,min(.896,m.y+m.d*.5+.068)):
            box("Unpainted survey stake at slab edge",(x,y,.106),(.022,.024,.153),"cedar")
    beam("Visible temporary survey line",(xs[0],yy,.118),(xs[1],yy,.118),.006,.007,"trail")
    if max(xs)<.61 and p.upper:
        x=min(.824,max(xs)+.151)
        y=min(.722,m.y+.29)
        for k in range(4):
            box("Hand stacked lengths of future siding",(x,y,.051+k*.021),
                (.078,.345,.016),"sapwood" if k%2==0 else "cedar")
    if frame:
        for i in range(6):
            box("Bundled roof tiles at front service position",(xs[1]-.087,-.723+.027*i,.055+i%2*.011),
                (.127,.024,.024),"terracotta" if i<4 else "terracotta bright")


def home_masses(p):
    spec=residential.BLUEPRINTS.get((p.root,p.look))
    if spec is None:
        raise AssertionError("Missing residential construction references")
    x,y=.015,.110
    if p.root==0x1a or p.look==2:
        x,y=-.123,.168
    main=Mass(x,y,spec.w,spec.d,spec.h+.067,spec.body,6,2)
    wing=None
    if spec.plan=="recessed_gabled_terrace":
        wing=Mass(x+.340,y-spec.d*.5-.068,.355,.315,.54,"brick bright",3,2)
    elif p.root==0x06:
        wing=Mass(x+.594,y-spec.d*.5+.132,.391,.660,.526,"plaster",3,2)
    elif p.look==0:
        wing=Mass(x+.528,y-spec.d*.5+.008,.437,.517,.486,"brick bright",3,2)
    elif p.look==1:
        wing=Mass(x+.541,y-spec.d*.5+.027,.442,.536,.51,"brick",3,2)
    elif p.look==2:
        wing=Mass(x+.494,y-spec.d*.5+.023,.442,.525,.569,"brick bright",3,2)
    elif p.look==3:
        wing=Mass(x+.563,y-spec.d*.5+.050,.384,.565,.48,"brick",3,2)
    return (main,wing)


def cut_wall(x,y,w,d,start,end,c, name="Brick gable-stage side wall"):
    if end>start:
        box(name,(x,y,(start+end)*.5),(w,d,end-start),c)


def cottage(p):
    main,wing=home_masses(p)
    if p.upper==0:
        # The golden house's first two images have no raised building.
        # On its second site only a partly completed low outline and
        # the surrounding verge are visible, not a cottage shell.
        if p.stage==1:
            footing(main,.091)
            if wing:
                footing(wing,.087)
        return
    for i,m in enumerate(q for q in (main,wing) if q):
        footing(m,.122 if p.stage==0 else .155)
        if p.stage==0:
            if i==0:raw_access(m,p,False)
            continue
        w,d,x,y=m.w,m.d,m.x,m.y
        e=m.h
        xl,xr=x-w/2+.029,x+w/2-.029
        yf,yb=y-d/2+.027,y+d/2-.027
        roofstyle= "hip" if p.look in (1,2) and (p.root==0x06 or p.look==1) else "gable"
        if p.upper==1504:
            # Stock alternate only advances to uninterrupted low block
            # walls at stage 1, with no detached finished timber gable.
            cut_wall(xl,y,.093,d,.102,.36,m.color,"Low laid side masonry")
            cut_wall(xr,y,.093,d,.102,.36,m.color,"Low laid side masonry")
            cut_wall(x,yb,w,.093,.102,.305,m.color,"Low rear masonry")
            cut_wall(x-w*.27,yf,w*.465,.092,.102,.278,m.color,"Low front masonry beside opening")
            cut_wall(x+w*.33,yf,w*.29,.092,.102,.286,m.color,"Low front masonry beside opening")
            continue
        # Front remains intentionally unfinished, with open temporary
        # window and door bays made from separate beams instead of panes.
        brick=p.upper in (1445,1510,1573)
        tone=m.color if brick else "sapwood"
        for side,xs in enumerate((xl,xr)):
            low=.154+(.061 if side==1 else .0)
            for j in range(m.bays):
                z=y+(j+.5-m.bays*.5)*(d-.09)/m.bays
                cut_wall(xs,z,.046,(d-.10)/m.bays-.016,.192,
                         e*(.36+((j+side)%3)*.161),tone,"Incomplete masonry or timber infill bay")
            for a in range(m.bays+1):
                z=yf+a*(yb-yf)/m.bays
                beam("Standing wall upright at expected building footprint",
                     (xs,z,low),(xs,z,e),.036,.043,"cedar")
            beam("Top bearing beam",(xs,yf,e),(xs,yb,e),.056,.052,"sapwood")
            beam("Diagonal carpentry framing brace",(xs,yf+.045,.21),(xs,yb-.05,e-.032),.025,.028,"warm limestone")
        for z in (yf,yb):
            if z==yb or brick:
                cut_wall(x,z,w-.068,.052,.19,e*.46,tone,"Laid wall backing, no mature windows")
            beam("Entrance header appears before the fitted door",(xl,z,e),(xr,z,e),.043,.048,"sapwood")
            for a in range(4):
                xs=xl+(xr-xl)*a/3
                beam("Open entrance timber frame",(xs,z,.126),(xs,z,e),.036,.039,"cedar")
        ridge=e+(.21 if i else .385)
        for k in range(5):
            a=k/4
            z=yf+(yb-yf)*a
            peak=(ridge if roofstyle=="gable" else ridge-.155*abs(2*a-1))
            for xs in (xl,xr):
                beam("Exposed upper roof timber before cladding",(xs,z,e),(x,z,peak),.027,.033,"sapwood")
        if i==0:
            beam("Exposed ridge plate",(x,yf-.01,ridge),(x,yb+.01,ridge),.045,.043,"cedar")
            raw_access(m,p,True)


def post(x,y,z,height,tone,foot=.07):
    cut_wall(x,y,foot,foot,z,height,tone,"Actual structural posts without installed facade")


def steel_building(p, masses):
    for i,m in enumerate(masses):
        white=m.color in ("stone","warm limestone","plaster")
        footing(m,.155,white=white)
        if p.stage==0:
            # Modern shafts or slab crowns may go up before any floors,
            # but ordinary masonry starts with a rebar-footed plot.
            if p.upper==1541:
                cut_wall(m.x,m.y,m.w-.06,m.d-.065,.112,.54,m.color,"Low masonry podium started")
            elif p.upper in (1531,1547):
                cut_wall(m.x,m.y,m.w-.12,m.d-.148,.103,.46,m.color,"Stock tall tower's existing stone podium")
            top=.54 if p.upper in (1541,1547) else .219
            for side in (-1,1):
                for k in range(m.bays+1):
                    x=m.x+(k/m.bays-.5)*(m.w-.11)
                    y=m.y+side*(m.d-.09)*.5
                    tapered("Protruding individual poured footing rebars",(x,y,.112),(x,y,top+.067+.03*(k%3)),
                           .009,.007,4,"dark metal")
            if i==0:
                raw_access(m,p)
            continue

        x,y,w,d=m.x,m.y,m.w,m.d
        base=.112
        X=(x-w*.5+.043,x+w*.5-.043)
        Y=(y-d*.5+.043,y+d*.5-.043)
        steel="dark metal" if white else "rust"
        belt="pale stone" if white else "warm limestone"
        if p.upper in (1533,1549,1543):
            cut_wall(x,y,w-.15,d-.17,.104,.404,belt,"Detailed former ground floor podium")
        for xx in X:
            for yy in Y:post(xx,yy,base,m.h,steel,.065)
        for xx in X:
            for k in range(1,m.bays):
                yy=Y[0]+(Y[1]-Y[0])*k/m.bays
                post(xx,yy,base,m.h-.028,steel,.038)
        for yy in Y:
            for k in range(1,m.bays):
                xx=X[0]+(X[1]-X[0])*k/m.bays
                post(xx,yy,base,m.h-.028,steel,.038)
        floor=(m.h-.147)/m.floors
        for j in range(1,m.floors+1):
            height=base+j*floor
            if p.upper not in (1533,1462,1465,1468,1477) or j<=m.floors-2:
                box("Open-sided new intermediate floor deck",(x,y,height),(w-.073,d-.070,.036),belt)
            for q in X:
                beam("Exposed full-length facade beam",(q,Y[0],height),(q,Y[1],height),.051,.041,steel)
            for q in Y:
                beam("Unclad transverse I-beam",(X[0],q,height),(X[1],q,height),.047,.043,steel)
            for k in (1,2,3):
                yy=Y[0]+k*(Y[1]-Y[0])/4
                beam("Visible floor joists under empty top tiers",(X[0],yy,height),(X[1],yy,height),.029,.027,steel)
            # Stock upper construction rows show different proportions
            # of open frame and started masonry. Keep their windows
            # transparent geometric holes, never finished awnings.
            if j<=1 or (j<=m.floors-2 and not p.upper in (1533,1465)) or p.upper==1549:
                low=height-floor+.073
                ww=(X[1]-X[0])/m.bays
                for q in range(0,m.bays,2):
                    cx=X[0]+(q+.5)*ww
                    cut_wall(cx,Y[0],ww*.45,.051,low,height-.02,m.color,"Partly installed bay jamb")
                    cut_wall(cx+.50*ww,Y[0],ww*.76,.045,low,low+floor*.18,m.color,"Unfinished sill course")
                if j<=m.floors-2:
                    cut_wall(X[1],y,.050,d-.116,low,low+floor*.62,m.color,"Starter side facade bricks")
        if p.upper in (1462,1465,1477):
            for yy in Y:
                beam("Dressed eaves block on part of the front wing",(X[0],yy,m.h),(X[1],yy,m.h),.058,.055,belt)


def church(p):
    footing(Mass(0,.20,1.21,1.20,.85,"warm limestone"),.158)
    footing(Mass(0,-.477,.5,.47,1.33,"stone"),.173,white=True)
    for side in (-1,1):
        cut_wall(side*.56,.229,.094,1.09,.140,.432 if p.stage==0 else .653,
                "warm limestone","Unfinished ashlar nave elevation")
        for y in (-.071,.481):
            cut_wall(side*.62,y,.13,.12,.09,.293 if p.stage==0 else .523,
                     "pale stone","Original church buttress course")
    cut_wall(0,.777,1.067,.093,.152,.407 if p.stage==0 else .657,
             "stone","Open-backed rising masonry")
    if p.stage==1:
        for x in (-.217,.217):
            cut_wall(x,-.48,.093,.46,.167,1.16,"stone","Unfinished open bell tower sides")
        for y in (-.698,-.261):
            cut_wall(0,y,.346,.068,.153,1.111,"warm limestone","Half-height bell tower crosswall")
        for x in (-.277,.277):
            beam("Church temporary tower brace",(x,-.741,.238),(x,-.233,.895),.035,.044,"cedar")
        for y in (.048,.307,.584):
            beam("No finished roof: exposed nave collar tie",(-.55,y,.683),(.55,y,.683),.060,.061,"cedar")


def warehouse(p):
    m=Mass(.095,.19,1.49,1.30,.825,"brick")
    footing(m,.142)
    if p.stage==1:
        for side in (-1,1):
            cut_wall(m.x+side*(m.w*.5-.045),m.y,.09,m.d,.128,.744,"brick","Open industrial side wall")
        cut_wall(m.x,m.y+m.d*.5-.04,m.w-.155,.086,.128,.749,"brick","Raised stock warehouse rear wall")
        for x in (-.579,-.13,.306,.759):post(x,-.455,.144,.75,"brick bright",.104)
        beam("Loading-bay lintel with empty openings",(-.612,-.455,.735),(.794,-.455,.735),.080,.080,"warm limestone")
        for yy in (-.39,-.15,.11,.37,.64,.81):
            beam("Open steel warehouse rafter",(-.60,yy,.748),(.782,yy,.748),.035,.047,"metal")
    else:
        raw_access(m,p)


def modern(p):
    # RC1's futuristic #11 tower starts with its two concrete masts;
    # #24 instead has two yellow crane/shaft-like members before the
    # blue glazed round main building joins them at completion.
    if p.root==0x24:
        for index,(x,y,h,r) in enumerate(((-.28,.12,2.36,.052),(.24,.27,1.96,.042))):
            box("Machinery foundation and ballast",(x,y,.077),(.28,.30,.108),"stone")
            for k in range(round(h/.24)):
                a=.122+.24*k;b=min(h,a+.242)
                taper=r*(1-k*.018)
                tapered("Golden open-frame tower post segment",(x,y,a),(x,y,b),taper,taper*.96,4,"wheat")
                if k+1<h/.24:
                    box("Structural gold joining sleeve",(x,y,a+.014),(2.0*taper,2.0*taper,.022),"gold")
            tapered("Steel telescoping summit on unfinished office",
                (x,y,h-.048),(x,y,h+.039),.035,.018,5,"metal")
        return
    for x,y,h in ((-.38,.325,2.05),(.385,.418,2.19)):
        tapered("Round concrete technology tower pod footing",(x,y,.041),(x,y,.214),.126,.116,12,"stone")
        tapered("Unclad technology tower concrete column",(x,y,.196),(x,y,h),.101,.089,12,"pale stone")
        tapered("Rainproof unfinished steel mast collar",(x,y,h-.070),(x,y,h+.008),.100,.102,12,"metal")
    box("Stock visible concrete entry deck",(0,.104,.244),(1.41,1.246,.131),"pale stone")
    if p.stage==1:
        for dx,dy,z,w,d in ((-.221,.115,.57,.83,.82),(.225,.247,.86,.64,.72),(-.086,.18,1.17,.49,.62)):
            box("Separate upper modernist pod under assembly",(dx,dy,z),(w,d,.141),"plaster")
            for q in (-1,1):post(dx+q*w*.35,dy,z-.27,z+.039,"stone",.098)


def bare_shell(p):
    # Keep the geometry and materials of the editable 3D superstructure.
    # Only detached landscaping/paving are omitted for the RC1 dirt stage.
    # Do not identify removals by Z alone: the cobbled path and flowers
    # sit beside authentic door jambs and roof details can be low.
    if p.root==0x0e:
        residential.office(landscaped=False)
    elif p.root==0x06 or p.root==0x18:
        residential.residential(residential.BLUEPRINTS[p.root,p.look],(p.root<<4)+p.look,landscaped=False)
    else:
        # The earlier town kit deliberately separates improvements such
        # as walkways, street lamps, benches and trees into named helpers.
        # Instantiate only the structural path, then restore the helpers.
        detached=("plot","walk","lamp","tree","bench")
        builders={key:getattr(town,key) for key in detached}
        try:
            for key in detached:setattr(town,key,lambda *a,**k:None)
            town.ASSETS[p.root][1]()
        finally:
            for key,value in builders.items():setattr(town,key,value)
        fit_out={"Boundary hedge","Street-level landscaped planter","Street-level clipped shrubs",
                 "Roof terrace planted trough","Roof terrace shrubs","Window flower box","Flowering geraniums"}
        for obj in list(bpy.context.scene.objects):
            if obj.name.split(".",1)[0] in fit_out:
                bpy.data.objects.remove(obj,do_unlink=True)
    grounds(p)


def render(path,p):
    sc=bpy.context.scene
    from build_scenery_art import MATS
    MATS.clear();MATS.update({q.name:q for q in bpy.data.materials})
    box("Studio reference floor",(0,0,-.075),(9,9,.14),"stone")
    hi=max(z.co.z for o in bpy.context.scene.objects if o.type=="MESH" for z in o.data.vertices)
    distance=max(2.85,3.05+max(0,hi-1.0)*.49)
    bpy.ops.object.camera_add(location=(2.7,-3.9,2.95 if hi<1.5 else 3.61))
    cam=bpy.context.object;cam.data.type="ORTHO";cam.data.ortho_scale=distance
    cam.rotation_euler=(Vector((0,0,max(.23,hi*.47)))-cam.location).to_track_quat("-Z","Y").to_euler()
    sc.camera=cam
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x,sc.render.resolution_y=620,420
    sc.render.resolution_percentage=100
    sh=sc.display.shading;sh.light="STUDIO";sh.color_type="MATERIAL"
    sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type="BOTH"
    sh.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Quiet rural gray")
    sc.world.color=(.17,.21,.25)
    sc.view_settings.view_transform="Standard";sc.view_settings.exposure=.25
    sc.render.image_settings.file_format="JPEG";sc.render.image_settings.quality=91
    sc.render.filepath=str(Path(path)/f"{p.name}.jpg")
    bpy.ops.render.render(write_still=True)


def build(p):
    init()
    sc=bpy.context.scene
    sc.name=p.name
    sc["OpenTTD source"]="16.0-RC1 src/table/town_land.h _town_draw_tile_data"
    sc["plot and structure indices"]=f"{p.ground}, {p.upper}"
    if p.name.startswith("town_site_shell_"):
        bare_shell(p)
    else:
        grounds(p)
        if p.root in (0x06,0x1a):
            cottage(p)
        elif p.upper and p.root in (0x11,0x24):
            modern(p)
        elif p.upper and p.root==0x03:
            church(p)
        elif p.upper and p.root==0x12:
            warehouse(p)
        elif p.upper:
            masses=OFFICES[p.root]
            if p.root in (0x1b,0x1c) and p.slot==2:
                m=masses[0]
                bases={0x1b:(1.43,1.20,1.24),0x1c:(1.42,1.24,2.54)}
                w,d,h=bases[p.root]
                alt=Mass(m.x,m.y,w,d,h,"brick bright",5,m.floors+1)
                masses=(alt,*masses[1:])
            steel_building(p,masses)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=Vector((0,0,.48))
                v.region_3d.view_rotation=Vector((.77,-.93,.67)).to_track_quat("Z","Y")
                v.region_3d.view_distance=3.7
    dest=ROOT/"art"/"stock_construction"
    dest.mkdir(exist_ok=True)
    blend=dest/f"{p.name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
    ob=town.join_into_native()
    town.export_obj(ob,p.name)
    if path:=os.getenv("TOWN_SITE_REVIEW"):
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        Path(path).mkdir(exist_ok=True,parents=True)
        render(path,p)


if __name__=="__main__":
    match=re.compile(os.getenv("TOWN_SITE_FILTER","."))
    for phase in source_scenes():
        if match.search(phase.name):
            build(phase)
