#!/usr/bin/env python3
"""Verify the stock #30 asset, closed hull, real railhead and consist geometry."""
from argparse import ArgumentParser
from collections import Counter
from io import BytesIO
from math import hypot
from pathlib import Path
import re
import struct
from zipfile import ZipFile, ZIP_DEFLATED

from chaney_jubilee_art import planar, projected_groups, tread_clearance
from rail_span_art import along_ray, load
from rail_wagon_art import mesh
from ship_facility_art import read, ray
from small_airport_art import intersects

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_oil_tanker"
OBJ=ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj"
ATLAS=ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}.png"
END1="Sealed_front_dished_end"
END2="Sealed_rear_dished_end"
SHELL="Long_cylindrical_tank_shell_with_dished_shoulders"
EPS=2.e-6


def source(args):
    if args.upstream_engines:
        s=Path(args.upstream_engines).read_text()
        assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_OIL\s*,\s*T\|A\|S\s*\),\s*//\s*30 Oil Tanker",s)
        assert re.search(r"RVI\(\s*36,\s*W,\s*200,\s*0,\s*0,\s*24,\s*0,\s*RC_W,\s*30,\s*R,\s*A\),\s*//\s*30 Oil Tanker",s)
    if args.upstream_train_sprites:
        t=Path(args.upstream_train_sprites).read_text()
        def cell(n):
            v=re.search(rf"{n}\[\]\s*=\s*\{{(.*?)\}};",t,re.S)
            return [int(j,0) for j in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b",v[1])][36]
        assert (cell("_engine_sprite_base"),cell("_engine_sprite_and"),
                cell("_engine_sprite_add"),cell("_wagon_full_adder"))==(2745,3,0,0)


def closed_geometry(m):
    tris=read(NAME,True)
    counts=Counter()
    for a in (SHELL,END1,END2):
        for f,_ in tris[a]:
            for p,q in zip(f,f[1:]+f[:1]):
                counts[(p,q)]+=1
    assert len(counts)==2388,(len(counts),Counter(counts.values()))
    assert all(count==1 and counts[(b,a)]==1 for (a,b),count in counts.items())
    c=m[SHELL]
    assert abs(max(h for x,z,h in c)-.503)<EPS
    assert abs(min(h for x,z,h in c)-.223)<EPS
    assert .393<max(z for x,z,h in c)<.395
    # Rays prove the circle widens through the mid-plane and narrows
    # toward the floor/crown and the dished tips. The gap under the barrel
    # away from mounts stays open, as does the access ladder gap.
    t={k:tris[k] for k in (SHELL,END1,END2)}
    assert ray(t,0,.133,.363,.201,.207)
    assert ray(t,0,.133,.446,.154,.170) and not ray(t,0,.133,.446,.181,.207)
    assert not ray(t,0,.133,.211,.0,.215)
    assert ray(t,1,0,.363,.390,.398)
    name="Visible_independent_non-filling_rung_spans"
    assert name in tris and "Shaped_ladder_stringers_separate_from_closed_tank" in tris
    for k in (-1,1):
        assert any(k*x>.13 for x,z,h in m[name])
    assert "Low_fitted_oil_discharge_manifold" in tris and "Closed_discharge_end_cap" in tris
    assert "Deep_shaped_curved_saddle_knees" in tris
    return len(counts)//2


def wheel_contact(m):
    r=[]
    for s,c in ((-1,"L"),(1,"R")):
        v=m[f"Rolling_tread_oil_{c}"]
        assert min(h for _,_,h in v)==0
        axes={round(z,6) for _,z,h in v if abs(h)<EPS}
        assert axes=={-.235,.235}
        for a in axes:
            x=[x for x,z,h in v if abs(z-a)<EPS and abs(h)<EPS]
            assert min(x)<s*.212<max(x)
            r.append((s,a,min(x),max(x)))
    assert abs(min(h for _,_,h in m["True_native_inward_wheel_guide_flange"])+.009)<EPS
    return tread_clearance(r)


def coupled(m):
    # Both orders: the focal tanker in front of and behind the other stock
    # vehicle, both travel hands and reversal of each longitudinal part.
    modes=("rail_floss_47","rail_ginzu_a4","rail_kirby_paul_tank","rail_coal_wagon_loaded",NAME)
    body=projected_groups(m)
    phases=0
    cosmetic=0
    for label in modes:
        other=mesh(label)
        for n in (m,other):
            k=n["Coupler_knuckles"]
            assert {round(z,3) for x,z,h in k}>={-.499,.499}
            hs=[h for x,z,h in k]
            assert abs((max(hs)+min(hs))/2-.157)<EPS
        row=projected_groups(other)
        for a,b in ((body,row),(row,body)):
            for hand in (-1,1):
                for reverse_a in (False,True):
                    for reverse_b in (False,True):
                        for at_i in range(85):
                            at=-.37+at_i*.033
                            aa=[(n,h,H,planar(p,at,hand,reverse_a)) for n,h,H,p in a]
                            bb=[(n,h,H,planar(p,at-1,hand,reverse_b)) for n,h,H,p in b]
                            seen=False
                            for na,ha,Ha,(x0,x1,z0,z1,p) in aa:
                                for nb,hb,Hb,(u0,u1,v0,v1,q) in bb:
                                    if min(Ha,Hb)-max(ha,hb)<1e-4 or x1<u0 or x0>u1 or z1<v0 or z0>v1:
                                        continue
                                    if intersects(p,q):
                                        pair=na.lower(),nb.lower()
                                        assert ("coupler" in pair[0] and "buffer" in pair[1]) or (
                                            "buffer" in pair[0] and "coupler" in pair[1]),(label,at,hand,na,nb)
                                        seen=True
                            p=planar([(0,-.499 if reverse_a else .499)],at,hand,reverse_a)[4][0]
                            q=planar([(0,.499 if reverse_b else -.499)],at-1,hand,reverse_b)[4][0]
                            assert .0019<hypot(p[0]-q[0],p[1]-q[1])<.141
                            phases+=1
                            cosmetic+=seen
    assert phases==6800
    return phases,cosmetic


def verify(args):
    source(args)
    m=mesh(NAME)
    edges=closed_geometry(m)
    contacts=wheel_contact(m)
    points=[p for row in m.values() for p in row]
    assert max(abs(x) for x,z,h in points)<.26 and .53<max(h for x,z,h in points)<.545
    assert max(abs(z) for n,a in m.items() if n!="Coupler_knuckles" for x,z,h in a)<.492
    bore=[f for name,f in load("bl_rail_tunnel_portal_1") if name=="Coursed_brick_intrados"]
    pairs=set((round(x,4),round(h,4)) for x,z,h in points)
    for x,h in pairs:
        for z in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(bore,2,x,z))
    phases,cosmetic=coupled(m)
    assert (ROOT/"art"/f"{NAME}.blend").stat().st_size>120_000
    a=ATLAS.read_bytes()
    assert a[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",a,16)==(272,8)
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for f in (OBJ,ATLAS):z.write(f,f.name)
    print(f"RAIL_OIL_TANKER_ART_PASS #30/image36/30k L, closed shell {edges:,} oriented welded edges, "+
          f"4 tread contacts and {contacts:,} true railhead overlaps, {phases:,} paired poses "+
          f"({cosmetic} centered knuckle/buffer visual grazes only), {len(pairs)*3:,} portal samples; {b.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-train-sprites")
    verify(p.parse_args())
