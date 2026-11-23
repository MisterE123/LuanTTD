"""Exact OpenTTD RC1 layout, native OBJ bounds, closed seam provenance.

python3 tests/stock_metal_industry_art.py --upstream-layout /path/to/build_industry.h
blender -b -t 2 --python-exit-code 1 --python tests/stock_metal_industry_art.py
Running through Blender also verifies continuous source polygons against the
sum of all clipped mesh areas. No upstream art or image tools are required.
"""
from argparse import ArgumentParser
from math import sqrt
from pathlib import Path
import re
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"mods/luanttd_core/models"
T=ROOT/"mods/luanttd_core/textures"
SITES={
    "iron_mine":(18,{(x,z):100+4*x+z for x in range(4) for z in range(4)}),
    "steel_mill":(8,{(2,1):52,(2,2):53,(3,1):54,(3,2):55,(0,0):56,(1,0):57,
          (0,1):56,(1,1):57,(0,2):56,(1,2):57,(2,0):56,(3,0):57}),
}
MUST_HAVE={
    "iron_mine":("headframe","winding_sheave","ore_crushing","tapered_riveted_steel_side",
                 "gravity_bins","rust-red_iron_ore","winding_truck","loading_siding","cut_bank"),
    "steel_mill":("blast_furnace_process_shell","refractory","preheat_heat_exchanger",
                  "rolling_and_tapping","traveling_gantry","gas_offtake","fines_and_screened_iron",
                  "slag_bin","finished_slab_ingot","siding_along_steel"),
}


def triangle_area(a,b,c):
    p=tuple(b[i]-a[i] for i in range(3))
    q=tuple(c[i]-a[i] for i in range(3))
    return .5*sqrt(sum((p[i]*q[(i+1)%3]-p[(i+1)%3]*q[i])**2 for i in range(3)))


def validate_source(path):
    text=Path(path).read_text()
    for style,(_,expected) in SITES.items():
        source=re.search(rf"\b_tile_table_{style}_0\s*\{{(.*?)\n\}};",text,re.S)
        assert source is not None, style
        rows={(int(x),int(z)):int(gfx) for x,z,gfx in
              re.findall(r"\{\{(\d+),\s*(\d+)\},\s*(\d+)\}",source[1])}
        assert rows==expected
    steel=text.split("/* Steel mill */",1)[1].split("/* Bank temperate*/",1)[0]
    mine=text.split("/* Iron ore Mine */",1)[1].split("/* Fruit plantation */",1)[0]
    rows=re.findall(r"^\s*\{(.*)\},",steel,re.M)
    assert len(rows)==6 and all("1, CT_PASSENGERS, 8, CT_IRON_ORE" in row for row in rows)
    rows=re.findall(r"^\s*\{(.*)\},",mine,re.M)
    assert len(rows)==16 and all("0, CT_INVALID, 0, CT_INVALID" in row for row in rows)


def inspect(p,id,gfx,dx,dz,palette):
    rows=p.read_text().splitlines()
    assert f"industry {id}, layout 0 ({dx},{dz}) GFX {gfx}" in rows[0]
    vv,uv,nn,labels=[],[],[],set()
    total=0.
    count=0
    crosses=set()
    for row in rows[1:]:
        if not row:continue
        tag,*values=row.split()
        assert tag not in {"usemtl","mtllib"}
        if tag=="o":
            labels.add(values[0].lower())
        elif tag=="v":
            x,y,z=map(float,values)
            assert -.500001<=-x<=1.500001 and -.500001<=z<=1.500001,(p,x,z)
            assert -.5<=y<=2.7,(p,y)
            vv.append((-x,z,y+.5))
        elif tag=="vt":
            u,v=map(float,values)
            assert abs(u-(len(uv)+.5)/palette)<6e-7 and v==.5
            uv.append(u)
        elif tag=="vn":
            normal=tuple(map(float,values))
            assert abs(sum(v*v for v in normal)-1)<3.1e-5
            nn.append(normal)
        elif tag=="f":
            refs=[tuple(map(int,r.split("/"))) for r in values]
            assert len(refs)==3
            assert all(0<a<=len(vv) and 0<b<=len(uv) and 0<c<=len(nn) for a,b,c in refs)
            area=triangle_area(*(vv[r[0]-1] for r in refs))
            assert area>1e-9,(p,values)
            total+=area
            count+=1
            for a,_,_ in refs:
                x,z,y=vv[a-1]
                if y>.1:
                    if min(abs(x+.5),abs(x-1.5))<1e-7:crosses.add("x")
                    if min(abs(z+.5),abs(z-1.5))<1e-7:crosses.add("z")
    assert len(uv)==palette and len(labels)>=2 and count>=30,p
    assert min(y for _,_,y in vv)<.009
    return total,count,labels,crosses


def audit(opts):
    if opts.upstream_layout:
        validate_source(opts.upstream_layout)
    in_blender=False
    try:
        import bpy
        in_blender=True
    except ImportError:
        pass
    if in_blender:
        sys.path.insert(0,str(ROOT/"tools"))
        from build_stock_metal_industry_art import source_mesh
    for site,(id,layout) in SITES.items():
        if opts.site and opts.site!=site:continue
        source=ROOT/"art"/f"stock_{site}.blend"
        assert source.is_file() and source.stat().st_size>80000
        fns=set(M.glob(f"bl_industry_{site}_*_*.obj"))
        assert fns=={M/f"bl_industry_{site}_{x}_{z}.obj" for x,z in layout}
        a=T/f"bl_industry_{site}_atlas.png"
        raw=a.read_bytes()
        assert raw[:8]==b"\x89PNG\r\n\x1a\n"
        w,h=struct.unpack_from(">II",raw,16)
        assert w%8==0 and h==8
        results=[inspect(M/f"bl_industry_{site}_{x}_{z}.obj",id,gfx,x,z,w//8) for (x,z),gfx in layout.items()]
        area=sum(r[0] for r in results)
        faces=sum(r[1] for r in results)
        groups=set().union(*(r[2] for r in results))
        seams=set().union(*(r[3] for r in results))
        assert seams=={"x","z"}
        assert all(any(k in g for g in groups) for k in MUST_HAVE[site]),(site,MUST_HAVE[site])
        print(f"PASS stock {site} type {id}: {len(layout)} correctly anchored cells, {faces:,} triangles")
        if in_blender:
            bpy.ops.wm.open_mainfile(filepath=str(source))
            saved=0.
            for o in bpy.data.objects:
                if o.type=="MESH":
                    data=o.data
                    data.calc_loop_triangles()
                    saved+=sum(triangle_area(*(o.matrix_world@data.vertices[i].co for i in tri.vertices))
                               for tri in data.loop_triangles)
            m=source_mesh(site)
            rebuilt=sum(triangle_area(*(m.vertices[n][i] for i in ids))
                    for n,fl in m.parts.items() for ids,_ in fl)
            assert abs(rebuilt-saved)/rebuilt<.00001
            error=abs(area-saved)/saved
            print(f"    Saved .blend surface {saved:.6f}; all tile pieces {area:.6f}; relative difference {error:.8g}")
            assert error<.000035,(site,area,saved,error)


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--site",choices=SITES)
    p.add_argument("--upstream-layout")
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else ([] if "blender" in sys.argv[0] else sys.argv[1:])
    audit(p.parse_args(args))
