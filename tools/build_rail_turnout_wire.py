#!/usr/bin/env python3
"""Original modular 3D overhead supports for RC1 shared-edge turnouts."""
from math import pi, sin
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_rail_catenary_art as W

R = W.R
MASKS = (5, 6, 9, 10, 17, 18, 20, 24, 33, 34, 36, 40)

def build(mask):
    pieces = [R.TrackPath(i) for i in range(6) if mask & (1 << i)]
    mesh = R.Mesh(R.terrain_height(0))
    overlap, = {pieces[0].a, pieces[0].b} & {pieces[1].a, pieces[1].b}
    for i, path in enumerate(pieces):
        # A shared contact section starts at the same surveyed point.
        # The collector wire fans away at the same first few substeps as
        # the underlying track geometry, rather than a fake straight lead.
        ends = path.a == overlap
        distance = lambda t: t if ends else 1 - t
        W.cable(mesh, path, f"Route {i+1} copper contact wire", W.contact, .009, .011,
                "Weathered copper contact underside", "Glancing contact edge")
        W.cable(mesh, path, f"Route {i+1} messenger", W.messenger, .008, .008,
                "Messenger cable charcoal")
        for j in (.30, .58, .81):
            if distance(j) < .18:
                continue
            x,z,*_ = path.sample(j)
            W.bar(mesh, f"Route {i+1} dropper", "Dropper link tempered steel",
                  (x,z,W.WIRE+.006), (x,z,W.messenger(j)+.004), .0047)
    # Choose one verifiably spare quadrant for the grounded support,
    # never through the track, ballast edge or the next door tile.
    grid = (-.78, 0, .78)
    foot = max(((x,z) for x in grid for z in grid), key=lambda v:min(p.distance(*v) for p in pieces))
    separation = min(p.distance(*foot) for p in pieces)
    assert separation > .39, (mask,foot,separation)
    x,z = foot
    W.B(mesh,"Chamfered turnout mast foot","Foundation dark mortar edge",x,z,.15,.15,0,.055,.018,"Foundation rough granite")
    W.B(mesh,"Riveted tapered mast","Braced period blue-grey steel mast",x,z,.048,.059,.05,1.25,.009)
    for xx in (x-.022,x+.022):
        W.B(mesh,"Flanged steel reinforcement","Satin warm galvanized beam edge",xx,z,.009,.076,.073,1.224,.002)
    for i,path in enumerate(pieces):
        cx,cz,*_ = path.sample(.5)
        # Stagger the top brackets slightly; share one ground footing.
        h = 1.172-i*.045
        W.bar(mesh,"Cantilever registration arm","Braced period blue-grey steel mast",(x,z,h),(cx,cz,1.058),.018)
        W.bar(mesh,"Triangular lower arm brace","Mast steel shadow tension flange",
              (x,z,h-.23),(.44*x+.56*cx,.44*z+.56*cz,1.09),.009)
        W.D(mesh,"Porcelain hanger","Porcelain warm bleached insulator",(cx,cz,0),.012,"h",1.020,1.060,9)
        W.bar(mesh,"Suspended wire clip","Raised copper end clamps",(cx,cz,1.032),(cx,cz,W.WIRE+.010),.007)
    return mesh

def main():
    models=[]
    for mask in MASKS:
        name=f"bl_rail_turnout_catenary_{mask}"
        model=build(mask)
        R.export_obj(R.MODELS/(name+".obj"),model,vertical_origin=1.5,generator="build_rail_turnout_wire.py")
        models.append((name,model))
    W.author(models,"rail_turnout_wire.blend")

if __name__ == "__main__":
    main()
