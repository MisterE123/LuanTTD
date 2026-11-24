#!/usr/bin/env python3
"""Alternate 14-tile RC1 steel works, using the original mill component kit.

blender -b -t 3 --python-exit-code 1 --python tools/build_stock_steel_mill_layout_1_art.py
Set STOCK_STEEL_L1_PREVIEW=/tmp/steel-l1.png for a survey render.
"""
from collections import Counter
from math import sqrt
from pathlib import Path
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_metal_industry_art as M

A,R,S=M.A,M.R,M.S
B,T,F,Q=M.B,M.T,M.F,M.Q
ROOT=M.ROOT
LAYOUT={(0,0):52,(0,1):53,(1,0):54,(1,1):55,
        (2,0):52,(2,1):53,(3,0):54,(3,1):55,
        (0,2):56,(1,2):57,(2,2):56,(3,2):57,(1,3):56,(2,3):57}
REUSE=((0,2),(1,2))
STYLE="industry_steel_mill_l1"
PALETTE="industry_steel_mill"
SOURCE=ROOT/"art/stock_steel_mill_layout_1.blend"


def move_into(dst,src,valid,dx=0,dz=0,label=""):
    for name,records in src.parts.items():
        if valid(name):
            for ids,color in records:
                face=src.vertices[name]
                dst.face((label+" "+name) if label else name,color,[(face[i][0]+dx,face[i][1]+dz,face[i][2]) for i in ids])


def known_rolling_units(m):
    # The large shed, roof monitor, crane, and furnace/stack profiles are
    # original LuanTTD layout-0 art, not new approximations of the same cells.
    # All four 52/53/54/55 tile relationships within a unit are unchanged.
    house,blast=A.mesh(),A.mesh()
    M.steel_house(house)
    M.steel_furnaces(blast)
    for k,dx in enumerate((-4,0),1):
        tag=f"Unit {k}"
        move_into(m,house,lambda _:True,dx,-2,tag)
        # Their circular guardrails formerly had a northern yard tile as
        # a small catchment. Translate rigidly another .12 south so no
        # rooftop handrail is cut flat by the new northern site boundary.
        move_into(m,blast,lambda n:n.startswith(("GFX52 ","GFX54 ")),dx,-1.88,tag)
        # This hopper is wholly part of the retained upper charging equipment.
        move_into(m,blast,lambda n:n.startswith("High charging and gravity skip discharge bin"),dx,-1.88,tag)
        # The interior transfer deck belongs to the existing workshop. Keep
        # its seam coordinates and move the whole continuous rail together.
        rail=A.mesh()
        M.steel_yard(rail)
        move_into(m,rail,lambda n:n.startswith("Under-house low hot section runner"),dx,-2,tag)


def working_surfaces(m):
    M.ground(m,LAYOUT,"ashphalt")
    old=A.mesh()
    M.steel_yard(old)
    move_into(m,old,lambda n:n.startswith(("Siding along steel ingot yard","Distinct layered finished slab ingot stacks",
                                          "Separated low slag bin","Discarded cast shape in open slag bin")))
    # Right-hand apron sits next to both rolling units, not underneath the
    # old row-0 northeast feed banks, so new bins/ore piles are low and clear.
    for x,z,h,c in ((4.33,4.46,.37,"hematite"),(6.43,4.54,.44,"coke")):
        stock="New eastern ore and coke bays"
        M.strata(m,stock,x,z,.61,.54,h,
                 ("hematite_dark","hematite","hematite_sun","clay_cut","limonite") if c=="hematite"
                 else ("coke","coke_sun","shale","slag","coke"),int(x*980+z*6),6)
        B(m,stock+" stone containment wall","workstone",x,z+.58,1.51,.10,.022,.215,.012)
        B(m,stock+" short slag divider","aggregate",x+.694,z+.28,.08,.66,.026,.179,.014)
    # Private yard south of the two unchanged GFX56/57 tiles. Back-to-back
    # flatbar racks and rails fit the two 56/57 extensions only.
    for j in range(2):
        for i in range(3):
            x=1.98+.46*i+2.0*j
            for ply in range(4+(i+j)%2):
                y=.064+ply*.067
                B(m,"Southern dispatch finished slabs and pig iron","steel_plate" if (i+ply)%3 else "roof_rib",
                  x,6.76-.09*(i%2),.378,.63,y,y+.052,.009)
        x=2.41+2*j
        B(m,"Low capped barrier ends loading apron","workstone",x,7.265,1.48,.113,.015,.193,.012)
        B(m,"Recessed truck bed painted bumper rail","yellow_safety",x,7.183,1.25,.055,.079,.122,.012)
    M.track(m,"Rear loading rail along the two-cell southern extension",
            [(1.79,5.968),(3.47,6.04),(5.175,6.00)],.155)


def alternate_connections(m):
    # Layout 0's belt/return pipe came from yards at its north and west; the
    # north and west of the first process unit are now boundary terrain.
    # Feed from the surviving southern apron via slender external spine walks.
    for i,x in enumerate((-.205,3.54),1):
        h=1.093+(i-1)*.074
        stem=f"Unit {i} redirected charging-back supply"
        fx=.593+4*(i-1)
        M.conveyor(m,stem+" long side loading elevator",(x,3.316,.24),(x,.585,h),.285)
        M.conveyor(m,stem+" steep upper bridge",(x,.585,h),(fx,.169,2.468),.305)
        M.pipe(m,f"Unit {i} redirected blast pressure return","oxidized_steel",
          [(x+.11,.43,.62),(x+.10,.25,.81),(fx-.23,.14,.84),(fx-.118,.145,1.24)],.059)
    # Slender hot-air column groups travel with the two furnace units' new
    # available east boundaries. No geometry extends past an occupied tile.
    for n,(x,z,h) in enumerate(((1.425,.015,1.36),(3.13,1.103,1.44),
                                 (5.410,.027,1.45),(7.137,.942,1.48)),1):
        label=f"Plant {n} Cowper pressure stove"
        T(m,label+" heat footing","millbrick_dark",(x,z,.035),(x,z,.19),.213,.212,13)
        T(m,label+" vertical heat exchanger","oxidized_steel",(x,z,.171),(x,z,h),.182,.177,14)
        T(m,label+" galvanized dome","roof_zinc",(x,z,h),(x,z,h+.12),.184,.062,14)
        for y in (.32,.71,1.03):
            T(m,label+" broad structure ring","roof_rib",(x,z,y),(x,z,y+.039),.189,.188,14)
        M.ladder(m,label+" access rung",x,z+.198,.093,h-.052)
    # Keep the central service alley visually continuous without pretending the
    # siding is a player-operated route. Stripes don't overlap old ballast.
    for j in range(7):
        z=1.27+j*.292
        Q(m,"Repainted alley warning stripes","yellow_safety",3.692,3.746,z,z+.127,.018)
    B(m,"Steel transfer platform apron end","metal_blue",4.944,5.225,.78,.21,.057,.178,.011)


GROUPS=(
    ("01 Matched layout-zero yards and shared southern apron",working_surfaces),
    ("02 Reused paired 52-55 furnace and rolling-plant units",known_rolling_units),
    ("03 Changed adjacency: redirected raw stock and blast loop",alternate_connections),
)


def scene_meshes():
    group_meshes=[]
    total=A.mesh()
    for name,builder in GROUPS:
        group=A.mesh()
        builder(group)
        group=M.triangulated(group)
        group_meshes.append((name,group))
        move_into(total,group,lambda _:True)
    for name,vertices in total.vertices.items():
        for x,z,_ in vertices:
            assert any(2*i-.500001<=x<=2*i+1.500001 and 2*j-.500001<=z<=2*j+1.500001
                       for i,j in LAYOUT),(name,x,z,"orphaned geometry outside stock plot")
    return group_meshes,total


def mesh_faces(m):
    """Quantized unordered triangle coordinates plus palette, for reuse audit."""
    result=Counter()
    for name,faces in m.parts.items():
        points=m.vertices[name]
        for ids,c in faces:
            coords=tuple(sorted(tuple(round(k,6) or 0 for k in points[i]) for i in ids))
            result[(coords,c)]+=1
    return result


def runtime_obj(path):
    points=[]
    tris=Counter()
    for line in path.read_text().splitlines():
        vals=line.split()
        if not vals:continue
        if vals[0]=="v":
            xx,yy,zz=map(float,vals[1:])
            points.append((-xx-.5,zz-.5,yy+.5))
        elif vals[0]=="f":
            refs=[tuple(map(int,s.split("/"))) for s in vals[1:]]
            vtc={q[1] for q in refs}
            assert len(vtc)==1
            p=tuple(sorted(tuple(round(k,6) or 0 for k in points[q[0]-1]) for q in refs))
            tris[p,next(iter(vtc))-1]+=1
    return tris


def write_assets(total,test_only=False):
    for (x,z),gfx in LAYOUT.items():
        f=R.MODELS/f"bl_{STYLE}_{x}_{z}.obj"
        header=f"# OpenTTD 16.0-RC1 industry 8, layout 1 ({x},{z}) GFX {gfx}; original Blender art\n"
        tile=M.triangulated(S.clip(total,x,z,LAYOUT))
        if (x,z) in REUSE:
            base=R.MODELS/f"bl_{PALETTE}_{x}_{z}.obj"
            # Rural replay follows both authoring and frozen baseline bytes.
            # Clip tool and atlas are the same; exact source trim unchanged.
            assert runtime_obj(base)==mesh_faces(tile),(x,z,"old yard relationship changed")
            content=header+base.read_text().split("\n",1)[1]
            if test_only:assert f.read_text()==content,f
            else:f.write_text(content)
        elif test_only:
            assert runtime_obj(f)==mesh_faces(tile),f
        else:
            R.export_obj(f,tile)
            previous=f.read_text().split("\n",1)[1]
            f.write_text(header+previous)
    palettes=ROOT/"mods/luanttd_core/textures"
    base=palettes/f"bl_{PALETTE}_atlas.png"
    alt=palettes/f"bl_{STYLE}_atlas.png"
    if test_only:assert base.read_bytes()==alt.read_bytes()
    else:alt.write_bytes(base.read_bytes())


def build():
    groups,total=scene_meshes()
    if "--check" in sys.argv:
        write_assets(total,True)
        print("All 14 assigned stock steel mill sections match real clipped source.")
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.name="Stock Steel Mill, layout 1"
    scene["OpenTTD RC1 source"]=f"{M.SOURCE_SHA}: src/table/build_industry.h _tile_table_steel_mill_1"
    scene["Native tile reference"]=" | ".join(f"({x},{z}) GFX{g}" for (x,z),g in LAYOUT.items())
    mats=R.materials()
    for i,n in enumerate(M.PAL):mats[i].name=n.replace("_"," ").title()
    for name,mesh in groups:
        coll=bpy.data.collections.new(name)
        scene.collection.children.link(coll)
        R.to_blender(mesh,coll,mats)
    write_assets(total)
    look,where=Vector((3.50,3.22,.57)),Vector((12.5,12.9,9.2))
    rot=(look-where).to_track_quat("-Z","Y")
    camera=bpy.data.objects.new("Survey camera",bpy.data.cameras.new("Survey camera"))
    scene.collection.objects.link(camera)
    camera.location=where
    camera.rotation_euler=rot.to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=10.88
    scene.camera=camera
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=look
                view.region_3d.view_distance=13.2
                view.region_3d.view_rotation=rot
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=980
    scene.render.resolution_y=820
    shading=scene.display.shading
    shading.light="STUDIO"
    shading.color_type="MATERIAL"
    shading.show_shadows=True
    shading.show_cavity=True
    shading.cavity_type="BOTH"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.26
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
    shot=os.environ.get("STOCK_STEEL_L1_PREVIEW")
    if shot:
        bpy.ops.mesh.primitive_plane_add(size=100,location=(look.x,look.y,-.001))
        lower=bpy.data.materials.new("Surrounding meadow review only")
        lower.diffuse_color=(.156,.238,.102,1)
        bpy.context.object.data.materials.append(lower)
        scene.render.filepath=shot
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":build()
