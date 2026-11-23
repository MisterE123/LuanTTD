#!/usr/bin/env python3
"""Geometry, bundle, and original City Airport clearance for four Darwin jets."""
import argparse
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re
import struct

from darwin_100_art import (
    AIRCRAFT_SHA, CORE, ROOT, bore_test, city_ground_art, city_source, mesh
)

# Ground and air OBJ at Luanti node scale. Test each distinctive under-wing
# intake's actual empty recess, not just whether its geometry is nonempty.
DATA = {
    200: dict(width=1.4176, length=1.550, height=.48384, tires=6, motor=(.261,.112,.197,.052)),
    400: dict(width=1.7776, length=2.043, height=.61584, tires=10, motor=(.322,.147,.165,.096)),
    500: dict(width=1.8696, length=2.016, height=.65784, tires=10, motor=(.358,.158,.212,.113)),
    600: dict(width=1.9656, length=2.129, height=.72284, tires=14, motor=(.387,.169,.221,.129)),
}

def check(series, data, opt):
    path=CORE/"models"/f"bl_stock_darwin_{series}.obj"
    model, faces=mesh(path)
    flight, air_faces=mesh(CORE/"models"/f"bl_stock_darwin_{series}_flight.obj")
    assert (ROOT/"art"/f"stock_darwin_{series}.blend").stat().st_size>140_000
    png=(CORE/"textures"/f"bl_stock_darwin_{series}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    low,high=[tuple(op(c) for c in zip(*model)) for op in (min,max)]
    assert abs(high[0]-low[0]-data["width"])<.00003
    assert abs(high[2]-low[2]-data["length"])<.00003
    assert low[1]==0 and abs(high[1]-data["height"])<.00004 and low[2]<0<high[2]
    wheels={(x,z) for ps,c in faces if c in (25,26) for x,y,z in ps if y==0}
    assert {(x,z) for x,y,z in model if y==0}==wheels and len(wheels)==2*data["tires"]
    assert min(v[1] for v in flight)>.032 and not any(c==25 or c==26 for _,c in air_faces)
    # Gear exports must not accidentally diverge on windows, turbine
    # bores, cabin doors, livery, or wing/tail exterior geometry.
    g=Counter((tuple(sorted(ps)),c) for ps,c in faces if min(v[1] for v in ps)>.215)
    a=Counter((tuple(sorted(ps)),c) for ps,c in air_faces if min(v[1] for v in ps)>.215)
    # Closed gear bay skins can sit higher on tall models; most scenery
    # shall compare exactly, and wing tips/top and other bounds must match.
    assert sum((g&a).values())>.995*sum(g.values())
    assert max(y for _,y,_ in flight)==high[1] and min(z for _,_,z in flight)==low[2]
    x,h,y,r=data["motor"]
    bore_test(faces,((-x,h,y,.84*r),(x,h,y,.84*r)))
    print(f"PASS Darwin {series}: distinct W/L/H {data['width']:.3f}/{data['length']:.3f}/{data['height']:.3f}, "
          f"{len(wheels)//2} grounded tires, open nacelles, gear doors and separate clean flight export",flush=True)
    if opt.city_model_dir:
        tire_rows=city_source(opt,wheels) if opt.city_movement else None
        city_ground_art(opt,tire_rows,path)
    return png

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--series",type=int,choices=DATA)
    for key in ("aircraft","city-movement","city-layout","city-model-dir","city-ground-poses"):
        p.add_argument("--"+key,type=Path)
    p.add_argument("--city-prefix",default="bl_city_airport_")
    opt=p.parse_args()
    assert bool(opt.city_movement)==bool(opt.city_layout)
    assert bool(opt.city_model_dir)==bool(opt.city_ground_poses)
    if opt.aircraft:
        blob=opt.aircraft.read_bytes()
        assert sha256(blob).hexdigest()==AIRCRAFT_SHA
        table=re.search(r"_aircraft_sprite\[\]\s*=\s*{([^}]+)}",blob.decode())[1]
        assert int(table.split(",")[4],0)==0x0ED5
        print("PASS source aircraft sprite image 4 resolves to shared 0x0ED5; no source artwork embedded")
    variants={opt.series:DATA[opt.series]} if opt.series else DATA
    assert len({check(series,row,opt) for series,row in variants.items()})==len(variants)
