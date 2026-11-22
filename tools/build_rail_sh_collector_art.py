#!/usr/bin/env python3
"""Additive body and sprung collector assets for original SH 30/40 models."""
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_sh_30_art as SH
import build_sh_40_art as V40

# World-unit local to the locomotive's mesh origin (crown) in +Y-up Luanti.
PIVOT_Y=.580
PIVOT_Z=.053
COLLECTOR="bl_rail_sh_collector"
ART="rail_sh_sprung_collector"
MOVING={
    "Linked steel lower swinging pantograph arms",
    "Slender stand-off upper support for broad collector",
    "Machined visible pantograph elbow pivot bush",
    "Fixed smaller parallelogram lower return arm",
    "Fixed smaller parallelogram upper return arm",
    "Transverse working contact shoe, level at the specified wire",
    "Thin polished outer contact edge exactly at the wire datum",
    "Slightly bent contact shoe horns clear of the wire",
}
MOUNTS={
    "Genuine turned stacked roof ceramic standoffs",
    "Painted rectangular scissor heel foot attached to roof",
    "Pressed roof blue black switching cylinder isolator mount",
    "Independent lead and service feeder to low switchgear",
}


def _shaft(m,src,parts,dy=0,dz=0):
    for k,fs in src.parts.items():
        if k not in parts:
            continue
        for a,c in fs:
            coords=[src.vertices[k][i] for i in a]
            m.tri(k,c,[(x,z+dz,y+dy) for x,z,y in coords])


def heap(sh):
    SH.setup()
    SH.R.COLORS[:]=(V40.PALETTE if sh==40 else SH.PAL).values()
    base=SH.mesh()
    if sh==40:
        V40.body(base)
    else:
        SH.locomotive_shell(base);SH.cab(base);SH.drive_and_vents(base)
    for z in (-.253,.253):
        SH.bogie(base,z)
    for z in SH.AXLES:
        SH.wheel(base,z)
    assembled=SH.mesh()
    SH.collectors(assembled)
    assert set(assembled.parts)==MOVING|MOUNTS
    active=SH.mesh()
    _shaft(base,assembled,MOUNTS)
    _shaft(active,assembled,MOVING,-PIVOT_Y,-PIVOT_Z)
    return base,active


def export(name,model):
    # 10 OBJ units per native node; body keeps its original mount.
    p=SH.R.MODELS/(name+".obj")
    SH.R.export_obj(p,SH.W.local_obj(model))
    p.write_text("# Original sprung SH roof art · tools/build_rail_sh_collector_art.py\n"+
                 p.read_text().split("\n",1)[1])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD · SH30 / SH40 detachable sprung collector"
    scene.view_settings.view_transform="Standard"
    scene["Mount (native X/Y/Z)"]=[0.,PIVOT_Y,PIVOT_Z]
    scene["Nominal child shoe (native X/Y/Z)"]=[0.,SH.CONTACT-PIVOT_Y,SH.SHOE_Z-PIVOT_Z]
    scene["Y only"]="The two body shell collections each require one collector. Animate local Y around the heel. The whole original models remain unchanged."
    for i,sh in enumerate((30,40)):
        body,active=heap(sh)
        export(f"bl_rail_sh_{sh}_body",body)
        pal=SH.colors()
        col=bpy.data.collections.new(f"SH {sh} fixed body and anchored heel")
        scene.collection.children.link(col)
        SH.R.to_blender(body,col,pal)
        for ob in col.objects:
            ob.location=(i*.92,0.,0.)
        col=bpy.data.collections.new(f"SH {sh} moving linkage; edit Y scale in Luanti / Blender Z")
        scene.collection.children.link(col)
        SH.R.to_blender(active,col,pal)
        hinge=bpy.data.objects.new(f"SH {sh} collector heel origin",None)
        col.objects.link(hinge)
        hinge.empty_display_type="ARROWS"
        hinge.empty_display_size=.065
        hinge.location=(i*.92,PIVOT_Z,PIVOT_Y)
        for ob in list(col.objects):
            if ob!=hinge:ob.parent=hinge
        if i==0:
            export(COLLECTOR,active)
            shared=active
        else:
            assert shared.parts==active.parts and shared.vertices==active.vertices
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                space=a.spaces.active
                space.shading.color_type="MATERIAL"
                space.region_3d.view_location=(.46,0.,.39)
                space.region_3d.view_rotation=Vector((.85,-1.03,.65)).to_track_quat("Z","Y")
                space.region_3d.view_distance=2.65
    bpy.ops.wm.save_as_mainfile(filepath=str(SH.R.ROOT/"art"/(ART+".blend")),compress=True)


if __name__=="__main__":
    main()
