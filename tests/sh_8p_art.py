#!/usr/bin/env python3
"""#10 SH '8P' identity, native rail contact, geometry and fit."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from chaney_jubilee_art import coupling, tread_clearance
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from ship_facility_art import read

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_sh_8p"
AXLES={"leading":(-.321,-.263),"drivers":(-.184,-.057,.070),"trailing":(.155,),
       "tender":(.236,.289,.344)}
EPS=2e-6


def verify(a):
    if a.upstream_engines:
        e=Path(a.upstream_engines).read_text()
        assert re.search(r"MT\(\s*12419,\s*20,\s*23,\s*25,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*10 SH '8P'",e)
        assert re.search(r"RVI\(\s*0,\s*G,\s*22,\s*144,\s*1600,\s*170,\s*130,\s*RC_S,\s*0,\s*R,\s*S\),\s*//\s*10 SH '8P'",e)
        assert re.search(r"#define G RAILVEH_SINGLEHEAD",e)
    if a.upstream_train_sprites:
        t=Path(a.upstream_train_sprites).read_text()
        assert re.search(r"_engine_sprite_base\[\]\s*=\s*\{\s*0x0B59",t)
    if a.opengfx_trains:
        t=Path(a.opengfx_trains).read_text()
        assert re.search(r'spr2905\(2905, "sprites/png/trains/temperate_engines_28px.png"\).*?\(111, 35\)',t)
    m=mesh(NAME)
    required=("Long_standard_8P_tapered_circular_boiler","Grooved_smokebox_cylinder_and_dished_hot_door",
              "Broad_freestanding_curved_8P_smoke_deflector_sheet","Compact_visible_Caprotti_chamber_cover",
              "Fifteen_individually_cast_spokes_on_each_large_driving_wheel",
              "Integrated_but_visibly_separate_8P_tender_frame","Individual_original_fractured_tender_coal_lumps",
              "Rolled_pillars_framing_actual_open_cab_sides")
    assert set(required)<=m.keys()
    wheels=[]
    for key,q in AXLES.items():
        for side,s in (("L",-1),("R",1)):
            values=m[f"Rolling_tread_{key}_{side}"]
            assert min(h for x,z,h in values)==0
            axes={round(z,6) for x,z,h in values if abs(h)<EPS}
            assert axes==set(q)
            for z0 in q:
                x=[x for x,z,h in values if abs(z-z0)<EPS and abs(h)<EPS]
                assert min(x)<s*.212<max(x)
                wheels.append((s,z0,min(x),max(x)))
    assert len(wheels)==18
    v=[p for pts in m.values() for p in pts]
    assert abs(min(h for x,z,h in v)+.009)<EPS
    assert .556<max(h for x,z,h in v)<.570
    assert max(abs(x) for x,z,h in v)<.268
    assert max(abs(z) for k,p in m.items() if k!="Coupler_knuckles" for x,z,h in p)<.492
    # Two genuine chimney apertures rather than blind black discs.
    tri=[f for a in read(NAME,True).values() for f,t in a]
    for z in (-.380,-.343):
        assert max(along_ray(tri,2,0,z))<.520
        assert max(along_ray(tri,2,.0235,z))>.55
    portal=[f for k,f in load("bl_rail_tunnel_portal_1") if k=="Coursed_brick_intrados"]
    xy={(round(x,4),round(h,4)) for x,z,h in v}
    for x,h in xy:
        for q in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(portal,2,x,q))
    wheel=tread_clearance(wheels)
    count,cosmetic=coupling(m)
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for f in (ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj",ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}.png"):
            z.write(f,f.name)
    assert struct.unpack_from(">II",f.read_bytes(),16)==(304,8)
    assert (ROOT/"art"/f"{NAME}.blend").stat().st_size>170_000
    print(f"SH_8P_ART_PASS: 18 wheel contacts, {wheel:,} real rail overlaps, {count:,} coupled clear phases"+
          f" ({cosmetic} cosmetic knuckle/buffer only), {3*len(xy):,} portal samples; {b.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-train-sprites")
    p.add_argument("--opengfx-trains")
    verify(p.parse_args())
