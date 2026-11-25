#!/usr/bin/env python3
"""Static footprint, atlas, loading space and detailed finished geometry."""
from argparse import ArgumentParser
from math import cos, hypot, isclose, sin, tau
from pathlib import Path
import re
import struct
import sys
from collections import defaultdict
from zipfile import ZipFile, ZIP_DEFLATED
from io import BytesIO

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from farm_surface_partition import area,bounds,overlaps,subtract
MODELS=ROOT/"mods/luanttd_core/models"
TEXTURES=ROOT/"mods/luanttd_core/textures"
LAYOUT={
    "farm":{(1,0):33,(1,1):34,(1,2):36,(0,0):37,(0,1):37,
            (0,2):36,(2,0):35,(2,1):38,(2,2):38},
    "factory":{(0,0):39,(0,1):40,(1,0):41,(1,1):42,(0,2):39,(0,3):40,
               (1,2):41,(1,3):42,(2,1):39,(2,2):40,(3,1):41,(3,2):42},
}
REQUIRED={
    33:("Stocking_and_sorting_corral","Orchard_forked_ash_trunk"),
    34:("Single-storey_farmhouse","Farmhouse_chimney"),
    35:("Threshing_barn","Side-by-side_cart_shed"),
    36:("Light_slate_grain_annex_open_pass-through_concrete_floor",),
    37:("Corrugated_vertical_grain_silo_weathered_turned_shell","Corrugated_vertical_grain_silo_silvery_roof_cone"),
    38:("paddock_galvanized_gate_bar","Galvanized_livestock_water_trough_hull"),
    39:("masonry_freight_elevator_tower","folded_standing_seam_blue_steel_weather_canopy"),
    40:("Side_goods_warehouse_open_door_jamb_lintel","Side_goods_warehouse_glazed_window_pane"),
    41:("Factory_pair_of_tapering_brick_chimneys_visibly_open_chimney_crown","Boiler_and_wash_powerhouse"),
    42:("Concrete_wagon_loading_court","Flush_outbound_truck_weighbridge","Goods_packing_crates"),
}


def upstream(build,land):
    if build:
        text=Path(build).read_text()
        for name,expected in LAYOUT.items():
            body=re.search(r"_tile_table_"+name+r"_0\s*\{(.*?)^\s*\};",text,re.M|re.S)[1]
            cells=(re.findall(r"MK\((\d+), (\d+), (\d+)\)",body) or
                   re.findall(r"\{\{(\d+), (\d+)\}, (\d+)\}",body))
            assert {(int(x),int(z)):int(g) for x,z,g in cells}==expected
    if land:
        data=Path(land).read_text().split("_industry_draw_tile_data",1)[1]
        rows=re.findall(r"^\s+M\((.*)\),",data,re.M)
        for i,(ground,overlay) in enumerate(((0x83a,0x83c),(0x83b,0x83d),(0x83e,0x83f),(0x840,0x841),
                            (0x842,0x843),(0x844,0x845),(0x862,0x866),(0x863,0x867),(0x864,0x868),(0x865,0)),33):
            row=rows[4*i+3].split(",")
            assert (int(row[0].split()[0],16),int(row[2].split()[0],16))==(ground,overlay),(i,row)


def mesh(f,materials,gfx):
    pts=[];groups={};uvs=[];name="";n=0;faces=0
    expected=Path(f).read_text().splitlines()
    assert f"GFX {gfx}; original Blender art" in expected[0]
    for line in expected[1:]:
        if line.startswith("o "):
            name=line[2:]; groups[name]=[]
        elif line.startswith("v "):
            p=tuple(map(float,line.split()[1:]))
            assert -.500001<=-p[0]<=1.500001 and -.500001<=p[2]<=1.500001,(f,p)
            assert -.527<=p[1]<2.1,(f,p)
            pts.append(p);groups[name].append(p)
        elif line.startswith("vt "):
            u,v=map(float,line.split()[1:])
            assert isclose(u,(len(uvs)+.5)/materials,abs_tol=5.2e-7) and v==.5,(f,line)
            uvs.append(u)
        elif line.startswith("vn "):
            p=tuple(map(float,line.split()[1:]))
            assert isclose(sum(v*v for v in p),1,abs_tol=3e-5),(f,line)
            n+=1
        elif line.startswith("f "):
            refs=[tuple(map(int,v.split("/"))) for v in line.split()[1:]]
            assert len(refs)>=3
            assert all(1<=a<=len(pts) and 1<=b<=len(uvs) and 1<=c<=n for a,b,c in refs)
            faces+=1
    assert len(uvs)==materials and len(pts)>90 and faces>70,(f,len(pts),faces)
    assert all(any(required in n for n in groups) for required in REQUIRED[gfx]),(f,gfx,REQUIRED[gfx],list(groups))
    if str(f).endswith("bl_industry_farm_0_0.obj"):
        # Ground inlay must not swallow the flush weighing grille.
        assert all(groups[part] for part in ("Flush_receiving_weigh_plate","Visible_inset_slot_bars"))
        assert all(isclose(y,-.478,abs_tol=1e-6) for part in ("Flush_receiving_weigh_plate","Visible_inset_slot_bars")
                   for _,y,_ in groups[part])
    if gfx==42:
        # +X edge is open for the installation's visually paved delivery
        # approach, except paint and drainage. No false collision objects.
        assert all(-x<.79 or not .21<z<1.27 or h<-.464 for x,h,z in pts)
    return faces


def duplicate_surface(f):
    """A continuous material may meet, but not overlap another visible face."""
    verts,normals=[],[]
    planes=defaultdict(list)
    for line in Path(f).read_text().splitlines():
        field,*v=line.split()
        if field=="v":
            verts.append(tuple(map(float,v)))
        elif field=="vn":
            normals.append(tuple(map(float,v)))
        elif field=="f":
            refs=[tuple(map(int,part.split("/"))) for part in v]
            face=[verts[a-1] for a,_,_ in refs]
            normal=normals[refs[0][2]-1]
            axis=max(range(3),key=lambda i:abs(normal[i]))
            level=sum(a*b for a,b in zip(normal,face[0]))
            original=abs(area(face,axis))
            if original<2e-6:
                continue
            box=bounds(face,axis)
            # OBJ vertices are emitted at six decimals; tolerate their
            # quantization but not substantial overlap in the same plane.
            for slice_ in (int(level*50000)-1,int(level*50000),int(level*50000)+1):
                for other_level,other_box,other in planes[normal,slice_]:
                    if abs(other_level-level)<=2e-5 and overlaps(box,other_box):
                        surviving=sum(abs(area(q,axis)) for q in subtract(face,other,axis))
                        if original-surviving>2e-6:
                            return (normal,level,original-surviving)
            planes[normal,int(level*50000)].append((level,box,face))

def livestock(materials):
    assets=[]
    bounds_by_kind=defaultdict(list)
    for kind in ("brown","cream","pig"):
        poses={}
        for variant in ("idle","step_a","step_b"):
            f=MODELS/f"bl_farm_animal_{kind}_{variant}.obj"
            assets.append(f)
            vertices=[];objects={};name="";uv=normals=faces=0
            for line in f.read_text().splitlines():
                k,*v=line.split()
                if line.startswith("# o "):
                    name=line[4:];objects[name]=[]
                elif k=="v":
                    xyz=tuple(map(float,v))
                    assert abs(xyz[0])<1.3 and abs(xyz[2])<2.7 and -.02<xyz[1]<3.1,xyz
                    vertices.append(xyz);objects[name].append(xyz)
                elif k=="vt": uv+=1
                elif k=="vn": normals+=1
                elif k=="f":
                    assert all(1<=a<=len(vertices) and 1<=b<=uv and 1<=n<=normals
                               for a,b,n in (map(int,x.split('/')) for x in v))
                    faces+=1
            assert uv==materials and faces>180 and len(objects)>=6
            assert min(v[1] for v in vertices)<.2
            front="Pig_defined_snout" if kind=="pig" else "Livestock_pale_square_muzzle"
            assert min(z for _,_,z in objects[front])>.4
            poses[variant]=objects
            bounds_by_kind[kind].extend((-x/10,z/10) for x,_,z in vertices)
        legs="Pig_articulated_feet" if kind=="pig" else "Livestock_dark_hooves"
        assert len({tuple(p[legs]) for p in poses.values()})==3,"poses don't animate the feet"
        assert len({tuple(p[front]) for p in poses.values()})==1,"gait distorts the head"
    # Validate authored lane placement from the actual exported silhouettes;
    # end positions alone wouldn't catch the front or hindquarters clipping
    # a trough as the cow turns. A 3-cm inset covers posts and rail width.
    module=(ROOT/"mods/luanttd_core/farm_livestock_view.lua").read_text()
    lane_expr=r'kind="(\w+)",x=([.\d]+),z=([.\d]+),rx=([.\d]+),rz=([.\d]+)'
    original,alternate=module.split("local smaller_lanes=",1)
    paths=re.findall(lane_expr,original)
    assert len(paths)==5
    envelopes=[]
    for i,(kind,*fields) in enumerate(paths):
        x0,z0,rx,rz=map(float,fields)
        north=i<2
        xlo,zlo,xhi,zhi=(3.64,1.71,5.33,3.35) if north else (3.64,3.68,5.33,5.34)
        wx,tz=(5.075,2.06) if north else (5.07,4.02)
        all_x,all_z=[],[]
        for step in range(180):
            a=tau*step/180
            x,z=x0+rx*cos(a),z0+rz*sin(a)
            dx,dz=-rx*sin(a),rz*cos(a)
            d=hypot(dx,dz);dx,dz=dx/d,dz/d
            for u,v in bounds_by_kind[kind]:
                a_x,a_z=x+dz*u+dx*v,z-dx*u+dz*v
                assert xlo+.03<a_x<xhi-.03 and zlo+.03<a_z<zhi-.03,(kind,a_x,a_z)
                assert abs(wx-a_x)>.18 or abs(tz-a_z)>.09,(kind,"trough",a_x,a_z)
                all_x.append(a_x);all_z.append(a_z)
        envelopes.append((min(all_x),min(all_z),max(all_x),max(all_z)))
    for i,(a,b,c,d) in enumerate(envelopes):
        for x,z,u,v in envelopes[:i]:
            assert c<x or u<a or d<z or v<b,"animated animal paths overlap"
    compact=re.findall(lane_expr,alternate)
    assert len(compact)==2
    compact_bounds=[]
    for kind,*fields in compact:
        x0,z0,rx,rz=map(float,fields)
        pose=[]
        for step in range(180):
            a=tau*step/180
            x,z=x0+rx*cos(a),z0+rz*sin(a)
            dx,dz=-rx*sin(a),rz*cos(a)
            d=hypot(dx,dz);dx,dz=dx/d,dz/d
            for u,v in bounds_by_kind[kind]:
                px,pz=x+dz*u+dx*v,z-dx*u+dz*v
                assert -.33<px<1.32 and -.30<pz<1.29,(kind,"fence",px,pz)
                assert not (.185<px<.775 and -.292<pz<-.064),(kind,"trough",px,pz)
                assert not (.997<px<1.283 and any(abs(pz-center)<.133 for center in (.09,.37,.65))),(
                    kind,"bale",px,pz)
                pose.append(px)
        compact_bounds.append((min(pose),max(pose)))
    assert compact_bounds[0][1]<compact_bounds[1][0],"alternate pen animals cross each other"
    return assets

def test(args):
    upstream(args.upstream_layout,args.upstream_art)
    names=[]
    for label,cells in LAYOUT.items():
        f=TEXTURES/f"bl_industry_{label}_atlas.png";names.append(f)
        atlas=f.read_bytes()
        assert atlas[:8]==b"\x89PNG\r\n\x1a\n"
        width,height=struct.unpack(">II",atlas[16:24])
        assert width%8==0 and height==8
        files={f.name for f in MODELS.glob(f"bl_industry_{label}_*_*.obj")}
        assert files=={f"bl_industry_{label}_{x}_{z}.obj" for x,z in cells}
        faces=0
        for (x,z),gfx in cells.items():
            f=MODELS/f"bl_industry_{label}_{x}_{z}.obj";names.append(f)
            faces+=mesh(f,width//8,gfx)
            if label=="farm":
                animal=r"^o (Livestock_(?:modeled|shoulder|lowered|pale|turned|short|shaped|dark|curved)|Pig_)"
                assert not re.search(animal,f.read_text(),re.M),"static duplicate of animated livestock"
                overlap=duplicate_surface(f)
                assert not overlap,(f,"overlapping coplanar render surfaces",overlap)
        assert (ROOT/"art"/f"stock_temperate_{label}.blend").stat().st_size>120000
        print(f"Stock {label}: {len(cells)} exact named cells, {faces:,} valid faces, {width//8} original material swatches")
        if label=="farm":
            names.extend(livestock(width//8))
    records=BytesIO()
    with ZipFile(records,"w",compression=ZIP_DEFLATED,compresslevel=9) as z:
        for f in names:z.write(f,f.name)
    print(f"STOCK_FARM_FACTORY_ART_PASS: {len(names)} runtime assets, {len(records.getvalue())/1024:.1f} KiB compressed (excludes editable source).")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-layout")
    p.add_argument("--upstream-art")
    test(p.parse_args())
