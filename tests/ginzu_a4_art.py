#!/usr/bin/env python3
"""Stock #9 Ginzu A4 profile, ground contacts, wagon and track clearances."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

import chaney_jubilee_art as shared
from rail_span_art import along_ray, load
from rail_wagon_art import mesh

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_ginzu_a4"
AXLES={"Pilot_bogie":(-.320,-.255),"Main_driver":(-.172,-.053,.066),
       "Trailing_truck":(.155,),"Tender":(.207,.253,.299,.344)}
EPS=2e-6


def source(p):
    t=Path(p).read_text()
    assert re.search(r"MT\(\s*5479,\s*20,\s*20,\s*30,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*9 Ginzu 'A4'",t)
    assert re.search(r"RVI\(\s*1,\s*G,\s*19,\s*128,\s*1200,\s*162,\s*140,\s*RC_S,\s*0,\s*R,\s*S\),\s*//\s*9 Ginzu 'A4'",t)
    assert re.search(r"#define G RAILVEH_SINGLEHEAD",t)


def centers(groups):
    out=[]
    for key,axles in AXLES.items():
        for side,s in (("L",-1),("R",1)):
            v=groups["Rolling_tread_"+key+"_"+side]
            assert min(h for x,z,h in v)==0
            assert set(round(z,6) for x,z,h in v if abs(h)<EPS)==set(axles)
            for a in axles:
                x=[x for x,z,h in v if abs(z-a)<EPS and abs(h)<EPS]
                assert min(x)<s*.212<max(x)
                out.append((s,a,min(x),max(x)))
    assert len(out)==20
    flanges=groups["True_inward_rail_guiding_wheel_flanges"]
    assert -.009-EPS<min(h for x,z,h in flanges)<-.009+EPS
    assert .168<min(abs(x) for x,z,h in flanges)<max(abs(x) for x,z,h in flanges)<.179
    return out


def verify(args):
    if args.upstream_engines:source(args.upstream_engines)
    m=mesh(NAME)
    must=("Revolved_sheet_metal_A4_shoulder_and_slanted_wedge_smokebox_shroud",
        "Tapered_full-length_true_separate_skirt_sheet_and_cut_edge",
        "Low_double_chimney_real_perforated_smoke_outlet",
        "Fourteen_individual_cast_crimson_A4_driver_spokes",
        "Demarcated_separate_short_A4_steam_tender_drawbar",
        "A4_tender_rolled_blue_separate_outer_side_plate",
        "Rock_coal_lumps_in_tapering_tender_bunker",
        "Deep_aft_cabin_side_glazing_peeking_past_the_raised_gasket")
    assert set(must)<=m.keys(),set(must)-m.keys()
    assert len(m[must[3]])>350
    body=m[must[0]]
    crown=lambda a,b:max(h for x,z,h in body if a<=z<=b)
    assert crown(-.424,-.403)<.36<crown(-.403,-.393)<.46
    assert .500<crown(-.365,-.35)<.550 and .58<crown(-.17,-.15)<.59
    assert all(z> .201-EPS for x,z,h in m[must[5]])
    assert min(z for x,z,h in m["Real_warm_raised_twin_front_lamp_lenses"])<-.418
    assert min(z for x,z,h in m["Exposed_tail_ruby_lens_and_lamp_ring"])>.449
    v=[p for ps in m.values() for p in ps]
    assert max(abs(x) for x,z,h in v)<.268
    assert max(abs(z) for key,p in m.items() if key!="Coupler_knuckles" for x,z,h in p)<.492
    assert max(h for x,z,h in v)<.614 and max(h for x,z,h in v)>.600
    overlap=shared.tread_clearance(centers(m))
    pair,cosmetic=shared.coupling(m)
    bore=[f for name,f in load("bl_rail_tunnel_portal_1") if name=="Coursed_brick_intrados"]
    for x,y in {(round(x,4),round(h,4)) for x,_,h in v}:
        for q in (.65,.77,.92):
            hh=min(along_ray(bore,2,x,q))
            assert y+.114-.5+.035<hh,(x,y,q,hh)
    t=ROOT/"mods/bayline/textures"/("bl_"+NAME+".png")
    obj=ROOT/"mods/bayline/models"/("bl_"+NAME+".obj")
    atlas=t.read_bytes()
    assert atlas[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",atlas,16)==(320,8)
    output=BytesIO()
    with ZipFile(output,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for f in (t,obj):z.write(f,f.name)
    assert (ROOT/"art/rail_ginzu_a4.blend").stat().st_size>150_000
    print(f"GINZU_A4_ART_PASS: 20 tread contacts, {overlap:,} real rail overlaps, {pair:,} "
          f"coupled body-clear curve phases ({cosmetic} only fixed knuckle/buffer cases), "
          f"native portal fit, {output.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    verify(p.parse_args())
