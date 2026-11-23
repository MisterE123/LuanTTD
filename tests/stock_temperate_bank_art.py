"""Validate RC1 Temperate Bank identity, native mounting, bay and whole mesh seams.

python3 tests/stock_temperate_bank_art.py --upstream-layout /path/build_industry.h
blender -b -t 2 --python-exit-code 1 --python tests/stock_temperate_bank_art.py
"""
from argparse import ArgumentParser
from math import sqrt
from pathlib import Path
import re
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
STEM="industry_temperate_bank"
LAYOUT={(0,0):58,(1,0):59}


def area(a,b,c):
    p=tuple(b[i]-a[i] for i in range(3))
    q=tuple(c[i]-a[i] for i in range(3))
    return .5*sqrt(sum((p[i]*q[(i+1)%3]-p[(i+1)%3]*q[i])**2 for i in range(3)))


def source(path):
    txt=Path(path).read_text()
    def stock(name):
        table=re.search(rf"\b_tile_table_{name}_0\s*\{{(.*?)\n\}};",txt,re.S)[1]
        return {(int(x),int(z)):int(gfx) for x,z,gfx in
                re.findall(r"\{\{(\d+),\s*(\d+)\},\s*(\d+)\}",table)}
    assert re.search(r"IT_BANK_TEMP\s*=\s*12",txt)
    assert re.search(r"IT_BANK_TROPIC_ARCTIC\s*=\s*16",txt)
    assert stock("bank")==LAYOUT and stock("bank2")=={(0,0):89,(1,0):90}
    bank=txt.split("MI(_tile_table_bank,",1)[1].split("MI(_tile_table_food_process,",1)[0]
    assert "LandscapeType::Temperate" in bank and "IndustryBehaviour::Town1200More" in bank
    rows=txt.split("/* Bank temperate*/",1)[1].split("/* Food processing plant",1)[0]
    assert "CT_PASSENGERS, 8, MCT_VALUABLES_GOLD_DIAMONDS, 0, CT_INVALID, SLOPE_E" in rows
    assert "CT_PASSENGERS, 8, MCT_VALUABLES_GOLD_DIAMONDS, 0, CT_INVALID, SLOPE_S" in rows


def mounted(dx,dz,gfx,colors):
    mesh=MOD/"models"/f"bl_{STEM}_{dx}_{dz}.obj"
    vertices,names,normals=[],set(),[]
    uvs,faces=0,0
    measured_area=0.
    groups_at_seam=set()
    lines=mesh.read_text().splitlines()
    assert f"Temperate Bank ID 12, layout 0 ({dx},{dz}) GFX {gfx}" in lines[0]
    for row in lines[1:]:
        if not row:continue
        tag,*vals=row.split()
        assert tag not in {"usemtl","mtllib"}
        if tag=="o":
            current=vals[0].lower()
            names.add(current)
        elif tag=="v":
            x,h,z=map(float,vals)
            assert -.500001<=-x<=1.500001 and -.500001<=z<=1.500001 and -.501<=h<=1.55
            vertices.append((-x+2*dx,z+2*dz,h+.5))
        elif tag=="vt":
            u,v=map(float,vals)
            assert abs(u-(uvs+.5)/colors)<6e-7 and v==.5
            uvs+=1
        elif tag=="vn":
            normal=tuple(map(float,vals))
            assert abs(sum(v*v for v in normal)-1)<3.1e-5
            normals.append(normal)
        elif tag=="f":
            refs=[tuple(map(int,r.split("/"))) for r in vals]
            assert len(refs)==3
            assert all(1<=v<=len(vertices) and 1<=uv<=uvs and 1<=n<=len(normals) for v,uv,n in refs)
            points=[vertices[v-1] for v,_,_ in refs]
            x,z,h=zip(*points)
            # Actual geometric clearance, not a duplicate floor superimposed
            # on a solid box. Entire cargo width is open beyond the bollards.
            if gfx==59:
                assert max(x)<2.24 or min(x)>3.12 or max(z)<.65 or min(z)>1.48 or max(h)<.11 or min(h)>.739,(current,points)
            if min(abs(a-1.5) for a in x)<1e-7:
                groups_at_seam.add(current)
            val=area(*points)
            assert val>1e-9
            measured_area+=val
            faces+=1
    assert uvs==colors and len(names)>25 and faces>2500
    assert min(h for _,_,h in vertices)<=.008
    assert any("upper_sandstone_footing_crossing_seam" in n for n in groups_at_seam)
    assert any("lower_coping_continuous_across_seam" in n for n in groups_at_seam)
    required={58:("banking_hall","individual_smooth_courtyard","separate_bronze_double_door",
                  "raised_bank_characters","curved_translucent_fanlight","classical_entasis","pediment"),
              59:("vaulted_tinted_clerestory","standing_copper_seams","recessed_vault_receiving",
                  "metal_roller_shutter","annex_actual_car_apron","structural_outer_pier")}
    for text in required[gfx]:
        assert any(text in n for n in names),(gfx,text)
    print(f"PASS Temperate Bank GFX {gfx}: 2×2-node native anchor, {faces:,} correctly indexed triangles.")
    return measured_area


def main(opts):
    if opts.upstream_layout:
        source(opts.upstream_layout)
    assert {p.name for p in (MOD/"models").glob(f"bl_{STEM}_*.obj")}=={
        f"bl_{STEM}_{x}_{z}.obj" for x,z in LAYOUT}
    p=MOD/"textures"/f"bl_{STEM}_atlas.png"
    png=p.read_bytes()
    assert png[:8]==b"\x89PNG\r\n\x1a\n"
    w,h=struct.unpack_from(">II",png,16)
    assert h==8 and w%8==0
    clipped=sum(mounted(x,z,gfx,w//8) for (x,z),gfx in LAYOUT.items())
    path=ROOT/"art"/"stock_temperate_bank.blend"
    assert path.stat().st_size>120000
    try:
        import bpy
    except ImportError:
        return
    bpy.ops.wm.open_mainfile(filepath=str(path))
    full=0.
    for o in bpy.context.scene.objects:
        if o.type=="MESH":
            m=o.data
            m.calc_loop_triangles()
            full+=sum(area(*(o.matrix_world@m.vertices[i].co for i in f.vertices)) for f in m.loop_triangles)
    error=abs(full-clipped)/full
    assert error<.000025,(full,clipped,error)
    print(f"PASS whole editable Bank geometry: area {full:.7f}, sum of independent tiles {clipped:.7f}, relative seam loss {error:.6g}")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-layout")
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else ([] if "blender" in sys.argv[0] else sys.argv[1:])
    main(p.parse_args(args))
