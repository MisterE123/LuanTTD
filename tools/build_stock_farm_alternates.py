#!/usr/bin/env python3
"""Highfield variations on exact OpenTTD 16.0-RC1 footprints."""
from pathlib import Path
from random import Random
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S
from mathutils import Vector

A, R = S.A, S.R
B,T,Q = S.B,S.T,S.Q
LAYOUTS = {
    1: {(1,1):33,(1,2):34,(0,0):35,(0,1):36,(0,2):36,(0,3):35,
        (1,0):37,(1,3):38,(2,0):37,(2,1):37,(2,2):38,(2,3):38},
    2: {(2,0):33,(2,1):34,(0,0):36,(0,1):36,(0,2):37,(0,3):37,
        (1,0):35,(1,1):38,(1,2):38,(1,3):37,(2,2):37,(2,3):35},
}

def silo(m,name,x,z,h):
    B(m,name+" chamfered grain pad","cement",x,z,.45,.45,.01,.069,.039)
    T(m,name+" rolled corrugated shell","silo_blue",(x,z,.069),(x,z,h),.187,.187,18)
    for y in (.211,.433,.668,.889,1.091):
        if y<h-.04:
            T(m,name+" pressed silo hoop","zinc_edge",(x,z,y),(x,z,y+.016),.202,.199,18)
    T(m,name+" rain-shedding roof","zinc",(x,z,h),(x,z,h+.143),.206,.039,16)
    for a in (-.044,.044):
        T(m,name+" inspection ladder stile","dark_slate",(x+a,z+.195,.094),(x+a,z+.195,h+.019),.009,.009,6)
    for j in range(8):
        y=.16+j*.118
        if y<h:
            T(m,name+" ladder rung","steel",(x-.048,z+.205,y),(x+.048,z+.205,y),.008,.008,6)

def roll(m,x,z,h=.107):
    T(m,"Wrapped cut straw barrel","haygold",(x-.113,z,h),(x+.113,z,h),.098,.098,12)
    for i in (-.053,.051):
        T(m,"Individual straw knot binding","oat",(x+i,z,h),(x+i+.007,z,h),.103,.103,10)

def grounds(m,plan):
    for (ix,iz),role in plan.items():
        x,z=2*ix,2*iz
        texture="gravel" if role in (33,34,35,36) else "pasture"
        Q(m,"Stock occupied farm cell",texture,x-.50,x+1.50,z-.50,z+1.50,.006)
        if role==38:
            Q(m,"Worn animal path around trough","soil",x-.29,x+1.33,z+.87,z+1.24,.019)
        rng=Random(iz*59+ix*991)
        for _ in range(18):
            a,b=rng.uniform(x-.45,x+1.39),rng.uniform(z-.43,z+1.39)
            Q(m,"Weathered farm surface",rng.choice((texture,"warmclay","gravel")),a,a+.038,b,b+.026,.027)

def buildings(m,plan):
    for (ix,iz),role in plan.items():
        x,z=2*ix,2*iz
        if role==33:
            S.shed(m,"Raised wide threshing barn",x+.36,z+.49,1.38,1.43,.82,1.26,"farmred")
            B(m,"Threshing apron short stone dock","cement",x+.35,z+1.19,1.17,.23,.009,.078,.023)
            B(m,"Deep painted loft frame","dark_green",x+.35,z+1.213,.307,.050,.88,1.077,.018)
            for dx in (-.33,.34):
                roll(m,x+.34+dx,z+1.305)
        elif role==34:
            S.shed(m,"Whitewashed farmhouse and office",x+.48,z+.48,1.33,1.19,.76,1.11,"creamslats",False)
            B(m,"Brick cottage chimney","brick",x+.77,z+.24,.147,.144,.732,1.141,.009)
            B(m,"Lead chimney cap","dark_slate",x+.77,z+.24,.184,.182,1.126,1.153,.008)
            for dx in (-.365,.371):
                B(m,"Farmhouse glazed planter sill","woodold",x+.49+dx,z+1.09,.218,.105,.055,.095,.008)
                for j in range(4):
                    B(m,"Little herb plants","leaf",x+.42+dx+j*.043,z+1.09,.045,.041,.078,.137,.008)
        elif role==35:
            S.shed(m,"Machinery bay with open cart shelter",x+.48,z+.42,1.38,1.19,.62,.95,"creamslats")
            for i in range(3):
                roll(m,x+.03+i*.27,z+1.11)
            B(m,"Wooden equipment bench","woodold",x+1.26,z+.67,.207,.451,.053,.243,.009)
        elif role==36:
            silo(m,"Main barley grain store",x+.13,z+.27,1.26)
            silo(m,"Second feed silo",x+.78,z+.31,1.09)
            T(m,"Steel grain delivery auger","steel",(x+.78,z+.41,.95),(x+1.16,z+.81,.36),.033,.029,8)
            B(m,"Receiving sack grate","dark_slate",x+1.16,z+.81,.19,.17,.010,.063,.008)
            for i in range(3):
                roll(m,x-.08+i*.25,z+1.01)
        elif role==37:
            for j in range(5):
                xx=x-.34+j*.38
                Q(m,"Planted kitchen garden row","soil",xx,xx+.24,z-.30,z+1.30,.033)
                for i in range(7):
                    zz=z-.22+i*.22
                    S.ellipse(m,"Recognizable vegetable leaves","leaf",xx+.10,zz,.065,.061,.046,.054,7)
                    S.ellipse(m,"Pale growing tip","sunleaf",xx+.14,zz+.041,.079,.044,.041,.042,6)
            S.fence(m,[(x-.36,z-.34),(x+1.35,z-.34)],label="Garden back rail")
        elif role==38:
            pts=[(x-.36,z-.33),(x+1.35,z-.33),(x+1.35,z+1.32),(x+.95,z+1.32),
                 (x+.50,z+1.32),(x-.36,z+1.32),(x-.36,z-.33)]
            S.fence(m,pts,gate=(3,),label="Alternate livestock pen")
            B(m,"Stock water trough foot","woodold",x+.48,z-.178,.53,.168,.009,.112,.019)
            B(m,"Water trough interior","silo_blue",x+.48,z-.172,.435,.102,.108,.122,.01)
            for i in range(3):
                roll(m,x+1.14,z+.09+i*.28)

def build(variant):
    source=LAYOUTS[variant]
    name=f"industry_farm_l{variant}"
    look=(2.6,3.4,.50)
    S.build(name,source,(("Stock farm ground and roads",lambda m:grounds(m,source)),
        ("Barns, grain stores, fenced pens and vegetables",lambda m:buildings(m,source))),
        f"Highfield Farm / 16.0-RC1 layout {variant}",f"stock_temperate_farm_l{variant}.blend",
        look,(9.9,12.0,8.5),9.65,S.PAL,None,upstream_layout=variant)

if __name__=="__main__":
    for layout in (1,2):
        build(layout)
    # A farm module is self-contained. The two editable scenes retain
    # the full arrangement; runtime shares one original part per GFX role.
    members={}
    for (x,z),gfx in LAYOUTS[1].items():
        members.setdefault(gfx,(x,z))
    for gfx,(x,z) in members.items():
        (R.MODELS/f"bl_industry_farm_l1_{x}_{z}.obj").replace(R.MODELS/f"bl_farm_alt_gfx_{gfx}.obj")
    for variant,plan in LAYOUTS.items():
        for x,z in plan:
            (R.MODELS/f"bl_industry_farm_l{variant}_{x}_{z}.obj").unlink(missing_ok=True)
    (R.TEXTURES/"bl_industry_farm_l1_atlas.png").replace(R.TEXTURES/"bl_stock_farm_alternate_atlas.png")
    (R.TEXTURES/"bl_industry_farm_l2_atlas.png").unlink(missing_ok=True)
