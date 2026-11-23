#!/usr/bin/env python3
"""Verify actual rolling, mounting, and source envelope for stock engine #0."""
import argparse
import math
from pathlib import Path
import re

from rail_span_art import along_ray,load
from rail_wagon_art import mesh

NAME="rail_kirby_paul_tank"
ROOT=Path(__file__).resolve().parents[1]
AXLES=(-.269,-.051,.171)

def close(value,want,tol=3.e-6):
    assert math.isclose(value,want,abs_tol=tol),(value,want)

def check(upstream):
    if upstream:
        txt=Path(upstream).read_text()
        assert re.search(r'MT\(\s*1827,\s*20,\s*15,\s*30,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*0 Kirby Paul Tank',txt)
        assert re.search(r'RVI\(\s*2,\s*G,\s*7,\s*64,\s*300,\s*47,\s*50,\s*RC_S,\s*0,\s*R,\s*S\),\s*//\s*0 Kirby Paul Tank',txt)
    m=mesh(NAME)
    assert all(x in m for x in ("Individual_spoked_driver_castings","Continuous_0-6-0_coupling_rods",
       "Crosshead_main_piston_connecting_rod","Paired_sculpted_side_water_tanks","Arched_zinc_cab_roof",
       "Flared_cast_chimney_and_open_lip","Visible_lumps_in_rear_coal_bunker","Cab_tinted_window_glass"))
    contact=[]
    for side,group in ((-1,"Rolling_tread_L"),(1,"Rolling_tread_R")):
        tread=m[group]
        close(min(h for _,_,h in tread),0)
        lo,hi=min(x for x,_,_ in tread),max(x for x,_,_ in tread)
        close((lo+hi)/2,side*.212)
        assert set(round(z,6) for _,z,h in tread if abs(h)<1.e-6)==set(AXLES)
        for axle in AXLES:
            contact.append((side,axle,lo,hi))
    flange=m["Inner_flange_lip"]
    assert -.010<min(v[2] for v in flange)<-.008
    assert .164<min(abs(v[0]) for v in flange)<max(abs(v[0]) for v in flange)<.182
    couplers=m["Coupler_knuckles"]
    close(max(v[1] for v in couplers),.499)
    close(min(v[1] for v in couplers),-.499)
    close((max(v[2] for v in couplers)+min(v[2] for v in couplers))/2,.157)
    allv=[v for g in m.values() for v in g]
    assert max(abs(x) for x,z,h in allv)<.266
    assert .612<max(h for x,z,h in allv)<.616
    sill=max(h for _,_,h in m["Cab_bottom_rail"])
    lintel=min(h for _,_,h in m["Cab_doorway_reveal"])
    assert lintel-sill>=.291,"the crew opening must clear the street-scale avatar"
    assert max(abs(z) for name,group in m.items() if name!="Coupler_knuckles" for x,z,h in group)<.488
    for wagon in ("rail_passenger_wagon","rail_open_wagon"):
        tail=max(z for _,z,_ in mesh(wagon)["Coupler_knuckles"])
        close(1-.499-tail,.002)

    # Tangent pose on each stock radius-one half-tile curve: at all
    # six tyre bottoms, the true tread still overlaps the .060 rail crown.
    # Repeat both turn hands/directions so offsets cannot favor one side.
    curved=0
    for c in (-1,1):
        for j in range(1,20):
            for side,z,a,b in contact:
                r=1+c*side*.212
                if min(j*math.pi/40,(20-j)*math.pi/40)<math.atan(abs(z)/(r-.025)): continue
                ra,rb=sorted(math.hypot(1+c*x,z) for x in (a,b))
                overlap=min(rb,r+.030)-max(ra,r-.030)
                assert overlap>.006,(c,j,side,z,ra,rb,overlap)
                curved+=1
    # Portal envelope against actual exported vault, independent of static
    # screenshot angle. Largest model height at a given lateral coordinate.
    bore=load("bl_rail_tunnel_portal_1")
    faces=[t for g,t in bore if g=="Coursed_brick_intrados"]
    highs={}
    for x,_,h in allv:
        highs[x]=max(h,highs.get(x,-10))
    for x,h in highs.items():
        for z in (.65,.73,.97):
            hh=min(along_ray(faces,2,x,z))
            assert h+.114-.5+.04<hh,(x,h,z,hh)
    print(f"KIRBY_ART_PASS exact stock length/couplers, all six treads, {curved} curved tread/crown overlaps and real tunnel clearance")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-engines")
    check(p.parse_args().upstream_engines)
