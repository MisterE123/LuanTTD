#!/usr/bin/env python3
"""Original continuous RC1 monorail and maglev guideways in native 3D."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import os
import struct
import sys
import zlib

from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as G
from build_rail_diagonal_art import EasedPath
bpy=G.bpy
COLOR=(
    "666e6a","8c8a78","9c9c8a","737f7e","a6ada5","bcc0a9","444d4c","7f8c89",
    "505c60","77858a","909c9e","434d53","596c71","9e9d8b","ad8a5b","696657",
    "c2caca","7ca5ad","6b7e71")
G.COLORS[:]=COLOR
SHADOW,PLINTH,CAPS,BEAM,SHOULDER,CHAMFER,JOINT,BEAM_SIDE,STATOR_BASE,STATOR_FRAME,STATOR_COOL,CLAD,FASCIA,ENDCAP,COPPER,DUST,GUIDE,TRIM,HINT=range(len(COLOR))
NATIVE={
    "mono":{ "base_width":.263,"shoe":.206,"upper":.118,"top":.246,"hold":.170},
    "maglev":{ "base_width":.338,"shoe":.293,"upper":.251,"top":.213,"hold":.170},
}
FULL_TILE=[[(-1,-1),(1,-1),(1,1),(-1,1)]]

def mesh(type_,mask,grade,geos,ease=0):
    p=NATIVE[type_]
    shape=G.Mesh(G.terrain_height(grade))
    paths=[EasedPath(j,ease) if ease else G.TrackPath(j) for j in range(6) if mask&(1<<j)]
    tile=geos.union(FULL_TILE)
    def clipped(g):
        k=geos.lib.GEOSIntersectionPrec(g,tile,G.GEOMETRY_PRECISION)
        geos.free(g)
        assert k
        return k

    def outline(w):
        return clipped(geos.union([v.sweep(-w,w) for v in paths]))

    def surface(route,name,color,h):
        shape.skin(route,name,color,lambda x,z:h,geos)

    def strip(out,inner,name,color,h):
        shell=geos.difference(out,inner)
        surface(shell,name,color,h)
        geos.free(shell)

    foot,shoe,spine=map(outline,(p["base_width"],p["shoe"],p["upper"]))
    shape.side(foot,"Cross-tied foundation slab",SHADOW,.008,.053,geos)
    strip(foot,shoe,"Clean aggregate footing shoulders",PLINTH,.053)
    shape.side(shoe,"Integrated pin-bearing support plinth",CAPS,.051,.096,geos)
    strip(shoe,spine,"Flat load path under reinforcement",SHOULDER,.096)
    def distance(x,z):
        offsets=[]
        for path in paths:
            for end, anchor in enumerate((path.a,path.b)):
                dot=x*anchor[0]+z*anchor[1]
                if abs(dot-1)<1e-6:
                    direction=(path.t0,path.t1)[end] if ease else anchor
                    offsets.append(abs((x-anchor[0])*direction[1]-(z-anchor[1])*direction[0]))
            if not any(abs(x*a[0]+z*a[1]-1)<1e-6 for a in (path.a,path.b)):
                offsets.append(path.distance(x,z))
        return min(offsets)
    if type_=="mono":
        shape.side(spine,"Original continuous concrete straddle beam",BEAM,.096,.205,geos)
        rail=outline(.096)
        # Beveled real profile instead of stacked intersecting faces.
        shoulder=geos.difference(spine,rail)
        shape.skin(shoulder,"Beveled top shoulders and sides",CHAMFER,
          lambda x,z:p["top"]-max(0,min(1,(distance(x,z)-.096)/.022))*.041,
          geos)
        strip_width=.087
        inset=outline(strip_width)
        strip(rail,inset,"Smooth pale straddle wear bands",CHAMFER,p["top"])
        cuts=[]
        for path in paths:
            count=3 if path.length>1.65 else 2
            for j in range(count):
                cuts.append(G.rect(path,(j+1)/(count+1),.021,strip_width*2+.006,bevel=.004))
        lanes=clipped(geos.union(cuts))
        grid=geos.lib.GEOSIntersectionPrec(lanes,inset,G.GEOMETRY_PRECISION)
        main=geos.difference(inset,grid)
        surface(main,"Monorail surface: cast segment running band",CAPS,p["top"])
        surface(grid,"Real recesses at segment joints",JOINT,p["top"]-.005)
        shape.side(grid,"Join cut walls",BEAM_SIDE,p["top"]-.005,p["top"],geos)
        geos.free(rail,shoulder,inset,lanes,grid,main)
    else:
        shape.side(spine,"Orthogonal linear-motor guideway casing",CLAD,.095,.150,geos)
        middle=outline(.183)
        rim=geos.difference(spine,middle)
        # This is a trough: the alloy side guides are higher than the
        # complete flat motor shelf, not fake decals above one slab.
        shape.side(rim,"Raised guidance walls",FASCIA,.150,p["top"],geos)
        surface(rim,"Paired polished magnetic guide rails",GUIDE,p["top"])
        center=outline(.091)
        strip(middle,center,"Recessed steel motor shelf",STATOR_FRAME,.151)
        shape.side(center,"Exposed fault-tolerant stator bed",STATOR_BASE,.148,.162,geos)
        vlines=[]
        for path in paths:
            n=round(path.length/.19)
            for j in range(n):
                vlines.append(G.rect(path,(j+.5)/n,.035,.177,bevel=.009))
        vlines=clipped(geos.union(vlines))
        inlay=geos.lib.GEOSIntersectionPrec(vlines,center,G.GEOMETRY_PRECISION)
        inter=geos.difference(center,inlay)
        surface(inter,"Central induction strip",STATOR_COOL,.162)
        surface(inlay,"Exposed copper armature segments",COPPER,.163)
        geos.free(middle,rim,center,vlines,inlay,inter)
    geos.free(foot,shoe,spine,tile)
    shape.prune()
    return shape

def atlas(type_):
    def chunk(n,p):return struct.pack(">I",len(p))+n+p+struct.pack(">I",zlib.crc32(n+p))
    raw=b"".join(bytes.fromhex(color)*8 for color in COLOR)
    fn=G.TEXTURES/f"bl_guideway_{type_}_atlas.png"
    fn.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(COLOR)*8,8,8,2,0,0,0))
                  +chunk(b"IDAT",zlib.compress((b"\0"+raw)*8,9))+chunk(b"IEND",b""))

def run():
    geos=G.Geos()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name="LuanTTD | Monorail and magnetic guideway"
    sc["Provenance"]="Original editable concrete beam, alloy trough and junction surfaces. Only OpenTTD 16.0-RC1 track topology and grade offsets."
    mats=G.materials()
    choices={}
    for family in NATIVE:
        atlas(family)
        for mask in range(1,64):
            m=mesh(family,mask,0,geos)
            stem=f"guideway_{family}_flat_{mask}"
            coll=G.stash(m,mats,stem)
            choices[(family,mask)]=coll
            G.export_obj(G.MODELS/f"bl_{stem}.obj",m,generator=Path(__file__).name)
        for grade,mask in ((1,1),(2,1),(3,2),(4,2)):
            m=mesh(family,mask,grade,geos)
            stem=f"guideway_{family}_grade_{grade}"
            G.stash(m,mats,stem)
            G.export_obj(G.MODELS/f"bl_{stem}.obj",m,vertical_origin=1.5,generator=Path(__file__).name)
        for mask in (4,8,16,32):
            for mode in (1,2,3):
                m=mesh(family,mask,0,geos,mode)
                stem=f"guideway_{family}_eased_{mask}_{mode}"
                G.stash(m,mats,stem)
                G.export_obj(G.MODELS/f"bl_{stem}.obj",m,generator=Path(__file__).name)
    for family,x in (("mono",-2.8),("maglev",2.8)):
        for mask,dz in ((1,-3.6),(37,0),(3,3.6)):
            G.instance(sc,choices[(family,mask)],x,dz)
    cam_pos=(7.4,-9.5,11.6)
    cam=bpy.data.objects.new("Showcase context",bpy.data.cameras.new("Original guideway review"))
    sc.collection.objects.link(cam);cam.location=cam_pos
    cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=12.35;sc.camera=cam
    conv=cam.rotation_euler.to_quaternion()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                rv=area.spaces.active
                rv.shading.color_type="MATERIAL";rv.region_3d.view_rotation=conv;rv.region_3d.view_distance=14
    bpy.ops.wm.save_as_mainfile(filepath=str(G.ROOT/"art/advanced_guideways.blend"),compress=True)
    if out:=os.getenv("GUIDEWAY_REVIEW"):
        bpy.ops.mesh.primitive_plane_add(size=25,location=(0,0,-.004))
        grass=bpy.data.materials.new("Muted meadow");grass.diffuse_color=(.186,.255,.131,1)
        bpy.context.object.data.materials.append(grass)
        sc.render.engine="BLENDER_WORKBENCH";sc.render.resolution_x=1320;sc.render.resolution_y=1060
        s=sc.display.shading;s.light="STUDIO";s.color_type="MATERIAL";s.show_shadows=True
        s.show_cavity=True;s.cavity_type="BOTH";s.cavity_ridge_factor=1.28
        sc.render.filepath=out;sc.view_settings.view_transform="Standard"
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    run()
