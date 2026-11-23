#!/usr/bin/env python3
"""Stock-type monorail and magnetic bridge decks, ramp seams and real open bore mouths."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import os,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
# The conventional modeller records its own material data at import.
import build_rail_span_art as base
import build_advanced_guideway_art as guide

kit,bpy=base.kit,base.bpy
colors={i:f"Guideway shade {i:02}" for i in range(len(guide.COLOR))}
COLORS=base.COLORS|{label:guide.COLOR[i] for i,label in colors.items()}

def track_skeleton(geos,legacy,shift,grade,family):
    """Preserve the real bridge/tunnel structure, replace only its wheelway."""
    old=kit.Mesh()
    base.full_track(old,lambda _:0,"full",guards="span")
    for g in old.groups:
        legacy.groups.pop(g,None)
    m=guide.mesh(family,2,grade,geos)
    for g,faces in m.parts.items():
        for f,c in faces:
            legacy.poly("Guideway / "+g,colors[c],*((u,v,h+shift) for u,v,h in (m.vertices[g][i] for i in f)))
    return legacy

def main(family="mono"):
    assert family in {"mono","maglev"}
    prefix=f"bl_guideway_{family}_span"
    title="Monorail" if family=="mono" else "Maglev"
    artifact="monorail" if family=="mono" else "maglev"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    kit.COLORS=COLORS;kit.PREFIX=prefix
    mats=kit.materials()
    g=guide.G.Geos()
    assets={}
    for i,turn in enumerate((2,1)):
        full=track_skeleton(g,base.bridge("span"),.5,0,family).oriented(turn)
        assets[f"span_{i}"]=full
        clean=full.oriented(1)
        for name in ("Trestle twin king posts","Main bearing seat","Cross cap immediately below four stringers",
                     "Cross cap lower sole","Bearing cap carriage bolts"):
            assert clean.groups.pop(name,None)
        assets[f"span_{i}_road_clear"]=clean
    for d in range(4):
        for variant in ("flat","ramp"):
            ramp=variant=="ramp"
            assets[f"head_{variant}_{d}"]=track_skeleton(g,base.bridge(variant),-.5 if ramp else .5,3 if ramp else 0,family).oriented(d)
        assets[f"tunnel_{d}"]=track_skeleton(g,base.tunnel(),0,0,family).oriented(d)
    coll={}
    for name,m in assets.items():
        kit.export(name,base.lower(m,-.5) if name.startswith("tunnel") else m)
        coll[name]=kit.author(m,title+" / "+name,mats)
    for v,p in ((-4,"head_ramp_1"),(-2,"span_1"),(0,"span_1"),(2,"span_1"),(4,"head_ramp_3")):
        kit.instance(coll[p],(-2.2,v,1))
    kit.instance(coll["tunnel_1"],(2.4,0,0))
    kit.atlas()
    scene=bpy.context.scene
    scene.name=f"LuanTTD | {title} timber railway and true masonry bores"
    scene["Provenance"]="Original Blender guideway and structural kit. RC1 slope, relative tile offset and topology."
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/f"art/{artifact}_spans.blend"),compress=True)

if __name__=="__main__":
    main(sys.argv[-1] if "--" in sys.argv else "mono")
