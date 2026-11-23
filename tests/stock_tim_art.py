#!/usr/bin/env python3
"""Check RC1 T.I.M. and AsiaStar data and native paired art, wire clearance and split geometry."""
from argparse import ArgumentParser
from pathlib import Path
import re
import struct
import zlib

from chaney_jubilee_art import tread_clearance
from manley_morel_art import pair
from rail_sh_collector_art import read_faces, PIVOT_Y, PIVOT_Z, SHOE
from rail_span_art import along_ray,load
from rail_wagon_art import mesh

ROOT=Path(__file__).resolve().parents[1]
STOCK={
    "tim":dict(id=25,name="T.I.M.",intro=23376,model=30,stats=(21,40,240,7000,90,240),
               axles=(-.259,-.189,.181,.255),
               main=("Wide_divided_driving_windscreen","Directional_rapidly_tapering_traction_cooling_slats","Rebated_streamlined_stock_gangway")),
    "asiastar":dict(id=26,name="AsiaStar",intro=26298,model=50,stats=(23,43,264,8000,95,250),
                    axles=(-.251,-.183,.185,.259),
                    main=("Broad_flush_front_cab_glazing","Separate_pressed_copper-nickel_exchanger_vanes","Tinted_rear_corridor_bellows_and_suspension_gasket")),
}
EPS=2e-6

def atlas(path):
    data=path.read_bytes()
    width,height=struct.unpack_from(">II",data,16)
    assert data[24:26]==bytes((8,2))
    i=8; payload=b""
    while i<len(data):
        n,kind=struct.unpack_from(">I4s",data,i)
        if kind==b"IDAT":payload+=data[i+8:i+8+n]
        i+=n+12
    assert height==8
    decoded=zlib.decompress(payload)
    assert decoded[0]==0
    return width,decoded[1:1+3*width]

def test(source,variant):
    data=STOCK[variant]
    name="rail_"+variant
    def normalize(text):
        return "".join(text.split())
    if source:
        rows=[r for r in source.read_text().splitlines()
              if re.search(rf"//\s*{data['id']} '{re.escape(data['name'])}'", r)]
        sprite,cost,spd,power,mass,run=data['stats']
        assert len(rows)==2
        assert normalize(f"MM({data['intro']},20,25,{data['model']},CT_NONE,LandscapeTypes({{T}}))") in normalize(rows[0])
        assert normalize(f"RVI({sprite},M,{cost},{spd},{power},{mass},{run},RC_E,0,C,E)") in normalize(rows[1])
    full=read_faces(name);body=read_faces(name+"_body");collector=read_faces("rail_sh_collector")
    assert set(full)==set(body)|set(collector) and not set(body)&set(collector)
    assert all(full[k]==v for k,v in body.items())
    def rounded(v):return tuple(tuple(round(k,6) for k in p) for p in v)
    for n,faces in collector.items():
        restored=[(rounded([(x,z+PIVOT_Z,y+PIVOT_Y) for x,z,y in nodes]),j) for nodes,j in faces]
        reference=[(rounded(nodes),j) for nodes,j in full[n]]
        assert restored==reference,n
    assert abs(max(y for tri,_ in full[SHOE] for _,_,y in tri)-.784)<EPS
    textures=ROOT/"mods/luanttd_core/textures"
    a,pa=atlas(textures/f"bl_{name}.png");b,pb=atlas(textures/"bl_rail_sh_30.png")
    assert a==b==296 and pa!=pb
    # OBJ UV indices choose the same slot colors in the new whole asset
    # and the existing shared collector. Confirm all rail-native indices.
    used={int(u*a/8) for faces in collector.values() for _,uv in faces for u,_ in uv}
    for j in used:
        assert pa[j*24:(j+1)*24]==pb[j*24:(j+1)*24],j
    m=mesh(name)
    assert set(data["main"])<=m.keys()
    q=m["Coupler_knuckles"]
    assert min(z for _,z,_ in q)==-.499 and max(z for _,z,_ in q)==.499
    c=[]
    for side,sign in (("L",-1),("R",1)):
        tread=m["Rolling_tread_SH30_"+side]
        assert {round(z,6) for _,z,h in tread if abs(h)<EPS}==set(data["axles"])
        for pos in data["axles"]:
            xs=[x for x,z,h in tread if abs(z-pos)<EPS and abs(h)<EPS]
            assert min(xs)<sign*.212<max(xs)
            c.append((sign,pos,min(xs),max(xs)))
    assert len(c)==8
    bore=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    samples={(round(x,4),round(h,4)) for p in m.values() for x,_,h in p}
    for x,h in samples:
        for z in (.65,.77,.92):
            assert h+.114-.5+.035<min(along_ray(bore,2,x,z)),(x,h,z)
    assert (ROOT/"art"/f"{name}.blend").stat().st_size>150_000
    print(f"STOCK_{variant.upper()}_ART_PASS #{data['id']}, exact fixed/sprung rail wire contacts, {tread_clearance(c)} rail overlaps, {pair(m)} twin poses, {3*len(samples)} tunnel checks.")

if __name__=="__main__":
    args=ArgumentParser()
    args.add_argument("--upstream-engines",type=Path)
    args.add_argument("--variant",choices=sorted(STOCK),default="tim")
    opts=args.parse_args()
    test(opts.upstream_engines,opts.variant)
