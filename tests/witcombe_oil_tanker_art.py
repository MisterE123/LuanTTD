#!/usr/bin/env python3
"""Stock identity, true tank geometry, vehicle fit and native wheel contacts."""
import argparse
from collections import Counter
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
NAME="witcombe_oil_tanker"
OBJ=ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj"
ATLAS=ROOT/"mods/luanttd_core/textures"/f"bl_{NAME}_atlas.png"
S=.42


def source(engines,road,open_gfx):
    if engines:
        s = Path(engines).read_text()
        assert re.search(r'MR\(\s*5479,\s*20,\s*15,\s*55,\s*CT_OIL\s*,\s*T\|A\|S\s*\),\s*// 132 Witcombe Oil Tanker',s)
        assert re.search(r'ROV\(\s*3,\s*110,\s*90,\s*SND_19_DEPARTURE_OLD_RV_1,\s*96,\s*21,\s*38,\s*12\),\s*// 16 Witcombe Oil Tanker',s)
    if road:
        s = Path(road).read_text()
        assert data_table(s,"_roadveh_images")[3]==3308
        assert data_table(s,"_roadveh_full_adder")[3]==0
    if open_gfx:
        pnml=Path(open_gfx).read_text()
        assert re.search(r'spr3308\(3308, "sprites/png/roadvehicles/vehiclesroad01.png"\)\s*{\s*\[ 82, 296,',pnml)


def shell():
    """Require every edge shared twice after merging indexed material seams."""
    tank={"Oval_longitudinal_cistern_and_dished_bulkheads","Front_dished_cistern_face","Rear_dished_cistern_face"}
    vertices=[]
    edges=Counter()
    allpoints=set()
    label_points=set()
    for line in OBJ.read_text().splitlines():
        key,fields=line[:2],line[2:].split()
        if key == "o ":
            part=fields[0]
        if key == "v ":
            vertices.append(tuple(map(float,fields)))
        elif key=="f " and part in tank|{"Painted_curved_body_oil_and_fleet_identity"}:
            p=[vertices[int(s.split("/")[0])-1] for s in fields]
            if part in tank:
                allpoints.update(p)
                for a,b in zip(p,p[1:]+p[:1]):
                    edges[tuple(sorted((a,b)))]+=1
            else:
                label_points.update(p)
    assert len(allpoints)==440 and len(edges)>1200
    assert set(edges.values())=={2},Counter(edges.values())
    assert len(label_points)>240
    # Ensure lettering survives both backface culling and the object-engine
    # mirrored conversion by requiring outboard planes on each flank.
    assert min(p[0] for p in label_points)<-2.18
    assert max(p[0] for p in label_points)>2.18
    return len(allpoints),len(edges)


def verify(args):
    source(args.upstream_engines,args.upstream_roadveh,args.opengfx)
    assert (ROOT/"art"/(NAME+".blend")).stat().st_size>140000
    assert struct.unpack_from(">II",ATLAS.read_bytes(),16)==(528,8)
    p,n=shell()
    groups=mesh(NAME)
    tank=groups["Oval_longitudinal_cistern_and_dished_bulkheads"]
    assert min(z for x,z,h in tank)==-.172
    assert max(z for x,z,h in tank)==.762
    assert abs(min(h for x,z,h in tank)-.237)<1.e-7 and abs(max(h for x,z,h in tank)-.611)<1.e-7
    assert all(z<=-.202 for x,z,h in groups["Formed_short_individual_coach_cab,_B-pillar_and_domed_roof"])
    for part in ("Curved_under-tank_saddle_bearing_on_the_crossmember","Separate_tyre_shoulder_cheeks",
            "Wound_and_individually_spaced_rubber_hose_wraps","Rear_service_ladder_steel_side_tubes",
            "Tank_discharge_pipe_with_cast_elbows","Two_bolted_cast_band_clamps",
            "Machined_discharge_union","Round_red_butterfly_valve_handle"):
        assert groups[part],part
    m=read(NAME,True)
    assert ray(m,0,.356,.424,.21,.23),"tanker side is missing"
    assert not ray(m,0,.356,.617,.16,.235),"ellipse shoulder outside the tank should be clear"
    assert ray(m,0,.356,.528,.16,.213),"round upper shoulder should be present"
    assert ray(m,0,.356,.301,.16,.213),"round lower shoulder should be present"
    assert not ray(m,0,.356,.27,.17,.222),"open underside cutout is filled"
    footprints=[]
    tire=set()
    for key, points in groups.items():
        footprints.extend((x*S,h*S,z*S) for x,z,h in points)
        if key.startswith("Ground_contact_tyre_"):
            tire.update((x*S,z*S) for x,z,h in points if abs(h)<1.e-7)
    assert len(tire)==8 and {round(z/S,6) for x,z in tire}=={-.454,.435}
    assert len({(x>0,z>0) for x,z in tire})==4
    lo,hi=bounds(footprints)
    in_lane(lo,hi)
    turn_check(lo,hi)
    assert lo[1]==0 and .645<hi[2]-lo[2]<.686
    assert .267<hi[1]<.281
    shape=hull((x,z) for x,_,z in footprints)
    saved=runner.SAMPLE
    try:
        poses,worst,outside=native_sweep(sorted(tire),shape)
    finally:
        runner.SAMPLE=saved
    assert worst[0]==0 and outside==0
    stops=freight_fits(groups)
    arc=BytesIO()
    with ZipFile(arc,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for path in (ATLAS,OBJ): z.write(path,path.name)
    print(f"WITCOMBE_OIL_ART_PASS #132/image3/21k L, one closed shape: {p} tank vertices, {n} two-manifold shell edges, four tire contacts, {poses} stock road and {stops} freight-stop poses; "+
        f"{hi[0]-lo[0]:.5f} W / {hi[1]-lo[1]:.5f} H / {hi[2]-lo[2]:.5f} L; {arc.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-roadveh")
    p.add_argument("--opengfx")
    verify(p.parse_args())
