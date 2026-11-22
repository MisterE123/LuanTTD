#!/usr/bin/env python3
"""Stock footprint and source roles, runtime mesh format, and loading clearance."""
from argparse import ArgumentParser
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import re
import struct

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"mods/luanttd_core/models"
T=ROOT/"mods/luanttd_core/textures"
LAYOUTS={
    "oil_well":{(0,0):29,(1,0):29,(2,0):29,(0,1):29,(0,2):29},
    "oil_refinery":{(0,0):20,(0,1):21,(0,2):22,(0,3):21,(1,0):20,(1,1):19,(1,2):22,
                (1,3):20,(2,1):18,(2,2):18,(2,3):18,(3,2):18,(3,3):18,(2,0):23,(3,1):23},
}
TILES={
    18:("bunded_white_stock_tank_welded_cylindrical_shell","bunded_white_stock_tank_draw_manifold"),
    19:("tall_fractionating_tower_ring_access_platforms","colored_distillation_fraction_bands"),
    20:("true_open_unloading_approach_slab","flush_inspection_grate_slots",
        "curve","oxidized_igniter_nozzle","raised_OIL_label"),
    21:("open-frame_exchanger_building_rust_red_I-beam","horizontal_finned_exchanger_barrel"),
    22:("raised_vapor_reservoir_and_attached_pipes_cast_four-legged","rounded_stirred_receiver"),
    23:("low_pump_controls_and_passenger_staff_building_lighted_glass","large_valve_operator_door"),
    29:("recognizable_curved_solid_horsehead","split_linked_pitman_beam_rods","eccentric_crank_bar",
        "actual_bridle_polished_wire_ropes","rounded_wet_receiving_tank"),
}
IMG={18:0x820,19:0x823,20:0x826,21:0x829,22:0x82c,23:0x82f,29:0x87e}


def upstream(build,art):
    if build:
        text=Path(build).read_text()
        for k,v in LAYOUTS.items():
            group=re.search(rf"_tile_table_{k}_0\s*\{{([^}}]+)\}}",text)[1]
            assert {(int(a),int(b)):int(n) for a,b,n in re.findall(r"MK\((\d+), (\d+), (\d+)\)",group)}==v
        group=text.split("/* Oil refinery */",1)[1].split("/* Oil Rig */",1)[0]
        cargo=re.findall(r"^\s*MT\((.*)\)",group,re.M)
        assert len(cargo)==6
        assert [j+18 for j,s in enumerate(cargo) if "CT_OIL" in s]==[20]
        assert [j+18 for j,s in enumerate(cargo) if "CT_PASSENGERS" in s]==[23]
    if art:
        group=Path(art).read_text().split("_industry_draw_tile_data",1)[1]
        rows=re.findall(r"^\s*M\((.*)\),",group,re.M)
        for k,id_ in IMG.items():
            assert int(rows[4*k+3].split(",")[2].split()[0],16)==id_


def bbox(points):
    a,b,c=zip(*points)
    return (min(a),max(a),min(b),max(b),min(c),max(c))


def tile(path,gfx,material_count,receive_sign=None):
    data=path.read_text().splitlines()
    assert f"GFX {gfx}; original Blender art" in data[0]
    groups=set();uv=[];norm=[];verts=[];count=0;name="?"
    for row in data[1:]:
        tag,*values=row.split()
        if tag=="o":
            name=values[0];groups.add(name)
        elif tag=="v":
            x,y,z=map(float,values)
            assert -.500001<=-x<=1.500001 and -.500001<=z<=1.500001
            assert -.500002<=y<=2.3,(path,name,x,y,z)
            verts.append((-x,z,y+.5))
        elif tag=="vt":
            u,v=map(float,values);uv.append(u)
            assert abs(u-(len(uv)-.5)/material_count)<6e-7 and v==.5
        elif tag=="vn":
            norm.append(values)
            assert abs(sum(float(w)**2 for w in values)-1)<3.1e-5
        elif tag=="f":
            refs=[tuple(map(int,r.split("/"))) for r in values]
            count+=1
            assert len(refs)>=3
            assert all(0<a<=len(verts) and 0<b<=len(uv) and 0<c<=len(norm) for a,b,c in refs)
            if receive_sign:
                # A quarter-node of free width either side of the center
                # for the actual Witcombe tanker (over twice its half-width).
                # Conservative face-AABB sweep; no overhead intersections.
                lo,hi,za,zb,dn,up=bbox([verts[a-1] for a,b,c in refs])
                zs,ze=(-.50001,.95) if receive_sign<0 else (.06,1.50001)
                assert hi<.168 or lo>.714 or za>ze or zb<zs or up<.034 or dn>.433,(path,name,(lo,hi,za,zb,dn,up))
    assert count>300 and len(uv)==material_count
    required=TILES[gfx]
    assert all(any(k.lower() in g.lower() for g in groups) for k in required),(path,required,sorted(groups))
    return count


def test(opts):
    upstream(opts.upstream_layout,opts.upstream_drawing)
    paths=[]
    for k,v in LAYOUTS.items():
        atlas=T/f"bl_industry_{k}_atlas.png";raw=atlas.read_bytes()
        assert raw[:8]==b"\x89PNG\r\n\x1a\n"
        w,h=struct.unpack_from(">II",raw,16)
        assert w%8==0 and h==8
        fns=set(M.glob(f"bl_industry_{k}_?_?.obj"))
        assert fns=={M/f"bl_industry_{k}_{x}_{z}.obj" for x,z in v}
        rows=0
        for (x,z),gfx in v.items():
            rows+=tile(M/f"bl_industry_{k}_{x}_{z}.obj",gfx,w//8,
                       ((1 if z>0 else -1) if gfx==20 else None))
        source=ROOT/"art"/f"stock_{k}.blend"
        assert source.stat().st_size>130000
        paths.extend([atlas,*sorted(fns)])
        print(f"Stock {k}: {len(fns)} occupied tiles, {rows:,} faces with validated UVs, exact stock GFX roles.")
    mem=BytesIO()
    with ZipFile(mem,"w",compression=ZIP_DEFLATED,compresslevel=9) as z:
        for p in paths:z.write(p,p.name)
    print(f"STOCK_OIL_ART_PASS: five well pads, three swept truck lanes, exact stock hole, {len(mem.getvalue())/1024:.1f} KiB compressed.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-layout")
    p.add_argument("--upstream-drawing")
    test(p.parse_args())
