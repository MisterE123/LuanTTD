#!/usr/bin/env python3
"""Validate four original RC1 Bakewell Luckett ground and flight airframes."""
from argparse import ArgumentParser
from collections import Counter
from hashlib import sha256
from pathlib import Path
import re
import struct

from darwin_100_art import AIRCRAFT_SHA, CORE, ROOT, bore_test, city_ground_art, city_source, mesh

# Ground dimensions, deployed tires, and geometric intake axes measured in
# nodes. Includes independent, unobstructed centerline engine geometry.
AIRFRAMES = {
    "9": (1.43597, 1.612, .56161, 6, (.180, .253, -.363, .059), None),
    "80": (1.64797, 2.162, .63661, 6, (.186, .291, -.550, .074), None),
    "10": (1.85797, 2.034, .70361, 10, (.364, .160, .240, .103), (.509, -.540, .101)),
    "11": (1.92352, 2.220, .73961, 12, (.386, .163, .207, .111), (.532, -.623, .105)),
}

def verify(series, dims, args):
    w,l,h,tires,motor,dorsal=dims
    key=f"stock_bakewell_luckett_lb{series}"
    path=CORE/"models"/f"bl_{key}.obj"
    air=path.with_name(path.stem+"_flight.obj")
    m,f=mesh(path); a,g=mesh(air)
    assert (ROOT/"art"/f"{key}.blend").stat().st_size>140_000
    png=(CORE/"textures"/f"bl_{key}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    low,high=[tuple(op(c) for c in zip(*m)) for op in (min,max)]
    assert abs(high[0]-low[0]-w)<.00007
    assert abs(high[2]-low[2]-l)<.00007
    assert abs(high[1]-h)<.00007 and low[1]==0
    wheels={(x,z) for p,c in f if c in (25,26) for x,y,z in p if y==0}
    assert {(x,z) for x,y,z in m if y==0}==wheels and len(wheels)==2*tires
    assert min(v[1] for v in a)>.030 and not any(c in (25,26) for _,c in g)
    assert all(max(p[i] for p in a)==high[i] for i in range(3))
    k=Counter((tuple(sorted(ps)),c) for ps,c in f if min(v[1] for v in ps)>.228)
    b=Counter((tuple(sorted(ps)),c) for ps,c in g if min(v[1] for v in ps)>.228)
    assert sum((k&b).values())>.995*sum(k.values())
    # Includes actual original doors/cockpit details and a modest export
    # budget: no need to fill an entire map with high-poly decorative meshes.
    assert len(m)>=5000 and len(m)<10500 and len(a)>5000 and path.stat().st_size<700_000
    x,y,z,r=motor
    bores=[(-x,y,z,.839*r),(x,y,z,.839*r)]
    if dorsal: bores.append((0,dorsal[0],dorsal[1],.839*dorsal[2]))
    for view in (f,g): bore_test(view,bores)
    if series=="11":
        # Both sides have an upright winglet, substantial enough to read
        # in the compressed simulator and much higher than the wing tip.
        for s in (-1,1):
            assert max(y for x,y,z in m if s*x>.87)>.49
    print(f"PASS Bakewell LB{series}: {len(bores)} open nacelles, {tires} rolling wheels, editable gear-up/down shape",flush=True)
    if args.city_model_dir:
        tire_rows=city_source(args,wheels) if args.city_movement else None
        city_ground_art(args,tire_rows,path)
    return png

def main():
    p=ArgumentParser(description=__doc__)
    p.add_argument("--series",choices=AIRFRAMES)
    for key in ("aircraft","city-movement","city-layout","city-model-dir","city-ground-poses"):
        p.add_argument("--"+key,type=Path)
    p.add_argument("--city-prefix",default="bl_city_airport_")
    args=p.parse_args()
    assert bool(args.city_movement)==bool(args.city_layout)
    assert bool(args.city_model_dir)==bool(args.city_ground_poses)
    if args.aircraft:
        blob=args.aircraft.read_bytes()
        assert sha256(blob).hexdigest()==AIRCRAFT_SHA
        sprites=re.search(r"_aircraft_sprite\[\]\s*=\s*{([^}]+)}",blob.decode())[1].split(",")
        assert int(sprites[2],0)==0x0EC5 and int(sprites[3],0)==0x0ECD
        print("PASS pinned OpenTTD source image families: image 2 compact/stretched, image 3 trijets")
    planes={args.series:AIRFRAMES[args.series]} if args.series else AIRFRAMES
    assert len({verify(series,row,args) for series,row in planes.items()})==len(planes)

if __name__=="__main__":
    main()
