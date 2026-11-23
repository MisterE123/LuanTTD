#!/usr/bin/env python3
"""Cross-check RC1 stock Dash, original mesh envelope, 4 axles, pickups, and pair clearances."""
from argparse import ArgumentParser
from pathlib import Path
import re
import struct

from chaney_jubilee_art import tread_clearance
from manley_morel_art import pair
from rail_span_art import along_ray,load
from rail_wagon_art import mesh

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_dash"
AXLES=(-.264,-.194,.189,.256)
EPS=2e-6

def test(source):
    if source:
        engines=source.read_text()
        assert re.search(r"MM\(\s*23376,\s*20,\s*15,\s*35,\s*CT_PASSENGERS\s*,\s*LandscapeTypes\(\{T\s*\}\)\),\s*//\s*12 'Dash'",engines)
        assert re.search(r"RVI\(\s*10,\s*M,\s*14,\s*120,\s*700,\s*38,\s*70,\s*RC_D,\s*40,\s*R,\s*D\),\s*//\s*12 'Dash'",engines)
    m=mesh(NAME)
    assert {"Separate_cab_panes_with_narrow_centre_mullions","Pressed_warm-red_sliding_door_leaves",
            "Shallow_HVAC_cowls_above_saloon","Spoked_dish_wheel_face"}<=m.keys()
    front=m["Separate_cab_panes_with_narrow_centre_mullions"]
    assert all(z<-.429 for _,z,_ in front),front
    points={(round(x,4),round(h,4)) for poly in m.values() for x,_,h in poly}
    assert max(h for _,h in points)<.563
    assert max(abs(x) for x,_ in points)<.248
    couplers=m["Coupler_knuckles"]
    assert min(z for _,z,_ in couplers)==-.499 and max(z for _,z,_ in couplers)==.499
    assert abs((min(h for _,_,h in couplers)+max(h for _,_,h in couplers))/2-.157)<EPS
    contacts=[]
    for side,sign in (("L",-1),("R",1)):
        t=m["Rolling_tread_Dash_"+side]
        assert abs(min(h for _,_,h in t))<EPS
        assert {round(z,6) for _,z,h in t if abs(h)<EPS}==set(AXLES)
        for z0 in AXLES:
            xs=[x for x,z,h in t if abs(z-z0)<EPS and abs(h)<EPS]
            assert min(xs)<sign*.212<max(xs)
            contacts.append((sign,z0,min(xs),max(xs)))
    assert abs(min(h for _,_,h in m["Inboard_Dash_railhead_flange"])+.009)<EPS
    assert len(contacts)==8
    portal=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    for x,h in points:
        for outside in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(portal,2,x,outside))
    assert (ROOT/"art"/f"{NAME}.blend").stat().st_size>150_000
    atlas=ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}.png"
    w,h=struct.unpack_from(">II",atlas.read_bytes(),16)
    assert w%8==0 and 120<w<512 and h==8
    print(f"STOCK_DASH_ART_PASS: #12, {len(contacts)} contacts, {tread_clearance(contacts)} rail overlaps, {pair(m)} stock pair orientations, {3*len(points)} portal checks.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines",type=Path)
    test(p.parse_args().upstream_engines)
