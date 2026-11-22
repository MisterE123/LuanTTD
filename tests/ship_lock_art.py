#!/usr/bin/env python3
"""Validate the native stepped chamber, door states and clear ferry gauge."""
from pathlib import Path
from math import isclose
import struct

from ship_facility_art import read, points, rim, ray

ROOT=Path(__file__).resolve().parents[1]
DIRECTIONS=((-1,0),(0,1),(1,0),(0,-1))
TARGET_GROUPS=("Deep_structural_retaining_walls","Dressed_retaining_masonry_quoin",
               "Quarried_coping_slab","Joined_quay_rails")
EPS=2e-6


def compare_seam(a,b,d,A,B):
    for n in TARGET_GROUPS:
        p={(x,round(h+A,6)) for x,h in rim(a,(n,),1,d)}
        q={(x,round(h+B,6)) for x,h in rim(b,(n,),-1,d)}
        assert p and p==q,(n,p,q)


def main():
    atlas=ROOT/"mods/bayline/textures/bl_ship_lock_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24])==(512,64)
    ferry=points(read("harbor_ferry",True))
    ship_beam=max(abs(x) for x,z,h in ferry)
    ship_half=max(abs(z) for x,z,h in ferry)
    assert ship_beam<.383 and ship_half<.910
    n_vertical=0
    for d,(dx,dz) in enumerate(DIRECTIONS):
        lo,mid,hi=(read(f"ship_lock_{n}_{d}") for n in ("lower","middle","upper"))
        compare_seam(lo,mid,(dx,dz),0,0)
        compare_seam(mid,hi,(dx,dz),0,1)
        for key,model,sign in (("lower",lo,1),("upper",hi,-1)):
            w=points(model,(f"Fixed_{key}_reach_water",))
            assert all(abs(h)<EPS for x,z,h in w)
            assert isclose(max(sign*(x*dx+z*dz) for x,z,h in w),.885,abs_tol=EPS)
            assert isclose(min(sign*(x*dx+z*dz) for x,z,h in w),-1,abs_tol=EPS)
        bank=points(mid,("Exact_graded_outer_grass_banks",))
        assert {round(h,6) for x,z,h in bank}=={0.,1.}
        assert all(isclose(h,(x*dx+z*dz+1)/2,abs_tol=EPS) for x,z,h in bank)
        assert not any("water" in key.lower() for key in mid)
        # Exterior masonry ends are solid, and the decorative stone
        # faces stand off the flat backing so the surfaces cannot fight.
        for model,ext in ((lo,-1),(hi,1)):
            assert sum(all(abs(dx*x+dz*z-ext)<EPS for x,z,h in f)
                       for f,_ in model["Deep_structural_retaining_walls"])>=4
        for model in (lo,mid,hi):
            solid=points(model,("Deep_structural_retaining_walls",))
            accent=points(model,("Staggered_lock_face_masonry_blocks",))
            transverse=lambda p:abs(p[1] if dx else p[0])
            assert min(map(transverse,solid))-min(map(transverse,accent))>.003
        # Entire native hull height band clears the stone throughout the
        # low-to-high movement. The root may choose any water level here.
        axis=0 if dx else 1
        for model,offset in ((lo,0),(mid,0),(hi,1)):
            for x in (-.576,-ship_beam,-.17,0,.17,ship_beam,.576):
                for y in (-.217,-.183,.063,.301,.832,1.019,1.310,1.914):
                    assert not ray(model,axis,x,y-offset,-1.001,1.001),(d,offset,x,y)
                    n_vertical+=1
    water=points(read("ship_lock_chamber_water",True))
    assert {round(h,6) for x,z,h in water}=={0}
    assert isclose(max(abs(x) for x,z,h in water),.604,abs_tol=EPS)
    assert isclose(max(abs(z) for x,z,h in water),1.115,abs_tol=EPS)
    for key,anchor in (("lower",-1.115),("upper",1.115)):
        opened=read(f"ship_lock_gate_{key}_open",True)
        closed=read(f"ship_lock_gate_{key}_closed",True)
        for x in (-.56,-ship_beam,-.17,0,.17,ship_beam,.56):
            for h in (-.200,.112,.589,.941,1.101):
                assert not ray(opened,1,x,h,-1.,1.),(key,x,h)
                assert ray(closed,1,x,h,-1.,1.),(key,x,h)
        direction=1 if key=="upper" else -1
        assert min(direction*(z+anchor) for x,z,h in points(closed))>ship_half+.024
    print(f"PASS: 12 native orientations, eight exact modular wall joins, two phase water datums, {n_vertical} clear hull rays, 4 real gate poses")


if __name__=="__main__":
    main()
