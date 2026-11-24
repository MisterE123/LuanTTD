#!/usr/bin/env python3
"""All legal RC1 concrete suspension sequences meet at the correct seams."""
from itertools import product
from fast_girder_art import ROOT, TEXTURES, read, profile, flip

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


def check(family, base, bearings, core, skirt, min_len, max_len):
    count=0
    assert (ROOT/f"art/{family}_suspension.blend").stat().st_size>30_000
    for mode,axis in product(("road","rail"),(0,1)):
        stem=f"bl_{mode}_bridge_suspension_{family}"
        d=2 if axis==0 else 1
        other=(d+2)%4
        names=base+(["Running_asphalt","Shoulder_slab"] if mode=="road" else ["Polished_railhead","Rail_foot"])
        pieces={k:read(stem,f"span_{axis}_{k}") for k in END}
        spans={k:[profile(o,d,e,names+["Catenary_cable"]) for e in (-1,1)]
               for k,o in pieces.items()}
        try_head=read(stem,f"head_flat_{d}")
        try_tail=read(stem,f"head_ramp_{other}")
        left=profile(try_head,d,1,names+["Short_approach_cable"])
        left["Catenary_cable"]=left.pop("Short_approach_cable")
        right=flip(profile(try_tail,other,1,names+["Short_approach_cable"]))
        right["Catenary_cable"]=right.pop("Short_approach_cable")
        for length in range(min_len,max_len+1):
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
                assert set(m)-set(under)==bearings and all(m[g]==under[g] for g in under)
                pier=read(stem,f"pier_{axis}_{n}")[core]
                top={(x,z) for f in pier for x,z,y in f if y==.5}
                foot={(x,z) for f in m[skirt] for x,z,y in f if y==-.5}
                assert top==foot
            else:
                assert not (set(m)&bearings)
    print(f"PASS {family} suspension: both axes and transport modes, {count} cable joins across every native RC1 length")


def main():
    check("concrete", BASE, BEARINGS, "Concrete_suspension_core", "Suspension_support_skirt", 2, 10)
    check("steel", ["Riveted_slab_diaphragms","Continuous_steel_deck_joists","Double_rolled_flange",
                    "Bridge_angle_guardbar"], {"Steel_lattice_column_base","Cast_web_seat"},
          "Steel_lattice_core","Steel_lattice_column_base",3,64)
    for mode in ("road","rail"):
        a=TEXTURES/f"bl_{mode}_bridge_suspension_steel.png"
        b=TEXTURES/f"bl_{mode}_bridge_suspension_steel_yellow.png"
        assert a.read_bytes()!=b.read_bytes() and a.read_bytes()[16:24]==b.read_bytes()[16:24]
    print("PASS alternate steel palette uses the same atlas UV dimensions")


if __name__=="__main__":
    main()
