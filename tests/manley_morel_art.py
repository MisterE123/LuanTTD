#!/usr/bin/env python3
"""Original physically separate Class 101-inspired #11 shells and their mate."""
from argparse import ArgumentParser
from io import BytesIO
from math import hypot
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from chaney_jubilee_art import planar, projected_groups, tread_clearance
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from small_airport_art import intersects

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_manley_morel"
AXLES=(-.262,-.192,.194,.266)
EPS=2.e-6


def source(a):
    if a.upstream_engines:
        t=Path(a.upstream_engines).read_text()
        assert re.search(r"MM\(\s*13149,\s*20,\s*12,\s*30,\s*CT_PASSENGERS\s*,\s*T\s*\),\s*//\s*11 Manley-Morel DMU",t)
        assert re.search(r"RVI\(\s*8,\s*M,\s*11,\s*112,\s*600,\s*32,\s*85,\s*RC_D,\s*38,\s*R,\s*D\),\s*//\s*11 Manley-Morel DMU",t)
        assert "#define M RAILVEH_MULTIHEAD" in t
    if a.upstream_train_sprites:
        t=Path(a.upstream_train_sprites).read_text()
        arr=re.search(r"_engine_sprite_base\[\]\s*=\s*\{(.*?)\};",t,re.S)[1]
        assert int(re.findall(r"0x[0-9a-fA-F]+",arr)[8],0)==2949
    if a.opengfx_trains:
        t=Path(a.opengfx_trains).read_text()
        assert re.search(r'spr2949\(2949, "sprites/png/trains/temperate_engines_28px.png"\).*?\(111, 151\)',t)


def pair(m):
    parts=projected_groups(m)
    count=0
    for hand in (-1,1):
        for leading in (False,True):
            for i in range(200):
                at=-.48+i*.015
                # Both directions of the nominal stock pair. On the
                # normal stock pose both connected ends are gangways;
                # the reverse pairing adds a clearance guard for the cab.
                a=[(n,h,t,planar(p,at,hand,leading)) for n,h,t,p in parts]
                b=[(n,h,t,planar(p,at-1,hand,not leading)) for n,h,t,p in parts]
                for n,h,t,(x0,x1,z0,z1,p) in a:
                    for N,H,T,(a0,a1,b0,b1,P) in b:
                        if min(t,T)-max(h,H)<1e-4 or x1<a0 or x0>a1 or z1<b0 or z0>b1:
                            continue
                        assert not intersects(p,P),(n,N,at,hand,leading)
                u=planar([(0,-.499 if leading else .499)],at,hand,leading)[4][0]
                v=planar([(0,-.499 if leading else .499)],at-1,hand,not leading)[4][0]
                d=hypot(u[0]-v[0],u[1]-v[1])
                assert .0019<d<.141,(i,at,hand,leading,d)
                count+=1
    return count


def verify(a):
    source(a)
    m=mesh(NAME)
    required=("Three_inset_panoramic_driving_cab_windscreens","Broad_curved_yellow_half_warning_cab_apron",
              "Single_small_deep_inner_vestibule_window","Dark_inner_rubber_gangway_accordion",
              "Period_roof_passenger_compartment_vents","Visible_pressed_underfloor_diesel_engine_pack_each_side",
              "Paired_inset_sliding_top_light_dividers","Real_continuous_paired_railcar_waist_and_header_lining")
    assert set(required)<=m.keys()
    front=m[required[0]]
    assert len(front)==12 and all(z<-.430 for x,z,h in front)
    assert all(z>.423 for x,z,h in m[required[3]])
    assert max(h for p in m.values() for x,z,h in p)<.549
    assert max(abs(x) for p in m.values() for x,z,h in p)<.263
    q=m["Coupler_knuckles"]
    assert any(abs(p[1]-.499)<EPS for p in q) and any(abs(p[1]+.499)<EPS for p in q)
    assert abs((min(v[2] for v in q)+max(v[2] for v in q))/2-.157)<EPS
    wheels=[]
    for side,s in (("L",-1),("R",1)):
        t=m["Rolling_tread_DMU_"+side]
        assert min(h for x,z,h in t)==0
        assert {round(z,6) for x,z,h in t if abs(h)<EPS}==set(AXLES)
        for z0 in AXLES:
            x=[x for x,z,h in t if abs(z-z0)<EPS and abs(h)<EPS]
            assert min(x)<s*.212<max(x)
            wheels.append((s,z0,min(x),max(x)))
    assert abs(min(h for x,z,h in m["True_inner_DMU_railhead_flange"])+.009)<EPS
    points={(round(x,4),round(h,4)) for p in m.values() for x,z,h in p}
    portal=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    for x,h in points:
        for q in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(portal,2,x,q))
    assert (ROOT/"art"/(NAME+".blend")).stat().st_size>150_000
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for f in (ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj",ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}.png"):
            z.write(f,f.name)
    assert struct.unpack_from(">II",f.read_bytes(),16)==(312,8)
    print(f"MANLEY_MOREL_ART_PASS #11, 8 tread contacts per half, {tread_clearance(wheels):,} true rail overlaps, "+
          f"{pair(m):,} clear coupled orientation samples, {3*len(points):,} tunnel points; {b.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-train-sprites")
    p.add_argument("--opengfx-trains")
    verify(p.parse_args())
