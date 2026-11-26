#!/usr/bin/env python3
"""Bake the native RC1 curve-contact masts in both overlay positions."""
from copy import deepcopy
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_rail_edge_pylons as Edge

X,Z=(0,8,16,8),(8,16,8,0)
DX,DZ=(-2,-4,-2,0,2,4,2,0),(-2,0,2,4,2,0,-2,-4)
CASES=((0,4,0),(0,6,0),(1,0,0),(1,5,1),(1,6,1),
       (2,0,1),(2,2,0),(2,7,0),(3,2,1),(3,4,1))

def main():
    authored=[]
    for edge,pole,slot in CASES:
        x,z=X[edge],Z[edge]
        p=Edge.model(x+DX[pole],z+DZ[pole],x,z)
        name=f"bl_rail_curve_pylon_{edge}_{pole}_{slot}"
        authored.append((name,p))
        export=deepcopy(p)
        xoff,zoff=(1,0) if slot==0 else (0,1)
        for key,row in export.vertices.items():
            export.vertices[key]=[(x-xoff,z-zoff,y) for x,z,y in row]
        Edge.R.export_obj(Edge.R.MODELS/(name+".obj"),export,vertical_origin=1.5,generator="build_rail_curve_pylons.py")
    Edge.W.author(authored,"rail_curve_pylons.blend")

if __name__=="__main__":
    main()
