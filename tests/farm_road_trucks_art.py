#!/usr/bin/env python3
"""Original period farm lorries: stock identity, real bins/vents and lane fit."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from balogh_goods_truck_art import freight_fits
from coal_tipper_art import bounds, in_lane, turn_check
from foster_bus_art import native_sweep, runner
from rail_wagon_art import mesh
from ship_facility_art import read, ray
from small_airport_art import hull
from witcombe_wood_truck_art import data_table

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/bayline/models"
TEXTURES=ROOT/"mods/bayline/textures"
GRAIN="hereford_grain_truck"
LOADED=GRAIN+"_loaded"
VAN="talbott_livestock_van"
S=.42
EPS=1.e-6


def source(e,r,nml):
    if e:
        t=Path(e).read_text()
        assert re.search(r'MR\(\s*5479,\s*20,\s*15,\s*55,\s*CT_LIVESTOCK\s*,\s*T\|A\s*\),\s*//\s*135 Talbott Livestock Van',t)
        assert re.search(r'MR\(\s*5479,\s*20,\s*15,\s*55,\s*MCT_GRAIN_WHEAT_MAIZE\s*,\s*T\|A\|S\s*\),\s*//\s*141 Hereford Grain Truck',t)
        assert re.search(r'ROV\(\s*4,\s*105,\s*90,\s*SND_19_DEPARTURE_OLD_RV_1,\s*96,\s*14,\s*38,\s*12\),\s*//\s*19 Talbott Livestock Van',t)
        assert re.search(r'ROV\(\s*6,\s*114,\s*90,\s*SND_19_DEPARTURE_OLD_RV_1,\s*96,\s*20,\s*38,\s*12\),\s*//\s*25 Hereford Grain Truck',t)
    if r:
        t=Path(r).read_text()
        images=data_table(t,"_roadveh_images")
        steps=data_table(t,"_roadveh_full_adder")
        assert (images[4],steps[4])==(3316,0)
        assert (images[6],steps[6])==(3340,48)
        assert "cargo.StoredCount() >= this->cargo_cap / 2U" in t
    if nml:
        t=Path(nml).read_text()
        for frame,y in ((3316,296),(3340,328),(3388,392)):
            assert re.search(rf'spr{frame}\({frame}, "sprites/png/roadvehicles/vehiclesroad01.png"\)\s*\{{\s*\[338, {y}',t)


def matched_models(e,l):
    prefix=lambda n:(MODELS/f"bl_{n}.obj").read_text()
    # Materials and raw permanent coachwork lines agree through the end
    # of the rear gate: exact origin, normal and UV indexing, not visually
    # approximated bounds between the two models.
    assert prefix(l).startswith(prefix(e))
    a,b=mesh(e),mesh(l)
    assert a.keys()<=b.keys()
    assert len(b.keys()-a.keys())==4
    for key in a:
        assert a[key]==b[key],key
    cargo={p for n in b.keys()-a.keys() for p in b[n]}
    assert min(h for x,z,h in cargo)==.292 and max(h for x,z,h in cargo)>.55
    assert all(-.220<x<.220 and -.150<z<.727 and .291<h<.572 for x,z,h in cargo)
    base=read(GRAIN,True)
    full=read(LOADED,True)
    # The axial down-ray is a physical floor and the empty version does not
    # carry an invisible deck over the bin opening.
    assert not ray(base,1,0,.400,-.148,.710)
    assert ray(full,1,0,.48,-.148,.710)
    return len(cargo)


def vents():
    v=mesh(VAN)
    assert "Physically_bowed_cured_ventilated_van_roof" in v
    assert "Visible_inside_canvas_lining_above_cattle_deck" in v
    m=read(VAN,True)
    n=0
    for h in (.366,.439,.522,.606):
        for z in (.077,.163,.281,.459,.650):
            if not ray(m,0,z,h,.224,.300):n+=1
    assert n>=16,n
    assert ray(m,0,.282,.400,.225,.300),"lattice must have solid boards as well as openings"
    return n


def fit(stem):
    groups=mesh(stem)
    pts=[(x*S,h*S,z*S) for pieces in groups.values() for x,z,h in pieces]
    lo,hi=bounds(pts)
    assert lo[1]==0 and .64<hi[2]-lo[2]<.69
    assert hi[1]<.316
    if stem==VAN:
        assert .301<hi[1]<.312
        assert max(hi[0],-lo[0])<.133
    else:
        in_lane(lo,hi)
    turn_check(lo,hi)
    tire={p for key,t in groups.items() if key.startswith("Ground_contact_tyre") for p in t if abs(p[2])<EPS}
    assert len(tire)==8
    assert {round(z,6) for x,z,h in tire}=={-.454,.435}
    assert all(.18<abs(x)<.26 for x,z,h in tire)
    assert min(z for x,z,h in groups["Warm_fluted_glass_forward_lamp"])<-.76
    assert min(z for x,z,h in groups["Ruby_stop_lamp_in_grease_resistant_ring"])>.75
    footprint=hull((x,z) for x,_,z in pts)
    saved=runner.SAMPLE
    try:
        poses,worst,outside=native_sweep([(x*S,z*S) for x,z,h in tire],footprint)
    finally:
        runner.SAMPLE=saved
    assert outside==0 and worst[0]==0
    return tuple(round(b-a,5) for a,b in zip(lo,hi)),freight_fits(groups),poses


def archive(stems,at):
    buf=BytesIO()
    with ZipFile(buf,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for p in stems:z.write(MODELS/f"bl_{p}.obj",f"bl_{p}.obj")
        z.write(at,at.name)
    return buf.tell()


def main(a):
    source(a.upstream_engines,a.upstream_roadveh,a.opengfx)
    for key in (GRAIN,VAN):
        assert (ROOT/"art"/(key+".blend")).stat().st_size>150_000
    t1=TEXTURES/f"bl_{GRAIN}_atlas.png"
    t2=TEXTURES/f"bl_{VAN}_atlas.png"
    atlas=t1.read_bytes()
    assert atlas==t2.read_bytes() and struct.unpack_from(">II",atlas,16)==(368,8)
    n=matched_models(GRAIN,LOADED)
    c=vents()
    caps=(archive((GRAIN,LOADED),t1),archive((VAN,),t2))
    assert sum(caps)<490*1024,caps
    for key in (GRAIN,LOADED,VAN):
        sizes,freight,curves=fit(key)
        print(f"{key}: {sizes}, {freight} real freight-stop poses, {curves} right-hand road poses")
    print(f"FARM_TRUCK_ART_PASS: {n} independently added real grain vertices, {c} open livestock slit rays, packed {caps[0]}/{caps[1]} bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-roadveh")
    p.add_argument("--opengfx")
    main(p.parse_args())
