#!/usr/bin/env python3
"""Build the electrified versions of the native 45° overlay rails.

Run: blender -b -t 2 --python-exit-code 1 --python tools/build_eased_rail_catenary_art.py
The existing palette, mast, wire section heights and collector interface
are unchanged. This kit uses the same centerline as the running gear.
"""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_catenary_art as C
from build_rail_diagonal_art import EasedPath


class CatenaryPath(EasedPath):
    def offset(self,t,across):
        x,z,dx,dz=self.sample(t)
        if t in (0.,1.):
            # Cut the open cable prism by the physical tile edge, not a
            # plane normal to travel. Adjacent oblique sections therefore
            # share all four wire vertices with no protruding end faces.
            if abs(x)>.999:
                return x,z+across/dx
            return x-across/dz,z
        if t==.5 and across==.730:
            # Put the pole on level ballast-side ground inside its tile,
            # not over a neighboring embankment or the running rail.
            possibilities=[(x-i*.65*dz,z+i*.65*dx) for i in (1,-1)]
            return min(possibilities,key=lambda v:max(abs(k) for k in v))
        return x-across*dz,z+across*dx


def main():
    C.R.bpy.ops.wm.read_factory_settings(use_empty=True)
    models=[]
    for idx in range(2,6):
        for mode in (1,2,3):
            for pole in (0,1):
                path=CatenaryPath(idx,mode)
                # Straight diagonals need no tessellation changes at
                # seams; metadata here is authoring only.
                path.is_straight=mode==3
                obj=C.R.Mesh(C.R.terrain_height(0))
                C.wire(obj,path)
                if pole:
                    path.is_straight=True # caller chooses safe side above
                    C.mast(obj,path)
                name=f"bl_rail_catenary_eased_{2**idx}_{mode}_{pole}"
                C.R.export_obj(C.R.MODELS/(name+".obj"),obj,vertical_origin=1.5)
                models.append((name,obj))
    C.author(models,"rail_diagonal_catenary.blend")


if __name__=="__main__":
    main()
