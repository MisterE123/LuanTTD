#!/usr/bin/env python3
"""Authored cable components for electrically independent visual diagonals."""
from copy import deepcopy
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_compound_wire as C
from build_rail_diagonal_art import EasedPath

PAIRS={12:(2,3),48:(4,5)}
R,W=C.R,C.W
GEN="build_rail_paired_wire.py"

def paths(first,second,a,b):
    return {i:EasedPath(i,m) if m else R.TrackPath(i)
            for i,m in ((first,a),(second,b))}

def main():
    preview=[]
    for i in range(2,6):
        for mode in (1,2,3):
            mesh=C.wire(1<<i,{i:EasedPath(i,mode)})
            C.export_contact(R.MODELS/f"bl_rail_pair_single_{1<<i}_{mode}.obj",mesh,GEN)
    for mask,(first,second) in PAIRS.items():
        rotate=mask==12
        p=C.portal()
        if rotate:
            for key,row in p.vertices.items():
                p.vertices[key]=[(-z,x,y) for x,z,y in row]
            out=deepcopy(p)
            for key,row in out.vertices.items():
                out.vertices[key]=[(x-1,z-1,y) for x,z,y in row]
            R.export_obj(R.MODELS/"bl_rail_pair_portal_12.obj",out,vertical_origin=1.5,generator=GEN)
        for a in range(4):
            for b in range(4):
                if a+b==0:continue
                active=paths(first,second,a,b)
                for x,z in C.LEGS:
                    if rotate:x,z=-z,x
                    for dx in (-.081,.081):
                        for dz in (-.081,.081):
                            assert min(v.distance(x+dx,z+dz) for v in active.values())>.57, (mask,a,b)
                mesh=C.wire(mask,active)
                C.export_contact(R.MODELS/f"bl_rail_pair_contact_{mask}_{a}_{b}.obj",mesh,GEN)
                if (a,b) in {(1,2),(3,3)}:
                    preview.append((f"Independent paired contact {mask}_{a}_{b}",C.join(p,mesh)))
    W.author(preview,"rail_paired_wire.blend")

if __name__=="__main__":
    main()
