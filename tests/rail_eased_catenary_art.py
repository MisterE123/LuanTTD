#!/usr/bin/env python3
"""Verify the geometry the client loads, not just the catenary filename."""
from math import sqrt
from rail_catenary_art import ENDS, SIDES, SUBSET, WIRE, MESS, EPS, parsed, seam, vertices


def main():
    all_parts={}
    for mask in (4,8,16,32):
        for mode in (1,2,3):
            saved=None
            for pole in (0,1):
                key=f"bl_rail_catenary_eased_{mask}_{mode}_{pole}"
                part,_=parsed(key,1.5)
                if saved:
                    assert part[WIRE]==saved[WIRE] and part[MESS]==saved[MESS]
                else:
                    saved=part
                assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,_ in vertices(part))
                assert bool(pole)==("Chamfered_grounded_masonry_mast_foot" in part)
                for i,edge in enumerate(ENDS[SUBSET.index(mask)]):
                    width_scale=sqrt(2) if mode & (1 << i) else 1.
                    for cable,w,h,d in ((WIRE,.013,.898,.009),(MESS,.010,.997,.008)):
                        expected={(round(a*w*width_scale/2,6),round(y,6))
                                  for a in (-1,1) for y in (h,h+d)}
                        assert seam(part,cable,edge)==expected,(key,edge,seam(part,cable,edge))
                if mode==3:
                    a,b=[SIDES[e] for e in ENDS[SUBSET.index(mask)]]
                    # No stock quarter-circle oscillation survives in the
                    # interior wire, and pole placement never bends it.
                    for x,z,h in vertices(part,(WIRE,)):
                        err=abs((x-a[0])*(b[1]-a[1])-(z-a[1])*(b[0]-a[0]))/sqrt(2)
                        assert abs(err-.0065)<2*EPS,(key,x,z,err)
            all_parts[mask,mode]=saved
    for (a,ma),g in all_parts.items():
        partner={4:8,8:4,16:32,32:16}[a]
        for i,edge in enumerate(ENDS[SUBSET.index(a)]):
            if not ma & (1 << i):
                continue
            other=(edge+2)%4
            for (b,mb),r in all_parts.items():
                if b!=partner or other not in ENDS[SUBSET.index(b)]:
                    continue
                j=ENDS[SUBSET.index(b)].index(other)
                if mb & (1 << j):
                    for cable in (WIRE,MESS):
                        assert seam(g,cable,edge)==seam(r,cable,other)
    print("RAIL_EASED_CATENARY_PASS: 24 meshes, exact shared 3D wire ends, straight interiors, grounded mast/no-mast parity.")


if __name__=="__main__":
    main()
