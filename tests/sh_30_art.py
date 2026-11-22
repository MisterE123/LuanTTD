#!/usr/bin/env python3
"""Verify pinned SH30 ID, wheel/coach fit, and true pantograph wire contact."""
from argparse import ArgumentParser
from io import BytesIO
from math import sqrt
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from chaney_jubilee_art import coupling, tread_clearance
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from ship_facility_art import read

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_sh_30"
EPS=2e-6
CONTACT=.784


def tables(a, sh=30):
    assert sh in (30,40)
    if a.upstream_engines:
        e=Path(a.upstream_engines).read_text()
        if sh==40:
            assert re.search(r"MT\(\s*19359,\s*20,\s*23,\s*80,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*24 SH '40'",e)
            assert re.search(r"RVI\(\s*20,\s*G,\s*30,\s*176,\s*5000,\s*82,\s*205,\s*RC_E,\s*0,\s*C,\s*E\),\s*//\s*24 SH '40'",e)
        assert re.search(r"MT\(\s*16437,\s*20,\s*23,\s*30,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*23 SH '30'",e)
        assert re.search(r"RVI\(\s*20,\s*G,\s*26,\s*160,\s*3600,\s*84,\s*180,\s*RC_E,\s*0,\s*C,\s*E\),\s*//\s*23 SH '30'",e)
        assert "#define G RAILVEH_SINGLEHEAD" in e
    if a.upstream_train_sprites:
        t=Path(a.upstream_train_sprites).read_text()
        arr=re.search(r"_engine_sprite_base\[\]\s*=\s*{(.*?)};",t,re.S)[1]
        assert int(re.findall(r"0x[0-9A-Fa-f]+",arr)[20],0)==2937
    if a.opengfx_trains:
        t=Path(a.opengfx_trains).read_text()
        assert re.search(r'spr2937\(2937, "sprites/png/trains/temperate_engines_28px.png"\).*?\(111, 180\)',t)


def verify(a):
    sh=a.variant
    tables(a,sh)
    name=f"rail_sh_{sh}"
    m=mesh(name)
    if sh==40:
        legacy=mesh(NAME)
        removed=("Period_rounded_lower_cab_center_company_plate","Original_narrow_cream_fleet_plate_characters",
                 "Inset_contrasting_small_original_SH30_side_number_plate","Original_cream_miniature_square_AL6_stencil_strokes")
        assert all(k in legacy and k not in m for k in removed)
        # No dimensional drift on any reused original class component.
        matched={k for k in legacy if k not in removed}
        assert all(legacy[k]==m[k] for k in matched)
        new=set(m)-matched
        panel="Original_raised_SH40_fleet_identity_panel_on_each_side"
        letters=[f"Original_raised_SH40_badge_letter_{ch}" for ch in "SH40"]
        assert new=={panel,*letters}
        for sign in (-1,1):
            # Renderer mirrors OBJ X—read glyph order in native world coords.
            widths=[]
            for label in letters:
                a0=[sign*z for x,z,h in m[label] if x*sign>0]
                assert a0 and max(a0)-min(a0)>.014
                widths.append((min(a0),max(a0)))
            assert all(w[1]<v[0] for w,v in zip(widths,widths[1:]))
        old_atlas=(ROOT/"mods/bayline/textures/bl_rail_sh_30.png").read_bytes()
        assert old_atlas!=(ROOT/"mods/bayline/textures/bl_rail_sh_40.png").read_bytes()
    required=("One_distinctive_near-upright_faceted_cab_face_each_end","Two_bright_recessed_yellow_warning_faces",
        "Long_hood_dark_slatted_cooler_bank","Four_pairs_of_independent_resilient_wheel_discs",
        "Two_independent_B0-B0_cast_electric_bogie_sideframes","Genuine_turned_stacked_roof_ceramic_standoffs")
    assert set(required)<=m.keys()
    assert len(m[required[3]])>200
    assert len(m["Two_inset_panoramic_rectangular_cab_panes_on_each_end"])==16
    points=[p for vals in m.values() for p in vals]
    assert max(abs(x) for x,z,h in points)<.261
    assert max(abs(z) for key,vals in m.items() if key!="Coupler_knuckles" for x,z,h in vals)<.492
    assert abs(max(h for x,z,h in points)-CONTACT)<EPS
    shoe="Transverse_working_contact_shoe,_level_at_the_specified_wire"
    assert len(m[shoe])>=16
    assert abs(max(x for x,z,h in m[shoe])-.083)<EPS
    assert abs(min(x for x,z,h in m[shoe])+.083)<EPS
    assert abs(min(h for x,z,h in m[shoe])-.775)<EPS
    shoe_geometry=[f for f,_ in read(name,True)[shoe]]
    # Real bar contact from an overhead ray, not merely a declared visual
    # offset. Track line stays within the shoe even on radius-one turns.
    for z in (.026,.031,.036):
        for zigzag in (-.022,0,.022):
            for k in (-1,1):
                ra=1+zigzag
                x=k*(sqrt(ra*ra-z*z)-1)
                assert abs(max(along_ray(shoe_geometry,2,x,z))-CONTACT)<EPS
    wire_local_at_node=CONTACT+.614-1
    assert abs(wire_local_at_node-.398)<EPS
    contacts=[]
    for sign,c in ((-1,"L"),(1,"R")):
        v=m["Rolling_tread_SH30_"+c]
        assert min(h for x,z,h in v)==0
        assert {round(z,6) for x,z,h in v if abs(h)<EPS}=={-.292,-.214,.214,.292}
        for a0 in (-.292,-.214,.214,.292):
            xx=[x for x,z,h in v if abs(z-a0)<EPS and abs(h)<EPS]
            assert min(xx)<sign*.212<max(xx)
            contacts.append((sign,a0,min(xx),max(xx)))
    assert abs(min(h for x,z,h in m["True_inward_SH30_flange_below_contact_plane"])+.009)<EPS
    treads=tread_clearance(contacts)
    poses,close=coupling(m)
    bore=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    samples={(round(x,4),round(h,4)) for x,z,h in points}
    for x,h in samples:
        for z in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(bore,2,x,z)),(x,h,z)
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for p in (ROOT/"mods/bayline/models"/f"bl_{name}.obj",ROOT/"mods/bayline/textures"/f"bl_{name}.png"):
            z.write(p,p.name)
    assert struct.unpack_from(">II",p.read_bytes(),16)==(296,8)
    assert (ROOT/"art"/f"{name}.blend").stat().st_size>120_000
    assert b.tell()<160_000
    print(f"SH_{sh}_ART_PASS: exact #{23 if sh==30 else 24}/image20, {treads:,} true rail overlaps, {poses:,} coupled poses ({close} cosmetic buffing only), {3*len(samples):,} tunnel samples, 18 pantograph wire contacts; {b.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--variant",type=int,choices=(30,40),default=30)
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-train-sprites")
    p.add_argument("--opengfx-trains")
    verify(p.parse_args())
