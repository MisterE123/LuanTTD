#!/usr/bin/env python3
"""Original, accessible full-width guideway facilities for both late rail types."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import os
import sys
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_advanced_guideway_art as Guide
import build_rail_architecture as A

G,bpy=Guide.G,Guide.bpy
COLORS={
    "Formed concrete":"9eaaa7", "Darker aggregate":"707f7a", "Glare guard":"d7dfd7",
    "Passenger grit":"8c9895", "Cool lintels":"688890", "Signal teal":"307179",
    "Safety ochre":"d6b144", "Monorail marine":"3d5967", "Magnetic wine":"714d53",
    "Brushed aluminum":"a0aeb0", "Workshop glass":"6f8f9b", "Window underside":"40545e",
    "Glazed upper reflection":"bdd0cb", "Composite roof":"666f73", "Drained roof seam":"3e4c50",
    "Deep train stop":"843f37", "Bench slats":"9c773f",
}
V={k:i+len(G.COLORS) for i,k in enumerate(COLORS)}
G.COLORS.extend(COLORS.values()); A.P.update(V)


def platform(family,geos):
    m=Guide.mesh(family,1,0,geos)
    mono=family=="mono"
    deck=.431 if mono else .397
    nose=.284 if mono else .358
    tip=.953
    c="Monorail marine" if mono else "Magnetic wine"
    def box(label,mat,x,z,dx,dz,lo,hi,bevel=0,**kw):
        A.slab(m,label,mat,x,z,dx,dz,lo,hi,bevel,**kw)
    # Level deck and gap to bodysides are continuous through the tile.
    box("Load bearing rail platform walls","Darker aggregate",0,(nose+tip)/2,2,tip-nose,.002,deck-.063,
        open_x=True,bottom_skin=False)
    box("Rounded reinforced deck edge","Formed concrete",0,(nose+tip)/2,2,tip-nose,
        deck-.063,deck-.018,open_x=True,bottom_skin=False)
    box("Textured tactile platform edge","Safety ochre",0,nose+.020,2,.040,
        deck-.018,deck,open_x=True,bottom_skin=False)
    n0=nose+.04
    box("Broom-finished passenger paving","Passenger grit",0,(n0+tip)/2,2,tip-n0,
        deck-.018,deck-.003,open_x=True,bottom_skin=False)
    for x in (-.982,.982):
        profile=((x,nose,.003),(x,tip,.003),(x,tip,deck-.004),(x,nose,deck-.004))
        m.face("Recessed closed platform ends",V["Darker aggregate"],profile if x>0 else profile[::-1])
    for i in range(16):
        xx=-.938+.124*i
        for row in (nose+.013,nose+.027):
            box("Individually raised tactile studs","Glare guard",xx,row,.020,.007,deck,deck+.005,.002)
    for i in range(11):
        x=-.95+.19*i
        box("Scored contraction joints","Darker aggregate",x,tip-.1,.008,.17,deck-.003,deck-.001)
    for x in (-.36,.36):
        for z in (.637,.848):
            box("Tubular canopy supports","Cool lintels",x,z,.041,.041,deck,.91,.007)
            box("Anchored post feet","Formed concrete",x,z,.076,.076,deck,deck+.033,.007)
    box("Free-standing aluminum canopy","Brushed aluminum",0,.741,.812,.40,.904,.954,.023)
    box("Rain runnel and fascia","Composite roof",0,.741,.844,.416,.945,.978,.025)
    for x in (-.19,0,.19):
        box("Exterior glazing in detached windscreen","Workshop glass",x,.848,.181,.025,deck+.09,.888,.007)
        box("Soft light in each separate pane","Glazed upper reflection",x,.833,.150,.004,.814,.862)
    box("Backless hardwood passenger bench","Bench slats",0,.769,.473,.091,deck+.124,deck+.147,.008)
    for x in (-.164,.164):
        box("Closed bench footings","Cool lintels",x,.778,.036,.078,deck,deck+.125,.004)
    box("High contrast station identifier panel",c,0,.597,.311,.022,.803,.886,.007)
    for x in (-.104,-.053,.002,.051,.102):
        box("Light station lettering stems","Glare guard",x,.582,.020,.005,.830,.859)
    return m


def shed(family,geos):
    m=A.clip_behind(Guide.mesh(family,2,0,geos),-.785)
    mono=family=="mono"
    c="Monorail marine" if mono else "Magnetic wine"
    theme="Signal teal" if mono else "Brushed aluminum"
    def box(label,mat,x,z,dx,dz,lo,hi,bevel=0,**kw):
        A.slab(m,label,mat,x,z,dx,dz,lo,hi,bevel,**kw)
    for s in (-1,1):
        box("Floating side services slab","Darker aggregate",s*.589,-.08,.313,1.641,.011,.113,.028)
        box("Composite depot side wall","Formed concrete",s*.632,-.107,.177,1.588,.092,.944,.022)
        box("Turned lower cladding",c,s*.723,-.099,.032,1.501,.183,.394,.006)
        for z in (-.65,-.39,-.13,.13,.39):
            box("Side maintenance window seals","Window underside",s*.729,z,.034,.190,.502,.776,.008)
            box("Tempered shop window","Workshop glass",s*.749,z,.015,.166,.524,.754,.006)
            box("Sky from the back of the workshop","Glazed upper reflection",s*.759,z,.005,.142,.688,.734)
        box("Shop ventilation beam",c,s*.648,-.106,.181,1.598,.813,.921,.013)
        for z in (-.59,-.472,-.354,-.236,-.118,0,.118,.236,.354):
            box("Recessed exterior vents","Window underside",s*.748,z,.011,.080,.850,.885)
        box("Edge stripes at safe walk lanes","Safety ochre",s*.415,-.11,.028,1.359,.038,.047,.004)
        box("Separate raised workshop platform","Passenger grit",s*.464,-.109,.123,1.35,.013,.037,.007)
        box("Composite structural portal columns",theme,s*.548,.671,.22,.167,.018,.961,.025)
        box("Train opening lintel jambs","Cool lintels",s*.432,.691,.033,.177,.101,.933,.008)
    box("Solid workshop fire back","Darker aggregate",0,-.896,1.450,.126,.014,.998,.013)
    box("Portal beam retaining full rolling clearway",c,0,.674,1.294,.191,.948,1.083,.022)
    box("Weather-rated low angular canopy","Brushed aluminum",0,.759,1.508,.240,1.055,1.099,.015)
    box("Long flat folded sheet roof","Composite roof",0,-.095,1.546,1.696,.931,1.058,.025)
    for x in (-.639,-.427,-.213,0,.213,.427,.639):
        box("Sealed roof standing seams","Drained roof seam",x,-.10,.014,1.609,1.057,1.072,.002)
    box("Inside end-of-guideway service buffer","Deep train stop",0,-.752,.488,.059,.085,.302,.013)
    for x in (-.352,.352):
        box("Operational depot doorside lights","Glare guard",x,.769,.066,.027,.868,.919,.009)
    box("Fleet insignia over the portal",theme,0,.786,.245,.012,.995,1.040,.004)
    for x in (-.072,-.024,.024,.072):
        box("Embossed bay number details","Glare guard",x,.794,.022,.004,1.009,1.028)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name="LuanTTD | Native elevated-guideway facilities"
    sc["Provenance"]="Original editable platform and engine depot, with actual RC1 type-specific guideways."
    mats=G.materials()
    geo=G.Geos()
    for j,family in enumerate(("mono","maglev")):
        for stem,base,turns in (("platform",platform(family,geo),(0,3)),
                                ("depot",shed(family,geo),(1,0,3,2))):
            for i,turn in enumerate(turns):
                model=A.rotated(base,turn)
                name=f"guideway_{family}_{stem}_{i}"
                coll=G.stash(model,mats,name)
                if turn==0: G.instance(sc,coll,-1.35+j*2.7,-1.30+(2.6 if stem=="depot" else 0))
                G.export_obj(G.MODELS/f"bl_{name}.obj",model,generator=Path(__file__).name)
    # Guide.atlas uses its fixed palette. Export with the complete schematic.
    import struct,zlib
    for family in ("mono","maglev"):
        def chunk(n,p):return struct.pack(">I",len(p))+n+p+struct.pack(">I",zlib.crc32(n+p))
        raw=b"".join(bytes.fromhex(color)*8 for color in G.COLORS)
        (G.TEXTURES/f"bl_guideway_{family}_facility_atlas.png").write_bytes(
          b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(G.COLORS)*8,8,8,2,0,0,0))
          +chunk(b"IDAT",zlib.compress((b"\0"+raw)*8,9))+chunk(b"IEND",b""))
    cam=bpy.data.objects.new("Showcase",bpy.data.cameras.new("Transit architecture view"))
    sc.collection.objects.link(cam);cam.location=(6,8,8)
    cam.rotation_euler=(Vector((0,0,.30))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=7.25;sc.camera=cam
    bpy.ops.wm.save_as_mainfile(filepath=str(G.ROOT/"art/advanced_rail_facilities.blend"),compress=True)
    if out:=os.getenv("GUIDEWAY_FACILITY_REVIEW"):
        bpy.ops.mesh.primitive_plane_add(size=16,location=(0,0,-.005))
        grass=bpy.data.materials.new("Muted meadow");grass.diffuse_color=(.186,.255,.131,1)
        bpy.context.object.data.materials.append(grass)
        sc.render.engine="BLENDER_WORKBENCH";sc.render.resolution_x=1180;sc.render.resolution_y=970
        shading=sc.display.shading
        shading.color_type="MATERIAL";shading.light="STUDIO";shading.show_shadows=True
        shading.show_cavity=True;shading.cavity_type="BOTH";sc.render.filepath=out
        sc.view_settings.view_transform="Standard"
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()
