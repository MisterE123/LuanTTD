#!/usr/bin/env python3
"""Stock-oriented portal seams and an open bore checked on exported triangles."""
from collections import defaultdict
from math import floor, sqrt
from pathlib import Path
import re

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]/"mods"/"bayline"
MODELS=ROOT/"models"
PREFIX="bl_road_tunnel_portal"
DIR=((-1,0),(0,1),(1,0),(0,-1))
ROAD=("Shoulder_slab","Running_asphalt","Inlaid_centre_markings")
COLS={"Shoulder_slab":(154,147,126),"Running_asphalt":(79,82,85),
      "Inlaid_centre_markings":(239,227,182)}
COLLIDER_ONLY={"Recessed_vaulted_brick_barrel","Recessed_barrel_brick_walls"}
VEHICLES={"bus":"town_flyer","truck":"truck","coach":"coach",
          "leopard_bus":"leopard_bus","mail_van":"mail_van"}


def read(d):
    file=MODELS/f"{PREFIX}_{d}.obj"
    out=defaultdict(list)
    verts,uvs,normals=[],[],[]
    dx,dz=DIR[d]
    for line in file.read_text().splitlines():
        tag,_,v=line.partition(" ")
        if tag=="v":
            rawx,rawy,rawz=map(float,v.split())
            x,z=-rawx-.5,rawz-.5
            h=rawy+1
            u,s=dz*x-dx*z,dx*x+dz*z
            assert abs(u)<=1.000001 and abs(s)<=1.000001 and .499999<=h<=1.500001,(file,u,s,h)
            verts.append(tuple(round(x,6) for x in (u,s,h)))
        elif tag=="vn":
            n=tuple(map(float,v.split()))
            assert abs(sum(q*q for q in n)-1)<.00001
            normals.append(n)
        elif tag=="vt":
            uvs.append(tuple(map(float,v.split())))
        elif tag=="o":
            group=v
        elif tag=="f":
            xyz,tex,norm=zip(*(tuple(int(q)-1 for q in r.split("/")) for r in v.split()))
            assert len(xyz)==len(set(xyz))==3
            assert len(set(tex))==len(set(norm))==1
            out[group].append((tuple(verts[i] for i in xyz),uvs[tex[0]],normals[norm[0]]))
    return out


def ray_along_road(cross,height,tri):
    """Intersect a parallel road ray with a mesh triangle."""
    a,b,c=tri
    den=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2])
    if abs(den)<1e-10:
        return None
    s=((b[2]-c[2])*(cross-c[0])+(c[0]-b[0])*(height-c[2]))/den
    t=((c[2]-a[2])*(cross-c[0])+(a[0]-c[0])*(height-c[2]))/den
    r=1-s-t
    if min(s,t,r)>=-1e-8:
        return s*a[1]+t*b[1]+r*c[1]


def polygon_clip(points,axis,limit,greater):
    out=[]
    if not points:
        return out
    for a,b in zip(points,points[1:]+points[:1]):
        inside_a=(a[axis]>=limit) if greater else (a[axis]<=limit)
        inside_b=(b[axis]>=limit) if greater else (b[axis]<=limit)
        if inside_a:
            out.append(a)
        if inside_a!=inside_b:
            t=(limit-a[axis])/(b[axis]-a[axis])
            out.append(tuple(x+(y-x)*t for x,y in zip(a,b)))
    return out


def reaches_prism(triangle,left,right,floor,roof):
    # The bore spans the entire tile. Triangle clipping in its cross-section
    # proves clearance between samples, even for a longitudinal grazing face.
    points=list(triangle)
    for axis,position,greater in ((0,left,True),(0,right,False),(2,floor,True),(2,roof,False)):
        points=polygon_clip(points,axis,position,greater)
    return bool(points)


def vehicle_bounds():
    text=(ROOT/"road_lanes.lua").read_text()
    lanes=float(re.search(r"^M\.right_offset = ([.\d]+)",text,re.M)[1])
    scales={k:float(scale) for k,scale in re.findall(r"(\w+)=(\.\d+)",text)}
    clearance=[]
    out={}
    for engine,mesh in VEHICLES.items():
        # Actual shipped mesh model and current engine representation.
        file=MODELS/f"bl_{mesh}.obj"
        if not file.exists():
            raise AssertionError(f"road vehicle mesh missing: {mesh}")
        ps=[tuple(map(float,l[2:].split())) for l in file.read_text().splitlines() if l.startswith("v ")]
        width=max(abs(v[0]) for v in ps)*scales[engine]/10
        high=max(v[1] for v in ps)*scales[engine]/10+.52
        out[engine]=(width,high)
        assert lanes+width<.326,(engine,"outside approach profile")
        assert 0.35<high-.38<.5,(engine,"unexpected vertical units",high)
        for side in (-1,1):
            center=side*lanes
            # Sweep the complete bounding prism of the model, wider and
            # taller than its actual silhouette, not just the lane centers.
            for i in range(9):
                u=center+width*(-1+i/4)
                for j in range(7):
                    y=.508+(high-.508)*j/6
                    clearance.append((u,y))
    return clearance,out,lanes


def main():
    samples,bounds,lanes=vehicle_bounds()
    atlas=Image.open(ROOT/"textures"/f"{PREFIX}.png").convert("RGB")
    previous=None
    for direction in range(4):
        data=read(direction)
        assert {"Dressed_wing_masonry","Stone_spandrel_face","Arch_keystone",
                "Raised_fired-brick_voussoirs","Crown_turf","Portal_dressed-stone_flanks"} <= set(data)
        assert len(data["Raised_fired-brick_voussoirs"])==32
        for group in ROAD:
            for vs,(u,v),n in data[group]:
                assert all(abs(y-(.5+.004*min(1,8*(1-abs(v)))))<1e-6 for _,v,y in vs)
                assert n[1]>.9994
                assert atlas.getpixel((floor(u*atlas.width),floor(v*atlas.height)))==COLS[group]
        def edge(group,v):
            return sorted({(u,h) for tri,_,_ in data[group] for u,z,h in tri if z==v})
        for v in (-1,1):
            assert edge("Running_asphalt",v)==[(-.3125,.5),(.3125,.5)]
            assert edge("Shoulder_slab",v)==[(-.375,.5),(-.3125,.5),(.3125,.5),(.375,.5)]
            assert not edge("Inlaid_centre_markings",v)
        low=[y for (u,y) in edge("Excavated_turf_flanks",-1) if abs(u)==1]
        high=[y for (u,y) in edge("Crown_turf",1) if abs(u)==1]
        assert low==[.5,.5] and high==[1.5,1.5],(low,high)
        side_soil={"Excavated_turf_flanks","Main_slope_outer_grass","Crown_turf"}
        for g in side_soil:
            for tri,_,_ in data[g]:
                assert all(abs(h-(.5+(v+1)/2))<1e-6 for u,v,h in tri if abs(u)==1)
        # The physical bore reaches the inner tile boundary, i.e. there is
        # a roof and side masonry, not a flat painted opening.
        for g in COLLIDER_ONLY:
            assert edge(g,1) and edge(g,.39)
        assert max(y for _,y in edge("Recessed_vaulted_brick_barrel",1))==1.153
        assert min(u for u,_ in edge("Recessed_barrel_brick_walls",1))==-.422
        tris=[tri for part in data.values() for tri,_,_ in part]
        for engine,(width,roof) in bounds.items():
            for lane in (-lanes,lanes):
                assert not any(reaches_prism(tri,lane-width,lane+width,.508,roof) for tri in tris),(engine,direction)
        for u,y in samples:
            assert all(ray_along_road(u,y,tri) is None for tri in tris),(direction,u,y)
        # A second ray fan demonstrates that the clearance above ordinary
        # bus/truck roof height belongs to a real open arch too.
        for u in (-.35,-.25,0,.25,.35):
            ceiling=.5+.383+.270*sqrt(1-(u/.422)**2)
            assert all(ray_along_road(u,ceiling-.018,tri) is None for tri in tris),(direction,u)
        if previous is not None:
            cur={k:[pts for pts,_,_ in fs] for k,fs in data.items()}
            assert cur==previous
        else:
            previous={k:[pts for pts,_,_ in fs] for k,fs in data.items()}
        axis=10 if direction%2==0 else 5
        texture=Image.open(ROOT/"textures"/f"bl_road_surface_{axis}.png").convert("RGB")
        for e in (0,31):
            pixels=[texture.getpixel((e,i) if axis==10 else (i,e)) for i in range(32)]
            assert pixels[10:22]==[COLS["Shoulder_slab"]]+[COLS["Running_asphalt"]]*10+[COLS["Shoulder_slab"]]
    print(f"PASS: four oriented portal tiles, {len(samples)*4:,} two-lane vehicle-clearance rays "
          f"({', '.join(bounds)}), real arched crown and exact paved/terrain approach seams.")


if __name__=="__main__":
    main()
