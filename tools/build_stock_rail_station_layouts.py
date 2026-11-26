#!/usr/bin/env python3
"""Original Blender architecture for the eight stock RC1 rail platform cells.

Run: blender -b -t 4 --python-exit-code 1 --python tools/build_stock_rail_station_layouts.py
Only the layout/footprints are based on table/station_land.h, not its graphics.
"""
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_rail_architecture as A

R = A.rail


def platform(g, family):
    m = R.rail_geometry(1, 0, g)
    slab = A.slab
    # Flint-sided island platforms on both sides, with tactile stone
    # edges. End seams are open for a flush join on the next station tile.
    for sign in (-1, 1):
        at = sign * .702
        slab(m, "Battered foundation plinths", "Flagstone shadow", 0, at, 2, .596, .003, .209, open_x=True)
        slab(m, "Stone platform coping", "Dressed platform stone", 0, at, 2, .596, .209, .266, open_x=True)
        slab(m, "Flagstone platform surface", "Weathered pavers", 0, at, 2, .596, .266, .276, open_x=True)
        slab(m, "Cream railway safety strip", "Paver highlight", 0, sign*.435, 2, .036, .276, .282, open_x=True)
        # Recess caps independently from the tile seam. Adjacent
        # platform cells never supply coplanar faces at x=+/-1.
        for x in (-.988,.988):
            for material,lo,hi in (("Flagstone shadow",.003,.209),
                                   ("Dressed platform stone",.209,.266),
                                   ("Weathered pavers",.266,.276)):
                section=[(x,at-.298,lo),(x,at+.298,lo),(x,at+.298,hi),(x,at-.298,hi)]
                m.face("Recessed capped platform ends",A.P[material],section if x>0 else section[::-1])
        for x in (-.895,-.645,-.395,-.145,.105,.355,.605,.855):
            slab(m,"Masonry joints","Flagstone shadow",x,sign*.404,.008,.003,.027,.199)
    if family==2:
        # Small staff building / waiting room on the rear platform.
        z=-.766
        slab(m,"Brick waiting room","Old brick",0,z,1.080,.342,.276,.842,.025)
        slab(m,"Dressed stone plinth","Stone arch",0,z,1.100,.362,.280,.341,.021)
        for x in (-.340,.325):
            slab(m,"Timber window surrounds","Forest ironwork",x,-.590,.240,.024,.472,.705,.01)
            slab(m,"Deep-blue window glazing","Window glass",x,-.576,.197,.008,.494,.682,.007)
            slab(m,"Window sash","Cream paint",x,-.570,.020,.006,.499,.681)
            slab(m,"Window sills","Stone bevel",x,-.572,.259,.042,.438,.476,.008)
        slab(m,"Entrance trim","Stone arch",0,-.590,.207,.029,.276,.718,.013)
        slab(m,"Workshop door","Workshop door wood",0,-.570,.173,.013,.276,.683,.010)
        for lo,hi in ((-.984,z),(z,-.548)):
            roof=lambda x,w:.975-abs(w-z)*.62
            slab(m,"Gabled slate roof","Slate",0,(lo+hi)/2,1.181,hi-lo,lambda x,w:roof(x,w)-.033,roof)
        slab(m,"Roof ridge","Slate seam",0,z,1.197,.039,.964,.981)
        slab(m,"Porcelain station name board","Green enamel",0,-.547,.384,.025,.752,.814,.009)
        slab(m,"Name board inset","Cream paint",0,-.532,.292,.009,.770,.797,.003)
        slab(m,"Chimney","Brick shadow",-.375,-.849,.112,.107,.894,1.036,.008)
        slab(m,"Chimney coping","Stone bevel",-.375,-.849,.139,.132,1.034,1.061,.007)
    elif family in (4,6):
        # Complementary ribs and rear/front pillars. Adjacent A/B cells
        # make a two-track glass train shed; the roof stays clear of trains.
        sign=-1 if family==4 else 1
        for x in (-.815,.815):
            slab(m,"Riveted pillar bases","Stone bevel",x,sign*.922,.133,.123,.280,.375,.014)
            slab(m,"Cast iron columns","Forest ironwork",x,sign*.922,.066,.066,.370,1.473,.015)
            slab(m,"Decorative capitals","Green enamel",x,sign*.922,.101,.106,1.395,1.470,.012)
        sections=[(-1,-.65),(-.65,-.31),(-.31,0),(0,.31),(.31,.65),(.65,1)]
        roof=lambda x,z:1.43+.34*(1-((z+sign)/2)**2)
        for lo,hi in sections:
            for x in (-.818,0,.818):
                slab(m,"Riveted curved roof ribs","Forest ironwork",x,(lo+hi)/2,.047,hi-lo,
                     lambda a,b:roof(a,b)-.059,roof,bottom_skin=True)
            if (lo,hi) in sections[1:-1]:
                for left,right in ((-.952,-.851),(-.782,-.032),(.032,.782),(.851,.952)):
                    slab(m,"Blue-grey roof glazing","Window glass",(left+right)/2,(lo+hi)/2,
                         right-left,hi-lo-.009,lambda a,b:roof(a,b)-.029,lambda a,b:roof(a,b)-.009)
        for z in (-.65,-.31,0,.31,.65):
            slab(m,"Longitudinal glazing bars","Green enamel",0,z,2,.024,
                 lambda a,b:roof(a,b)-.033,lambda a,b:roof(a,b)+.009)
        slab(m,"Platform-side rain gutter","Slate",0,sign*.968,2,.057,1.397,1.462,open_x=True)
    return m


def seam(gfx, mask):
    family, axis = gfx-gfx%2, gfx%2
    sign = -1 if family==4 else 1
    # Rotating +X to -Z reverses the sense of the two end bits.
    ends = ((mask & 1)<<1)|((mask & 2)>>1) if axis else mask & 3
    m = R.Mesh(R.terrain_height(0))
    roof=lambda x,z:1.43+.34*(1-((z+sign)/2)**2)
    def glass(x0,x1,z0,z1):
        corners=[(x0,z0),(x1,z0),(x1,z1),(x0,z1)]
        m.face("Continuous canopy glazing", A.P["Window glass"], [(x,z,roof(x,z)-.009) for x,z in corners])
        m.face("Canopy liner", A.P["Window glass"], [(x,z,roof(x,z)-.029) for x,z in corners[::-1]])
    for end in (-1,1):
        if not ends & (1 if end<0 else 2):
            continue
        for low,high in ((-.65,-.31),(-.31,0),(0,.31),(.31,.65)):
            glass(-1 if end<0 else .952,-.952 if end<0 else 1,low+.0045,high-.0045)
    if mask & 4:
        low,high = (.65,1) if sign<0 else (-1,-.65)
        glass(-1 if ends & 1 else -.952,1 if ends & 2 else .952,low,high)
    if axis:
        m=A.rotated(m,3)
    overlay=R.Mesh(R.terrain_height(0))
    for group,faces in m.parts.items():
        for face,color in faces:
            verts=m.vertices[group]
            # Renderer puts the supplemental glass in the spare node one
            # unit to the right; compensate instead of replacing the platform.
            overlay.face(group,color,[(verts[i][0]-1,verts[i][1],verts[i][2]) for i in face])
    return overlay


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD / stock railway platform layouts"
    mats=R.materials()
    geos=R.Geos()
    for family in (0,2,4,6):
        x=platform(geos,family)
        for axis,mesh in ((0,x),(1,A.rotated(x,3))):
            gfx=family+axis
            name=f"Rail station layout {gfx}"
            col=R.stash(mesh,mats,name)
            R.instance(bpy.context.scene,col,3*(family//2),3*axis)
            R.export_obj(R.MODELS/f"bl_rail_station_gfx_{gfx}.obj",mesh,generator=Path(__file__).name)
    for gfx in range(4,8):
        for mask in range(1,8):
            mesh=seam(gfx,mask)
            name=f"Supplemental canopy glazing {gfx} join {mask}"
            col=R.stash(mesh,mats,name)
            R.instance(bpy.context.scene,col,3*gfx,12+3*mask)
            R.export_obj(R.MODELS/f"bl_rail_station_gfx_{gfx}_join_{mask}.obj",mesh,generator=Path(__file__).name)
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_station_layouts.blend"),compress=True)


if __name__=="__main__":
    main()
