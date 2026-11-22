#!/usr/bin/env python3
"""Physical fit and pinned catalog identity for original covered goods lorry."""
import argparse
from math import cos, sin
from pathlib import Path
import re
import struct

from coal_tipper_art import bounds, in_lane, turn_check
from rail_wagon_art import mesh
from road_freight_stop_art import trace, variants, rotate
from small_airport_art import hull, intersects

ROOT=Path(__file__).resolve().parents[1]
B="balogh_goods_truck"
SCALE=.42
EPS=3.e-6


def freight_fits(groups):
    refs=variants()
    allv=[(x*SCALE,z*SCALE) for pts in groups.values() for x,z,h in pts]
    envelope=hull(allv)
    tires={(x*SCALE,z*SCALE) for name,pts in groups.items() if name.startswith("Ground_contact_tyre_")
           for x,z,h in pts if abs(h)<EPS}
    seen=set()
    count=0
    for key,side,x,z,yaw in trace():
        c,s=cos(yaw),sin(yaw)
        place=lambda u,w:(x+u*c-w*s,z+u*s+w*c)
        poly=[place(u,w) for u,w in envelope]
        u,w=zip(*poly)
        xmin,xmax,zmin,zmax=min(u),max(u),min(w),max(w)
        obstacles,apron,turn=refs[key]
        for name,a,b,e,f,o in obstacles:
            if b<xmin or a>xmax or f<zmin or e>zmax:continue
            assert not intersects(poly,o),(key,side,name,x,z,yaw)
        for u,w in tires:
            p=place(u,w)
            px,pz=rotate(*p,-turn)
            if apron:
                if px<=.005 and abs(pz)<=.316:continue
                if px<-.999 or abs(pz)>.999:continue
                assert any(intersects([p],r) for r in apron),(key,side,px,pz)
            else:
                assert abs(pz)<=.317,(key,side,px,pz)
        seen.add((key,side));count+=1
    assert count>5500 and len(seen)==12,(count,seen)
    return count


def verify(engines,rv_source):
    if engines:
        text=Path(engines).read_text()
        assert re.search(r'MR\(\s*5479,\s*20,\s*15,\s*55,\s*CT_GOODS\s*,\s*T\|A\|S\s*\),\s*//\s*138 Balogh Goods Truck',text)
        assert re.search(r'ROV\(\s*5,\s*107,\s*90,\s*SND_19_DEPARTURE_OLD_RV_1,\s*96,\s*14,\s*38,\s*12\),\s*//\s*22 Balogh Goods Truck',text)
    if rv_source:
        text=Path(rv_source).read_text()
        row=re.search(r'_roadveh_full_adder\[\]\s*=\s*{(.*?)};',text,re.S)
        assert row and [int(n) for n in re.findall(r'\b\d+\b',row[1])][5]==0
    assert (ROOT/"art"/(B+".blend")).stat().st_size>100000
    atlas=ROOT/"mods/luanttd_core/textures"/("bl_"+B+"_atlas.png")
    data=atlas.read_bytes()
    assert data[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",data,16)==(312,8)
    groups=mesh(B)
    for side,s in ((-1,"L"),(1,"R")):
        t=groups["Ground_contact_tyre_"+s]
        assert min(h for x,z,h in t)==0
        a,b=min(x for x,z,h in t if abs(h)<EPS),max(x for x,z,h in t if abs(h)<EPS)
        # X tyres both have a modest facing-side crown bias.
        assert abs((a+b)/2-side*.222)<.0011
        assert sorted({round(z,6) for x,z,h in t if abs(h)<EPS})==[-.464,.442]
    # A rounded cloth roof and rear closure, distinct from the cargo tray.
    top=groups["Wrapped_steel_hoop_weathered_canvas_surfaces"]
    assert len(top)>110
    assert min(h for x,z,h in top)<.45 and max(h for x,z,h in top)>.661
    assert "Closed_cargo_curtain_in_real_cloth_folds" in groups
    assert all(z<-.457 for x,z,h in groups["Pressed_double_windscreen_glass"])
    assert all(z<-.70 for x,z,h in groups["Warm_individual_fluted_headlamp_lens"])
    assert all(z>.74 for x,z,h in groups["Tail_ruby_prism_and_nickel_ring"])
    assert max(h for x,z,h in top)>max(h for x,z,h in groups["Rolled_profile_of_pressed_cab_and_rounded_roof_crown"])+.055
    dims=bounds([(x*SCALE,h*SCALE,z*SCALE) for points in groups.values() for x,z,h in points])
    in_lane(*dims)
    turn_check(*dims)
    lo,hi=dims
    poses=freight_fits(groups)
    print(f"BALOGH_GOODS_ART_PASS ID138/RV22/image5 fixed cover, all 4 contacts, {hi[0]-lo[0]:.4f} width, {hi[1]-lo[1]:.4f} height, {hi[2]-lo[2]:.4f} length; both lanes and eased turns, {poses} exact stock freight-stop sweep poses")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-roadveh")
    args=p.parse_args()
    verify(args.upstream_engines,args.upstream_roadveh)
