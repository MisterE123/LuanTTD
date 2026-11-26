#!/usr/bin/env python3
"""Original native steelwork at the four source straight-edge points."""
from copy import deepcopy
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_rail_catenary_art as W

R=W.R
# Original elrail_data.h PCP and PPP pixel coordinates, mapped to 2 nodes.
CASES=((0,12,0,8),(12,16,8,16),(16,4,16,8),(4,0,8,0))

def model(px,pz,cx,cz):
    foot=((px-8)/8,(pz-8)/8)
    contact=((cx-8)/8,(cz-8)/8)
    x,z=foot
    a,b=contact
    m=R.Mesh(R.terrain_height(0))
    W.B(m,"Cast beveled pier","Foundation dark mortar edge",x,z,.144,.144,0,.058,.019,"Foundation rough granite")
    W.B(m,"Hot rolled structural upright","Braced period blue-grey steel mast",x,z,.029,.047,.058,1.189,.004)
    for xx in (x-.018,x+.018):
        W.B(m,"Two machined flanges","Satin warm galvanized beam edge",xx,z,.012,.064,.078,1.205,.003)
    W.bar(m,"Bolted swing support","Braced period blue-grey steel mast",(x,z,1.126),(a,b,1.059),.024)
    W.bar(m,"Triangular support brace","Mast steel shadow tension flange",
          (x,z,.832),(.41*x+.59*a,.41*z+.59*b,1.085),.012)
    W.D(m,"Porcelain shoe hanger","Porcelain warm bleached insulator",(a,b,0),.012,"h",1.023,1.067,10)
    W.bar(m,"Rigid mounting clip","Raised copper end clamps",(a,b,1.026),(a,b,W.WIRE+.005),.006)
    return m

def main():
    authored=[]
    for edge in range(4):
        name=f"bl_rail_edge_pylon_{edge}"
        p=model(*CASES[edge])
        authored.append((name,p))
        export=deepcopy(p)
        xoff,zoff=(1,0) if edge<2 else (0,1)
        for key,row in export.vertices.items():
            export.vertices[key]=[(x-xoff,z-zoff,y) for x,z,y in row]
        R.export_obj(R.MODELS/(name+".obj"),export,vertical_origin=1.5,generator="build_rail_edge_pylons.py")
    W.author(authored,"rail_edge_pylons.blend")

if __name__=="__main__":
    main()
