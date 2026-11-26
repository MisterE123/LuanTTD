#!/usr/bin/env python3
"""Author reusable native RC1 pylon meshes on the four edge slots.

Run with Blender. Offsets are integer OpenTTD tile pixels from
elrail_data.h's PCP and PPP tables, measured on a two-node tile.
"""
from copy import deepcopy
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_edge_pylons as E

R,W=E.R,E.W
POINTS=(
    ((3,0,12),(4,2,10),(6,2,6)),
    ((0,6,14),(5,12,16),(6,10,14)),
    ((0,14,6),(2,14,10),(7,16,4)),
    ((1,4,0),(2,6,2),(4,10,2)),
)
PCP=((0,8),(8,16),(16,8),(8,0))
ANCHORS=((1,0,0),(0,0,1),(1,0,1),(0,1,0))

def main():
    assembled=[]
    for edge,opts in enumerate(POINTS):
        cx,cz=PCP[edge]
        dx,dy,dz=ANCHORS[edge]
        for direction,px,pz in opts:
            name=f"bl_rail_distributed_pylon_{edge}_{direction}"
            p=E.model(px,pz,cx,cz)
            assembled.append((name,p))
            out=deepcopy(p)
            for part,verts in out.vertices.items():
                out.vertices[part]=[(x-dx,z-dz,y) for x,z,y in verts]
            R.export_obj(R.MODELS/(name+".obj"),out,vertical_origin=1.5+dy,
                         generator="build_rail_distributed_pylons.py")
    W.author(assembled,"rail_distributed_pylons.blend")

if __name__=="__main__":
    main()
