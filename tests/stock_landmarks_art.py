#!/usr/bin/env python3
"""Check authentic stock identities, open lattice / dish geometry and native datum."""
from argparse import ArgumentParser
from io import BytesIO
from math import cos, pi, sin
from pathlib import Path
import re
import struct
from zipfile import ZIP_DEFLATED, ZipFile

from ship_facility_art import read

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/bayline"


def verify(args):
    if args.opengfx:
        m=Path(args.opengfx).read_text()
        expect=((2601,"infrastructure/airports.png",(98,472,63,90)),
                (2602,"landscape/landscape031.png",(706,3976,41,61)))
        for number,src,rect in expect:
            pattern=rf'spr{number}\({number}, "sprites/png/{re.escape(src)}"\)\s*{{\s*\[([^]]+)\]'
            assert tuple(map(int,re.findall(r'-?\d+',re.search(pattern,m)[1])))[:4]==rect
    atlas=MOD/"textures/bl_stock_landmarks_atlas.png"
    assert struct.unpack_from(">II",atlas.read_bytes(),16)==(264,8)
    assert (ROOT/"art/stock_landmarks.blend").stat().st_size>130000
    heights={}
    groups={}
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as arc:
        arc.write(atlas,atlas.name)
        for a in ("lighthouse","transmitter"):
            f=MOD/"models"/f"bl_stock_{a}.obj"
            arc.write(f,f.name)
            # read() decodes Luanti reflection and even anchor +.5/−.5.
            g=groups[a]=read("stock_"+a)
            p={v for fs in g.values() for tri,_ in fs for v in tri}
            assert len(p)>500
            assert -.006<min(h for x,z,h in p)<=0
            assert max(max(abs(x),abs(z)) for x,z,h in p)<1.0
            assert all(len(set(tri))==3 for fs in g.values() for tri,_ in fs)
            heights[a]=max(h for x,z,h in p)
    assert abs(heights["lighthouse"]-1.686)<2.e-6
    assert abs(heights["transmitter"]-2.557)<2.e-6
    l=groups["lighthouse"]
    assert len(l["Tapered_grey-white_lighthouse_masonry_shafts"])>300
    assert len(l["Turned_glass_lantern_panes_divided_by_dark_metal_stanchions"])==96
    assert len(l["Separate_circular_upper_lantern_gallery_railing"])==144
    assert "Separate_shaped_slate_gable_and_mortar_fascia" in l
    t=groups["transmitter"]
    # One real narrow tie per face of nine section tiers: 36 braces.
    assert len(t["Open_alternating_web_lattice_and_real_diagonal_steel_ties"])==432
    assert len(t["Three_diagonal_mast_tension_guy_cables"])==36
    assert len(t["Distinct_concave_microwave_reflector_dish_bowl"])==144
    p={v for tri,_ in t["Distinct_concave_microwave_reflector_dish_bowl"] for v in tri}
    for a,h,coarse in ((-.22*pi,2.133,.186),(.43*pi,2.227,.194),(1.09*pi,2.109,.189)):
        c,s=cos(a),sin(a)
        axis=lambda q:q[0]*c+q[1]*s
        p1=[q for q in p if axis(q)>.16]
        assert len(p1)>=36
        assert coarse+.061<max(map(axis,p1))<coarse+.093
        assert coarse<min(map(axis,p1))<coarse+.033
    assert b.tell()<150_000
    print(f"STOCK_LANDMARKS_ART_PASS: 2602 stone shaft/lantern 1.686 and 2601 three-dish open mast 2.557; exact single-tile ground and {b.tell():,} ZIP bytes")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--opengfx")
    verify(p.parse_args())
