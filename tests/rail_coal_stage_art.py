#!/usr/bin/env python3
"""Validate tile/rail asset dimensions using exported native triangles."""
from itertools import combinations
from math import isclose
from pathlib import Path

from rail_span_art import along_ray,load,vehicle
from rail_architecture import assert_no_area_overlap, det, sections

PREFIX="bl_rail_coal_stage"
ROOT=Path(__file__).resolve().parents[1]
EPS=6e-6
RAILS={"Polished_railhead","Rail_web","Rail_foot","Compacted_ballast","Ballast_shoulder"}
BASE=.5

def basis(axis,mirror,p):
    x,z,y=p
    if axis==0:x,z=z,-x
    if mirror:x=-x
    return (x,z,y+BASE)

def profile(m,axis,mirror,v,name):
    return {(round(x,6),round(h,6)) for g,tri in m if g==name
      for x,z,h in (basis(axis,mirror,p) for p in tri)
      if abs(z-v)<EPS}

FOUNDATION="Continuous_dressed_service_platform_foundation"
COPING="Continuous_nonfouling_ashlar_coping"
CAPS={"Finished_ashlar_platform_end_caps","End-coping_limestone_highlight"}
STRUCTURE={FOUNDATION,COPING,"Back_edge_of_receiving_pit_deck","Intact_landing_deck_beyond_hopper_ends",
    "Internal_service_pit_landing_return","Platform_sulfur_safety_line","Flush_service_deck_contraction_joints",
    "Rear_platform_contraction_joint","Capstone_perpendicular_joints"} | CAPS


def deck_faces(mesh,kind):
    faces=[f for g,f in mesh if g in STRUCTURE]
    # Axis-aligned structural faces must partition, not overlap. In old
    # exports this catches .014 square units of same-facing back wall and
    # the raised joints atop one another at .283 in every orientation.
    for axis in range(3):
        positions={round(f[0][axis],6) for f in faces if
                   all(abs(p[axis]-f[0][axis])<EPS for p in f)}
        for h in sorted(positions):
            assert_no_area_overlap(combinations(sections(faces,axis,h),2))
    top=sections(faces,2,.282)
    area=sum(abs(det(*t))/2 for t in top)
    expected=2*(.963-.358)-(1.24*(.921-.493) if kind=="unload" else 0)
    assert isclose(area,expected,abs_tol=1e-8),(kind,area,expected)
    for z in (-1,1):
        assert not sections(faces,1,z),"A whole stage end face shares the neighboring tile's plane"
        caps=sections([f for g,f in mesh if g in CAPS],1,z*.976)
        assert len(caps)==4
        assert isclose(sum(abs(det(*t))/2 for t in caps),(.963-.365)*.204+(.963-.358)*.076,abs_tol=1e-8)
        assert sections([f for g,f in mesh if g==COPING],0,.963), "Missing continuous coping side"
    if kind=="unload":
        # No paving crosses the opening; deck continues behind/along it
        # and on both approaches without abandoning the original outline.
        for x,z,solid in ((.70,0,False),(.5,.615,False),(.92,-.616,False),
                           (.95,0,True),(.42,.4,True),(.75,.7,True),(.75,-.7,True)):
            assert bool(list(along_ray(faces,2,x,z)))==solid,(x,z,solid)

def check():
    atlas=ROOT/"mods/bayline/textures"
    # Equal palette samples for stock rails and ballast despite independent
    # facility atlas sizes. Blender's angle/colour is not trusted as a proxy.
    from PIL import Image
    ta,ca=(Image.open(atlas/n) for n in ("bl_rail_atlas.png",PREFIX+"_atlas.png"))
    assert [ta.getpixel((8*i+4,4)) for i in range(19)]==[ca.getpixel((8*i+4,4)) for i in range(19)]
    joins=0;rays=0;maxh=0
    vehicles=("rail_kirby_paul_tank","rail_passenger_wagon","rail_open_wagon","electric")
    bounds={k:max(h for _,_,h in vehicle("bl_"+k)) for k in vehicles}
    assert max(bounds.values())+.114<.94
    fixtures={}
    for kind in ("load","unload"):
        for axis in (0,1):
            ref=load("bl_rail_track_"+str(2**axis))
            for m in (False,True):
                key=f"{kind}_{axis}"+("_mirror" if m else "")
                art=load(PREFIX+"_"+key)
                for side in (-1,1):
                    for g in RAILS:
                        expected=profile(ref,axis,m,side,g)
                        actual=profile(art,axis,m,side,g)
                        assert actual and actual==expected,(key,g,side,actual,expected)
                        joins+=1
                p=[(g,tuple(basis(axis,m,p) for p in ps)) for g,ps in art]
                deck_faces(p,kind)
                boxes=[v for g,ps in p for v in ps]
                assert max(abs(x) for x,z,y in boxes)<=1+EPS, key
                assert max(abs(z) for x,z,y in boxes)<=1+EPS, key
                assert min(y for x,z,y in boxes)>=-EPS, key
                maxh=max(maxh,max(y for x,z,y in boxes))
                assert any(g=="Continuous_nonfouling_ashlar_coping" and
                           any(abs(x-.358)<EPS and abs(y-.282)<EPS for x,z,y in ps)
                           for g,ps in p)
                # Exact exported solid geometry inside the rolling exclusion
                # prism is checked along the entire length, in all variants.
                machinery=[ps for g,ps in p if any(y>.124 for x,z,y in ps)]
                for x in (-.302,-.242,-.181,-.114,0,.114,.181,.242,.302):
                    for h in (.14,.22,.31,.39,.46,.57,.70,.79,.88,.940):
                        assert not list(along_ray(machinery,1,x,h)),(key,x,h)
                        rays+=1
                fixtures[kind,axis,m]=p
    for key,p in fixtures.items():
        if key[0]=="load":
            assert any(g=="Raw_coal_visible_in_open_surge_hopper" for g,_ in p)
            assert any(g=="Visible_coal_riding_feed_conveyor" for g,_ in p)
            low=min(h for g,pts in p if "chute_outer_side" in g for _,_,h in pts)
            assert isclose(low,1.03,abs_tol=EPS), low
        else:
            pit=[ps for g,ps in p if "Continuous_" not in g]
            for z in (-.46,-.355,-.224,.319,.418,.546):
                v=[u for u in along_ray(pit,2,.740,z) if u<.32]
                assert v and max(v)<.16,(key,z,v)
            assert any(g.startswith("Rotary_unloading_cradle") for g,_ in p)
            assert any(g.startswith("Sloped_formed_steel_wagon_tipping_throat") for g,_ in p)
    print(f"RAIL_COAL_STAGE_ART_PASS 8 orientations, {joins} precise ordinary track joins, {rays} unobstructed entry-to-exit rays; non-overlapping .282 deck and recessed end walls, self-contained tile footprint, max height {maxh:.3f}")

if __name__=="__main__":
    check()
