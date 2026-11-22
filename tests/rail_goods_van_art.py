#!/usr/bin/env python3
"""Check original #32 sprite identity, bowed roof, closed doors and rail fit."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from manley_morel_art import pair
from rail_oil_tanker_art import coupled, wheel_contact
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from ship_facility_art import read, ray

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_goods_van"


def tables(args):
    if args.upstream_engines:
        t=Path(args.upstream_engines).read_text()
        assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_GOODS\s*,\s*T\|A\|S\s*\),\s*//\s*32 Goods Van",t)
        assert re.search(r"RVI\(\s*38,\s*W,\s*190,\s*0,\s*0,\s*21,\s*0,\s*RC_W,\s*25,\s*R,\s*A\),\s*//\s*32 Goods Van",t)
    if args.upstream_train_sprites:
        t=Path(args.upstream_train_sprites).read_text()
        def cell(n):
            v=re.search(rf"{n}\[\]\s*=\s*\{{(.*?)\}};",t,re.S)
            return [int(j,0) for j in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b",v[1])][38]
        assert (cell("_engine_sprite_base"),cell("_engine_sprite_and"),cell("_engine_sprite_add"),
                cell("_wagon_full_adder"))==(2753,3,0,0)
    if args.opengfx_wagons:
        t=Path(args.opengfx_wagons).read_text()
        assert re.search(r'spr2753\(2753, "sprites/png/trains/temperate_railwagons_28px.png"\).*?\(\s*6,\s*79\)',t)


def verify(args):
    tables(args)
    m=mesh(NAME)
    g=read(NAME,True)
    top="Continuous_physically_arched_cured-cloth_roof"
    door="Actual_separately_milled_vertical_timber_loading_door_boards"
    wall="Individual_painted_sealed_horizontal_side_planks"
    formed="Horizontal_formed_steel_end_corrugation_channels"
    assert len(g[top])>=220 and len(g[door])>=784 and len(g[wall])>=1120
    assert len(g[formed])>300
    assert "True_shaded_underside_of_bowed_roof_boards" in g
    assert "Deep_proud_handle_and_independent_door_draw-latch_shaft" in g
    assert "Row_of_individual_punched_side_rivets" in g
    for z in (-.332,-.212,-.084,.036,.126,.250,.318):
        tris=[f for f,_ in g[top]]
        h0=min(along_ray(tris,2,0,z))
        shoulder=min(along_ray(tris,2,.180,z))
        assert .570<h0<.573 and .523<shoulder<.558
        assert h0-shoulder>.024
    for s in (-1,1):
        assert all(ray(g,0,z,.38,*sorted((s*.205,s*.245))) for z in (-.080,-.018,.022,.073))
    for z in (-.412,.412):
        assert all(not ray(g,0,z,h,.21,.26) for h in (.285,.418))
    p=[v for pts in m.values() for v in pts]
    assert max(abs(x) for x,z,h in p)<.259
    assert max(abs(z) for n,pts in m.items() if n!="Coupler_knuckles" for x,z,h in pts)<.493
    q=m["Coupler_knuckles"]
    assert any(abs(z-.499)<1e-6 for x,z,h in q) and any(abs(z+.499)<1e-6 for x,z,h in q)
    bore=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    xy={(round(x,4),round(h,4)) for x,z,h in p}
    for x,h in xy:
        for z in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(bore,2,x,z))
    rail=wheel_contact(m)
    c,contacts=coupled(m)
    pair_count=pair(m)
    asset=ROOT/"mods/luanttd_core"
    out=BytesIO()
    with ZipFile(out,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for f in (asset/"models"/f"bl_{NAME}.obj",asset/"textures"/f"bl_{NAME}.png"):
            z.write(f,f.name)
    assert struct.unpack_from(">II",f.read_bytes(),16)==(272,8)
    assert (ROOT/"art"/f"{NAME}.blend").stat().st_size>130_000
    print(f"RAIL_GOODS_VAN_ART_PASS #32/image38/25 crates, four treads / {rail:,} true rail overlaps; "+
          f"{c+pair_count:,} coupled poses ({contacts} cosmetic buffer grazes only); {len(xy)*3:,} portal samples; "+
          f"{out.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-train-sprites")
    p.add_argument("--opengfx-wagons")
    verify(p.parse_args())
