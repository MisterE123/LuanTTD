#!/usr/bin/env python3
"""Check standard units, axle gauge, contact patch and stock-length spacing."""
from collections import defaultdict
from math import isclose
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
EPS=1e-6


def mesh(key):
    groups=defaultdict(list)
    for line in (MODELS/f"bl_{key}.obj").read_text().splitlines():
        if line.startswith("o "):
            name=line[2:]
        if line.startswith("v "):
            x,h,z=(float(a)/10 for a in line[2:].split())
            groups[name].append((-x,z,h))
    assert sum(map(len,groups.values()))>1200
    return groups


def check(key,axles):
    g=mesh(key)
    assert {round((min(v[0] for v in g[wheel])+max(v[0] for v in g[wheel]))/2,6)
        for wheel in ("Rolling_tread_L","Rolling_tread_R")}=={-.212,.212}
    for group in ("Rolling_tread_L","Rolling_tread_R"):
        assert min(v[2] for v in g[group])==0
        assert {round(v[1],6) for v in g[group] if abs(v[2])<EPS}==set(axles)
    flange=g["Inner_flange_lip"]
    assert min(v[2] for v in flange)<0
    assert max(abs(v[0]) for v in flange)<.182,"flange under the actual rail crown"
    assert min(abs(v[0]) for v in flange)>.163
    coupling=g["Coupler_knuckles"]
    assert isclose(max(v[1] for v in coupling),.499,abs_tol=EPS)
    assert isclose(min(v[1] for v in coupling),-.499,abs_tol=EPS)
    assert isclose((min(v[2] for v in coupling)+max(v[2] for v in coupling))/2,.157,abs_tol=EPS)
    for name,verts in g.items():
        if name in ("Coupler_knuckles",): continue
        assert max(abs(v[1]) for v in verts)<=.478+EPS,(key,name)
    allv=[v for verts in g.values() for v in verts]
    assert max(abs(v[0]) for v in allv)<.268
    assert max(v[2] for v in allv)<.710
    assert "Recessed_saloon_end_door" in g or "Raised_wagon_side_planks" in g
    if key.endswith("open_wagon"):
        assert "Individual_open-bed_floor_planks" in g
        assert not any(abs(x)<.16 and abs(z)<.32 and h>.251 for x,z,h in allv)
    return .499


def locomotive_longitudinal_envelope(key):
    return max(abs(float(line.split()[-1]))/10 for line in
               (MODELS/f"bl_{key}.obj").read_text().splitlines() if line.startswith("v "))


def main():
    atlas=ROOT/"mods/luanttd_core/textures/bl_rail_wagon_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24])==(35*8,8)
    a=check("rail_passenger_wagon",(-.355,-.239,.239,.355))
    b=check("rail_open_wagon",(-.288,.288))
    assert isclose(1-(a+b),.002,abs_tol=EPS),"gear should meet at stock spacing"
    for locomotive,scale in (("steam",.56),("diesel",.54),("electric",.54)):
        gap=1-a-locomotive_longitudinal_envelope(locomotive)*scale
        assert .018<gap<.04,(locomotive,gap)
    print("PASS: two standard 8-unit wagons, exact .424 treads, rail contact, .002-node drawgear clearance, open bed and three compatible locomotive envelopes")


if __name__=="__main__":
    main()
