#!/usr/bin/env python3
"""Check the restored MkII, Uhl, Thomas and Foster road artwork and stock geometry."""
from collections import Counter
from hashlib import sha256
from math import isclose
from pathlib import Path
import argparse
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
CORE=ROOT/"mods/luanttd_core"
MODEL=CORE/"models"
TEX=CORE/"textures"
ROWS={
 "stock_foster_mk2_bus":(.40,(.24840,.29906,.66640)),
 "stock_foster_wood_truck":(.42,(.25746,.28807,.68061)),
 "stock_thomas_grain_truck":(.42,(.25956,.28770,.68782)),
 "stock_uhl_livestock_van":(.42,(.25998,.29064,.68441)),
}
LOADED={"stock_foster_wood_truck","stock_thomas_grain_truck"}
HEAD={
 "stock_foster_mk2_bus":"True_forward_swept_lights",
 "stock_foster_wood_truck":"True_forward-facing_individually_glazed_headlamp_reflectors",
 "stock_thomas_grain_truck":"Actual_paired_forward_lens_headlamps",
 "stock_uhl_livestock_van":"Actual_wide_forward_frosted_warm_lamp",
}
TAIL={
 "stock_foster_mk2_bus":"Raised_LED_rear_luminous_row",
 "stock_foster_wood_truck":"Raised_rear_rake_red_amber_and_white_lenses",
 "stock_thomas_grain_truck":"True_aft-facing_triple_lens_bars",
 "stock_uhl_livestock_van":"Directional_replacement_rear_lamp_lenses",
}
OVERNIGHT={
 "bl_stock_foster_wood_truck.obj":"50cf48e7eb5b841cab1815a245e25e34191bd90dec546f4050c42e83515925ea",
 "bl_stock_foster_wood_truck_loaded.obj":"c42b00ccb05e5f35e77f8a0f9aa87a5c7429006e3ef1dca00ed3450f1a5c97da",
 "bl_stock_foster_wood_truck_atlas.png":"032133fbf3159f9e8a8d4536545250544298c8594fdd7fc76b38eb83b7fc32c2",
 "bl_stock_thomas_grain_truck.obj":"d22c397a74761aa0cd9c9504a92e867efbfbffe715cecc979ccb2903dfae23c7",
 "bl_stock_thomas_grain_truck_loaded.obj":"9a491d34122d6909b44530a8ff07625f059dc612c40e98825f1c75e7ea8e3b01",
 "bl_stock_thomas_grain_truck_atlas.png":"0c95c82f1a60928ef3af2bdc052174d5180fa501e03e6ce93bff2d94a50e9200",
 "bl_stock_uhl_livestock_van.obj":"b0981e115c854d6f70937af4f9eba7b6a29e671202cf6122f6a0d6e524eca0f1",
 "bl_stock_uhl_livestock_van_atlas.png":"dd17fb715150403b56dbb777e15a03df517621919868433d603aea60f23f4f3f",
}


def mesh(path,scale):
    vertices=[];uv=[];normals=[];groups={};name=None
    for line in path.read_text().splitlines():
        k,*bits=line.split()
        if k=="v":
            x,y,z=map(float,bits)
            vertices.append((-x*scale/10,y*scale/10,z*scale/10))
        elif k=="vt":
            u,v=map(float,bits)
            assert isclose(u,(len(uv)+.5)/64,abs_tol=1e-6) and v==.5
            uv.append(u)
        elif k=="vn":
            n=tuple(map(float,bits))
            assert isclose(sum(x*x for x in n),1,abs_tol=1e-4)
            normals.append(n)
        elif k=="o":
            name=bits[0]
        elif k=="f":
            assert len(bits)==3 and name
            ii,t,nn=zip(*(map(int,c.split("/")) for c in bits))
            assert len(set(ii))==3 and len(set(t))==len(set(nn))==1
            assert all(1<=i<=len(vertices) for i in ii) and 1<=t[0]<=len(uv) and 1<=nn[0]<=len(normals)
            groups.setdefault(name,[]).append((tuple(vertices[i-1] for i in ii),t[0],normals[nn[0]-1]))
        else:
            assert k.startswith("#"),k
    assert len(uv)==64 and len(groups)>=50
    return vertices,groups


def bounds(v):
    return [tuple(fn(a) for a in zip(*v)) for fn in (min,max)]


def closed(faces):
    edges=Counter(tuple(sorted((a,b))) for p,_,_ in faces for a,b in zip(p,(p[1],p[2],p[0])))
    assert set(edges.values())=={2},Counter(edges.values())


def horizontal_hit(triangle,y,z):
    (ax,ay,az),(bx,by,bz),(cx,cy,cz)=triangle
    dy,dz=by-ay,bz-az
    ey,ez=cy-ay,cz-az
    det=dy*ez-dz*ey
    if abs(det)<1e-12:return None
    u=((y-ay)*ez-(z-az)*ey)/det
    v=(dy*(z-az)-dz*(y-ay))/det
    if min(u,v,1-u-v)<-1e-08:return None
    return ax+u*(bx-ax)+v*(cx-ax)


def inspect(stem,scale,expected):
    assert (ROOT/"art"/f"{stem}.blend").stat().st_size>100_000
    png=(TEX/f"bl_{stem}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(1024,16,8,2,0,0,0)
    obj=MODEL/f"bl_{stem}.obj"
    v,g=mesh(obj,scale)
    low,high=bounds(v)
    dims=tuple(b-a for a,b in zip(low,high))
    assert all(isclose(a,b,abs_tol=.00001) for a,b in zip(dims,expected)),(stem,dims)
    assert low[1]==0 and -.35<low[2]<-.319
    for side in (-1,1):
        lane=(low[0]+side*.155,high[0]+side*.155)
        assert min(abs(x) for x in lane)>.024
        assert max(abs(x) for x in lane)<.3125-.024
    treads={(x,z) for x,y,z in v if y==0}
    assert len(treads)==8 and len({z for _,z in treads})==2
    assert min(n[2] for _,_,n in g[HEAD[stem]])<-.90
    assert min(z for p,_,_ in g[TAIL[stem]] for _,_,z in p)>.30
    load=MODEL/f"bl_{stem}_loaded.obj"
    if stem in LOADED:
        assert load.read_bytes().startswith(obj.read_bytes()),"Load cannot change permanent structure."
        lv,lg=mesh(load,scale)
        assert bounds(lv)==[low,high] and all(lg[k]==g[k] for k in g)
        assert {(x,z) for x,y,z in lv if y==0}==treads
        if "wood" in stem:
            cargo=[faces for name,faces in lg.items() if name.startswith("Foster_removable_round_timber_")]
            assert len(cargo)==24
            assert len(lg["Loaded-only_twin_galvanised_timber_binder_straps"])==336
            for log in cargo:
                closed(log)
                assert any(n[2]<-.90 for _,_,n in log) and any(n[2]>.90 for _,_,n in log)
                assert len({c for _,c,_ in log})>=10
        else:
            shell="Watertight_thin_pressed_steel_open-top_tapered_hopper_shell"
            grain="Closed_molded_golden_grain_volume"
            kernels="Separate_real_convex_hull_grain_kernels"
            assert set(lg)-set(g)=={grain,kernels}
            assert len(lg[kernels])==482*10
            assert len(lg[grain])>1200
            for grp in (shell,grain,kernels):closed(lg[grp])
            assert max(y for p,_,_ in lg[grain] for _,y,_ in p)>.211
            assert g["Top-swing_visible_greased_gate_hinge_pins"] and g["Chrome_tipping_piston_extension"]
    else:
        assert not load.exists()
    if "livestock" in stem:
        roof="Closed_thin_charcoal_canvas_cover_arched_across_the_van"
        closed(g[roof])
        crown=[n for p,_,n in g[roof] if max(t[1] for t in p)>.290]
        assert crown and min(n[1] for n in crown)>.85
        assert len(g["Individually_pitched_open_side_livestock_ventilation_slats"])==288
        triangles=[tri for group in g.values() for tri,col,n in group]
        for side in (-1,1):
            for z in (-.057,.163,.393,.625):
                for y,blocked in ((.449,True),(.473,False),(.493,True),(.517,False),(.537,True)):
                    hits=(horizontal_hit(p,y*scale,z*scale) for p in triangles)
                    assert any(x is not None and .086 < side*x < .145 for x in hits)==blocked,(side,z,y)
    if "mk2" in stem:
        for shell in ("Continuous_low-floor_outer_skin_with_actual_wheel_and_door_relief",
                      "Crowned_single-deck_composite_passenger_coach_shell"):
            closed(g[shell])
        assert len(g["Individually_modeled_plug-sliding_door_leaves"])==112
        pane=g["Front_Continuous_curved_laminated_driver_pane"]
        assert len(pane)>=80 and min(n[2] for _,_,n in pane)<-.45
    print(f"PASS {stem}: grounded at Y=0, W/H/L "+"/".join(f"{d:.5f}" for d in dims)+
          "; distinct geometry/role and correct native envelope.")


def stock_fixture(repo):
    sys.path.insert(0,str(repo/"tests"))
    import road_corner_art as corners
    import level_crossing_art as crossing
    files={p.name:p for p in MODEL.glob("bl_stock_*.obj")}
    orig=corners.obj
    corners.obj=lambda path,*args:orig(files.get(path.name,path),*args)
    corners.STEMS={key:scale for key,(scale,_) in ROWS.items()}
    corners.STEMS.update({key+"_loaded":ROWS[key][0] for key in LOADED})
    corners.stock(corners.visual())
    count=0
    obj=crossing.obj
    # The earlier checkpoint used two legacy names; newer fixtures give the
    # same slots to stock assets. Substitute only the matching road scale.
    refs={.40:("bl_stock_hereford_leopard.obj","bl_leopard_bus.obj"),
          .42:("bl_stock_balogh_coal_loaded.obj","bl_coal_tipper_loaded.obj")}
    for axis in (0,1):
        real={s:crossing.active_groups(crossing.M/f"bl_level_crossing_{axis}_{s}.obj",axis)
              for s in ("open","closed")}
        for key,scale in corners.STEMS.items():
            def replace(path,*args):
                return obj(files[f"bl_{key}.obj"] if path.name in refs[scale] else path,*args)
            crossing.obj=replace
            count+=crossing.clearance(axis,real)
    crossing.obj=obj
    assert count==6*2904,count
    print(f"PASS {count:,} stock crossing fixture poses total (two axes × six mesh states/candidates).")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--road-fixtures",type=Path)
    opt=p.parse_args()
    for file,digest in OVERNIGHT.items():
        where=TEX if file.endswith(".png") else MODEL
        assert sha256((where/file).read_bytes()).hexdigest()==digest,file
    print("PASS all eight known overnight production hashes are byte-identical.")
    for key,(scale,expected) in ROWS.items():inspect(key,scale,expected)
    if opt.road_fixtures:stock_fixture(opt.road_fixtures.resolve())
