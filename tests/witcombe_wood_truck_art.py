#!/usr/bin/env python3
"""Physical, cargo-geometry, and source identity tests for stock road row 28."""
from argparse import ArgumentParser
from collections import Counter
from math import isclose
from pathlib import Path
import re
import struct

from coal_tipper_art import bounds,in_lane,turn_check
from balogh_goods_truck_art import freight_fits
from rail_wagon_art import mesh

ROOT=Path(__file__).resolve().parents[1]
NAME="witcombe_wood_truck"
S=.42
BARK_PREFIX="Real_separate_tapered_timber_bark_solid"
ENDS_PREFIX="Cut_endgrain_annular_growth_rings"
CONTACT="Ground_contact_tyre"

def data_table(txt,s):
    m=re.search(re.escape(s)+r'\s*\[\]\s*=\s*\{(.*?)\};',txt,re.S)
    assert m
    return [int(x,0) for x in re.findall(r'0[xX][A-Fa-f0-9]+|\b\d+\b',m[1])]

def source(engines,rv,opengfx,sheet):
    if engines:
        t=Path(engines).read_text()
        assert re.search(r'MR\(\s*5479,\s*20,\s*15,\s*55,\s*CT_WOOD\s*,\s*T\|A\|S\s*\),\s*//\s*144 Witcombe Wood Truck',t)
        assert re.search(r'ROV\(\s*7,\s*118,\s*90,\s*SND_19_DEPARTURE_OLD_RV_1,\s*96,\s*20,\s*38,\s*12\),\s*//\s*28 Witcombe Wood Truck',t)
    if rv:
        t=Path(rv).read_text()
        assert data_table(t,"_roadveh_images")[7]==0xD14
        assert data_table(t,"_roadveh_full_adder")[7]==48
        assert "cargo.StoredCount() >= this->cargo_cap / 2U" in t
    if opengfx:
        t=Path(opengfx).read_text()
        assert re.search(r'spr3348\(3348, "sprites/png/roadvehicles/flatbeds.png"\)\s*\{\s*tmpl_roadvehicles\(0,20\)',t)
        assert re.search(r'spr3396\(3396, "sprites/png/roadvehicles/flatbeds.png"\)\s*\{\s*tmpl_roadvehicles\(0,84\)',t)

    if sheet:
        from PIL import Image
        im=Image.open(sheet)
        assert im.mode=="P" and im.size==(256,512)
        # Company-blue palette indices are present in both profiles. Only
        # the loaded row gains a substantial warm wood stack. No palette
        # data or source image is bundled as part of the exported art.
        rows=[]
        for y in (20,84):
            row=im.crop((0,y,256,y+20))
            rows.append(Counter(row.get_flattened_data() if hasattr(row,"get_flattened_data") else row.getdata()))
        company=[sum(row[k] for k in range(198,206)) for row in rows]
        load=[sum(row[k] for k in range(60,65)) for row in rows]
        assert min(company)>400 and load[1]>9*load[0] and load[1]>500

def vertices(groups):
    return [(x*S,h*S,z*S) for ps in groups.values() for x,z,h in ps]

def faces(n):
    paths=ROOT/"mods/bayline/models"/f"bl_{n}.obj"
    pts=[];uv=[];normals=[];names={};g=None
    for line in paths.read_text().splitlines():
        t,*p=line.split()
        if t=="v":pts.append(tuple(map(float,p)))
        if t=="vn":normals.append(tuple(map(float,p)))
        if t=="vt":
            u,v=map(float,p)
            uv.append(round(42*u-.5))
            assert isclose(v,.5) and abs(42*u-.5-uv[-1])<.00003
        if t=="o":
            g=p[0];names[g]=Counter()
        if t=="f":
            corners=[tuple(map(int,k.split("/"))) for k in p]
            assert len(corners)==3 and all(0<i<=len(pts) and 0<j<=len(uv) and 0<k<=len(normals) for i,j,k in corners)
            names[g][tuple(sorted((pts[i-1],uv[j-1],normals[k-1]) for i,j,k in corners))]+=1
    assert len(uv)==42
    return names

def verify(e,r,ogg,sheet):
    source(e,r,ogg,sheet)
    empty=mesh(NAME)
    full=mesh(NAME+"_loaded")
    ef=faces(NAME);ff=faces(NAME+"_loaded")
    assert empty.keys()<full.keys()
    assert all(ff[k]==v for k,v in ef.items()),"Load must not move fixtures, coachwork, anchors or wheels"
    assert all(set(v.values())=={1} for k,v in ff.items()),"Repeated identical complete faces"
    added=full.keys()-empty.keys()
    barks=[k for k in added if k.startswith(BARK_PREFIX)]
    ends=[k for k in added if k.startswith(ENDS_PREFIX)]
    assert len(barks)==len(ends)==14
    assert sum("lower_long_stem" in k for k in barks)==4
    for p in ("_bundle_1","_bundle_2"):
        assert sum(p in k for k in barks)==5
    for k in barks:
        v=full[k]
        loz=min(z for _,z,_ in v);hiz=max(z for _,z,_ in v)
        assert -.173<loz<hiz<.722 and max(abs(x) for x,_,_ in v)<.202
        assert hiz-loz>(.80 if "long_stem" in k else .30)
    assert all(n in added for n in ("Separate_load-only_cinch_band_1","Separate_load-only_cinch_band_2"))
    assert max(h for k in added for _,_,h in full[k])<.651
    for k,s in (("L",-1),("R",1)):
        t=empty[CONTACT+"_"+k]
        assert min(h for _,_,h in t)==0
        minx,maxx= min(x for x,z,h in t if h==0),max(x for x,z,h in t if h==0)
        assert abs((minx+maxx)/2-s*.223)<.002
        assert sorted({round(z,6) for _,z,h in t if h==0})==[-.47,.479]
    for n,sign in (("Individual_warm_headlamp_lenses",-1),("Sector_glass_rear_hitch_tail_lamp_lenses",1)):
        assert all(z*sign>.70 for _,z,_ in empty[n])
    assert len(empty["Permanent_blue-slate_log_stakes"])>=30
    assert len(empty["Individual_full-length_hardwood_deck_boards"])>90
    assert all(z<-.640 for _,z,h in empty["Visible_two_independent_glazed_windshield_panels"])
    for state,groups in (("empty",empty),("loaded",full)):
        sizes=bounds(vertices(groups))
        in_lane(*sizes);turn_check(*sizes)
    lo,hi=bounds(vertices(full))
    assert bounds(vertices(empty))==bounds(vertices(full))
    for stem,model in ((NAME,ef),(NAME+"_loaded",ff)):
        tris=sum(sum(v.values()) for v in model.values())
        assert 10_000<tris<21_000,(stem,tris)
    assert (ROOT/"art/witcombe_wood_truck.blend").stat().st_size>100000
    atlas=(ROOT/"mods/bayline/textures/bl_witcombe_wood_truck_atlas.png").read_bytes()
    assert atlas[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",atlas,16)==(336,8)
    freight=freight_fits(full)
    print(f"WITCOMBE_ART_PASS #144/road28/image7+48; true empty and load, 4 contacts, native x/h/z {tuple(round(b-a,4) for a,b in zip(lo,hi))}; both lanes and eased turns, {freight:,} exact stock freight-stop sweeps.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-roadveh")
    p.add_argument("--opengfx-pnml")
    p.add_argument("--opengfx-sheet")
    a=p.parse_args()
    verify(a.upstream_engines,a.upstream_roadveh,a.opengfx_pnml,a.opengfx_sheet)
