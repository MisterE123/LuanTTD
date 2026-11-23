#!/usr/bin/env python3
"""All legal RC1 concrete suspension sequences meet at the correct seams."""
from itertools import product
from fast_girder_art import ROOT, read, profile, flip

END = {"plus":(False,True),"minus":(True,False),"double":(True,True),"clear":(False,False)}
BASE = ["Concrete_deck_diaphragm","Cast_fascia_band","Cast_coping",
        "Low_precast_safety_railing"]
BEARINGS = {"Suspension_support_skirt","Suspension_bearing_ledge"}


def key(n,s):
    if n==1: return "plus"
    if s==1: return "minus"
    if n<s: return "plus" if n%2 else "minus"
    if n>s: return "minus" if s%2 else "plus"
    return "clear" if n%2 else "double"


def main():
    count=0
    assert (ROOT/"art/concrete_suspension.blend").stat().st_size>30_000
    for mode,axis in product(("road","rail"),(0,1)):
        stem=f"bl_{mode}_bridge_suspension_concrete"
        d=2 if axis==0 else 1
        other=(d+2)%4
        names=BASE+(["Running_asphalt","Shoulder_slab"] if mode=="road" else ["Polished_railhead","Rail_foot"])
        pieces={k:read(stem,f"span_{axis}_{k}") for k in END}
        spans={k:[profile(o,d,e,names+["Catenary_cable"]) for e in (-1,1)]
               for k,o in pieces.items()}
        try_head=read(stem,f"head_flat_{d}")
        try_tail=read(stem,f"head_ramp_{other}")
        left=profile(try_head,d,1,names+["Short_approach_cable"])
        left["Catenary_cable"]=left.pop("Short_approach_cable")
        right=flip(profile(try_tail,other,1,names+["Short_approach_cable"]))
        right["Catenary_cable"]=right.pop("Short_approach_cable")
        for length in range(2,11):
            line=[key(i,length+1-i) for i in range(1,length+1)]
            assert left==spans[line[0]][0] and right==spans[line[-1]][1]
            for a,b in zip(line,line[1:]):
                assert spans[a][1]==spans[b][0],(axis,mode,length,a,b)
                assert END[a][1]==END[b][0]
                count+=1
        for n,ends in END.items():
            m=pieces[n]
            if any(ends):
                under=read(stem,f"span_{axis}_{n}_road_clear")
                assert set(m)-set(under)==BEARINGS and all(m[g]==under[g] for g in under)
                pier=read(stem,f"pier_{axis}_{n}")["Concrete_suspension_core"]
                top={(x,z) for f in pier for x,z,y in f if y==.5}
                foot={(x,z) for f in m["Suspension_support_skirt"] for x,z,y in f if y==-.5}
                assert top==foot
            else:
                assert not (set(m)&BEARINGS)
    print(f"PASS concrete suspension: both axes and transport modes, {count} cable joins across every RC1 legal length")


if __name__=="__main__":
    main()
