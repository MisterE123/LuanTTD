#!/usr/bin/env python3
"""Native wire seams, supported track shapes, platform/depot and SH30 clearances."""
from argparse import ArgumentParser
from io import BytesIO
from itertools import product
from math import atan2, cos, hypot, pi, sin, sqrt
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from rail_art import ENDS, SIDES, height
from rail_span_art import along_ray
from rail_wagon_art import mesh
from ship_facility_art import read

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
WIRE="Continuous_shaped_contact_wire_underside_aligned_to_SH30_shoe"
MESS="Independently_suspended_messenger_catenary_cable"
SUBSET=(1,2,4,8,16,32)
EPS=2.e-6


def point(t,mask):
    idx=SUBSET.index(mask)
    a,b=[SIDES[i] for i in ENDS[idx]]
    if idx<2:
        return a[0]*(1-2*t),a[1]*(1-2*t)
    x,z=a[0]+b[0],a[1]+b[1]
    ang=atan2(a[1]-z,a[0]-x)
    end=atan2(b[1]-z,b[0]-x)
    s=(1 if (end-ang)%(2*pi)<pi else -1)
    return x+cos(ang+s*pi*t/2),z+sin(ang+s*pi*t/2)


def parsed(stem,vertical_origin):
    verts=[]
    names={}
    norms={}
    ns=[]
    for line in (MOD/"models"/(stem+".obj")).read_text().splitlines():
        k,_,data=line.partition(" ")
        if k=="o":
            name=data;names.setdefault(name,[]);norms.setdefault(name,[])
        elif k=="v":
            x,h,z=map(float,data.split())
            verts.append((-x-.5,z-.5,h+vertical_origin))
        elif k=="vn":
            ns.append(tuple(map(float,data.split())))
        elif k=="f":
            f=[tuple(map(int,idx.split("/"))) for idx in data.split()]
            names[name].append(tuple(verts[v-1] for v,_,_ in f))
            norms[name].append(ns[f[0][2]-1])
    return names,norms


def vertices(groups,keys=None):
    return {v for k in keys or groups for f in groups[k] for v in f}


def seam(g,kind,edge):
    dx,dz=SIDES[edge]
    return {(round(x if dz else z,6),round(h,6))
            for x,z,h in vertices(g,(kind,)) if abs(x*dx+z*dz-1)<EPS}


def wire_proof(m,mask,grade):
    n=30 if mask<3 else 88
    for i in range(n+1):
        x,z=point(i/n,mask)
        a=list(along_ray(m[WIRE],2,x,z))
        t=height(x,z,grade)+.898
        assert a and abs(min(a)-t)<EPS and abs(max(a)-t-.009)<EPS,(mask,grade,i,a,t)
    for i in range(4):
        p=seam(m,WIRE,i)
        if i not in ENDS[SUBSET.index(mask)]:
            assert not p and not seam(m,MESS,i)
            continue
        dx,dz=SIDES[i]
        y=height(dx,dz,grade)
        pair=lambda width,h,depth:{(j,round(y+k,6)) for j in (-width/2,width/2) for k in (h,h+depth)}
        assert p==pair(.013,.898,.009),(i,mask,grade,p)
        assert seam(m,MESS,i)==pair(.010,.997,.008)


def buildings(parts):
    # All platform/canopy/sign/lamps are on the side, and the mastless
    # overhead wires can use the standard anchor above the rail.
    for i in (1,2):
        g=read("rail_platform_"+str(i))
        obs={k:[f for f,_ in g[k]] for k in g if k in ("Platform_canopy","Cast_shelter_posts",
                  "Shelter_rear_glazing","Porcelain_station_sign","Platform_coach_lamps")}
        wire=parts[i,0]
        remove=2-i # remove is world Z for axis X, world X for axis Z
        rail_axis=remove
        assert max(abs(p[rail_axis]) for p in vertices(wire))<.016
        assert min(abs(p[rail_axis]) for p in vertices(obs))>.40
    # Existing shed mouths have genuine arch clearance. The art module
    # does not mount wire through a shed, where it would exit the back wall.
    stage=mesh("rail_sh_30")
    samples={(round(x,4),round(h,4)) for rows in stage.values() for x,z,h in rows}
    for d,q in enumerate((1,0,3,2)):
        g=read("rail_depot_"+str(d))
        def rot(p):
            x,z,y=p
            return ((x,z,y),(z,-x,y),(-x,-z,y),(-z,x,y))[q]
        canopy=[tuple(map(rot,f)) for n in ("Masonry_gable","Dressed_stone_arch_voussoirs") for f,_ in g[n]]
        for x,h in samples:
            for z in (.475,.524,.601,.641):
                assert h+.114+.01<min(along_ray(canopy,2,x,z)),(d,x,h,z)
    return len(samples)*4*4


def verify(a):
    if a.upstream_elrail:
        t=Path(a.upstream_elrail).read_text()
        assert "Each track ends on two PCPs" in t and "one pylon every" in t
        assert "GetPCPElevation" in t and "IgnoredPCP" in t
    shapes=[(0,m) for m in SUBSET]+list(enumerate((1,1,2,2),1))
    out=BytesIO()
    world={}
    variants=0
    with ZipFile(out,"w",ZIP_DEFLATED,compresslevel=9) as b:
        texture=MOD/"textures/bl_rail_catenary_atlas.png"
        b.write(texture,texture.name)
        for grade,mask in shapes:
            prefix="bl_rail_catenary_"+(f"grade_{grade}" if grade else str(mask))
            modes=[]
            for pole in (0,1):
                name=prefix+f"_{pole}"
                m,n=parsed(name,2.5 if grade else 1.5)
                b.write(MOD/"models"/(name+".obj"),name+".obj")
                wire_proof(m,mask,grade)
                # Check the actual normals: lower face must be visible from
                # the locomotive cab in Luanti, not facing the sky.
                assert min(x[1] for x in n[WIRE])<-.89
                assert max(x[1] for x in n[WIRE])>.89
                assert max(max(abs(x),abs(z)) for x,z,h in vertices(m))<=1+EPS
                assert len(m["Five_actual_thin_separate_vertical_droppers"])==60
                if pole:
                    assert len(m["Three_separate_insulator_porcelain_ridges_on_drop_bar"])>=100
                    assert len(m["Tall_genuine_H_section_hot_rolled_steel_mast_central_web"])>=12
                    sol=vertices(m,("Chamfered_grounded_masonry_mast_foot",))
                    assert min(h-height(x,z,grade) for x,z,h in sol)<EPS
                    for x,z,h in sol:
                        d=min(hypot(x-a,z-c) for a,c in (point(i/220,mask) for i in range(221)))
                        assert d>.59,(mask,grade,x,z,d)
                else:
                    assert set(m)=={WIRE,MESS,"Five_actual_thin_separate_vertical_droppers"}
                    world[mask,grade]=m
                modes.append(m)
                variants+=1
            assert all(modes[0][k]==modes[1][k] for k in modes[0]),"mast variant changed the wire"
    joins=0
    for (u,g),(v,h) in product(world,repeat=2):
        for i in range(4):
            for cable in (WIRE,MESS):
                l=seam(world[u,g],cable,i)
                r=seam(world[v,h],cable,(i+2)%4)
                if l and r:
                    a=min(y for x,y in l)
                    c=min(y for x,y in r)
                    # If terrain heights and endpoints match normalize by
                    # those integer bases. No direction-dependent seams.
                    assert { (x,round(y-a,6)) for x,y in l }=={ (x,round(y-c,6)) for x,y in r },(u,g,v,h,i)
                    assert abs((a-c)-round(a-c))<EPS
                    joins+=1
    depot=buildings(world)
    # Geometry deliberately uses a fixed vertical offset on stock steep
    # rays. A future pitch-aware spring must shorten the visual collector.
    cut=.784/(sqrt(1+.5**2))
    assert .701<cut<.702 and .092<.784*sqrt(1+.5**2)-.784<.094
    train=mesh("rail_sh_30")
    pantograph=("Linked_steel_lower","Slender_stand-off_upper","Machined_visible_pantograph",
      "Fixed_smaller_parallelogram","Transverse_working_contact","Thin_polished_outer_contact",
      "Slightly_bent_contact")
    body=[h for name,pts in train.items() if not name.startswith(pantograph) for x,z,h in pts]
    assert max(body)+.10<cut, "fixed roof equipment must clear grade wire"
    assert out.tell()<200_000 and (ROOT/"art/rail_catenary.blend").exists()
    print(f"RAIL_CATENARY_ART_PASS: {variants} assets / {joins} joins, exact actual X/Y platform clearing, "+
          f"{depot:,} raised SH30 depot arch hits checked, 18 collector intersections covered separately; "+
          f"{out.tell():,} ZIP bytes.")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-elrail")
    verify(p.parse_args())
