#!/usr/bin/env python3
"""Source identity, roof wells, real tire contact and Floss' exact 1-unit fit."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

import chaney_jubilee_art as shared
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from ship_facility_art import read

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_floss_47"
AXLES=(-.307,-.242,-.174,.174,.242,.307)
EPS=2e-6


def verify(a):
    if a.upstream_engines:
        e=Path(a.upstream_engines).read_text()
        assert re.search(r"MT\(\s*15341,\s*20,\s*22,\s*33,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*15 Floss '47'",e)
        assert re.search(r"RVI\(\s*4,\s*G,\s*18,\s*160,\s*2580,\s*112,\s*140,\s*RC_D,\s*0,\s*R,\s*D\),\s*//\s*15 Floss '47'",e)
        assert re.search(r"#define G RAILVEH_SINGLEHEAD",e)
    m=mesh(NAME)
    def side(n):
        return tuple((max(p[i] for p in m[n]),min(p[i] for p in m[n])) for i in range(3))
    assert tuple(round(z,6) for z in side("Lofted_twin_tapering_Floss_front_hoods")[1])==(.424,-.424)
    assert all(abs(p[1])>.425 for p in m["Real_inserted_dark_cab_windscreen_panes"])
    assert len(m["Nine_angled_individual_radiator_fan_blades"])>=220
    assert len(m["Distinct_profiled_long_cooler_hood_louvres"])>225
    assert len(m["Deep-set_separate_driver_door_shells"])>=16
    required=("Complete_three-axle_bogie_casting_and_bolster","Paired_buffer_sleeves_pressed_from_cast_steel",
              "Four_stacked_boss_edges_of_bogie_helical_springs","Diesel_day_tank_between_bogie_trucks")
    assert set(required)<=m.keys()
    for n in ("Real_inserted_dark_cab_windscreen_panes","Polished_round_buffer_head_face","Nine_angled_individual_radiator_fan_blades"):
        assert all(any(p[1]*k>.014 for p in m[n]) for k in (-1,1))
    # Exact ray tests through real fan openings. Every ray is below the
    # nominal roof top until the fan rim: cast roof must not span the well.
    tris=[f for a in read(NAME,True).values() for f,t in a]
    for z in (-.097,.095):
        for x,q in ((.028,.017),(.029,-.023),(-.028,.031),(-.035,-.022)):
            hit=max(along_ray(tris,2,x,z+q))
            assert .551<hit<.586,(z,x,q,hit)
        for x in (-.077,.077):
            assert .589<max(along_ray(tris,2,x,z+.014))<.596
    wheels=[]
    for side_name,s in (("L",-1),("R",1)):
        t=m["Rolling_tread_Floss_"+side_name]
        assert min(p[2] for p in t)==0
        assert {round(z,6) for x,z,h in t if abs(h)<EPS}==set(AXLES)
        for z0 in AXLES:
            xx=[x for x,z,h in t if abs(z-z0)<EPS and abs(h)<EPS]
            assert min(xx)<s*.212<max(xx)
            wheels.append((s,z0,min(xx),max(xx)))
    f=m["True_inner_Floss_guide_flanges"]
    assert abs(min(h for x,z,h in f)+.009)<EPS
    points=[p for v in m.values() for p in v]
    assert max(abs(x) for x,z,h in points)<=.261
    assert max(abs(z) for n,p in m.items() if n!="Coupler_knuckles" for x,z,h in p)<.492
    assert .597<max(h for x,z,h in points)<.610
    overlap=shared.tread_clearance(wheels)
    phases,exceptions=shared.coupling(m)
    bore=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    portal=set((round(x,4),round(h,4)) for x,z,h in points)
    for x,h in portal:
        for z in (.65,.77,.92):
            roof=min(along_ray(bore,2,x,z))
            assert h+.114-.5+.035<roof,(x,z,h,roof)
    assert (ROOT/"art"/f"{NAME}.blend").stat().st_size>130000
    obj=ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj"
    atlas=ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}.png"
    a=atlas.read_bytes()
    assert a[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",a,16)==(336,8)
    buf=BytesIO()
    with ZipFile(buf,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for p in (obj,atlas): z.write(p,p.name)
    print(f"FLOSS_47_ART_PASS #15/image4, 12 actual tread contacts, {overlap:,} rail overlaps, real roof wells, {phases:,} coupled phases ({exceptions} buffer/knuckle cosmetic contacts only), {len(portal)*3:,} portal samples; {buf.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    verify(p.parse_args())
