#!/usr/bin/env python3
"""Native Yate #211 mesh tests: waterline, unique holds, depot and lock bore.

Supply an unpacked OpenTTD 14.1 source tree (or flat pinned source files) as
the optional argument to independently check stock roster and unchanged sprite.
"""
from math import isclose
from pathlib import Path
import re
import struct
import sys

from ship_facility_art import read, points, ray
from ship_lock_art import DIRECTIONS

ROOT = Path(__file__).resolve().parents[1]


def source(root):
    root = Path(root)
    e = next(p for p in (root/"engines.h",root/"src/table/engines.h") if p.is_file()).read_text()
    s = next(p for p in (root/"ship_cmd.cpp",root/"src/ship_cmd.cpp") if p.is_file()).read_text()
    assert re.search(r"MS\(\s*2557,\s*5,\s*30,\s*55,\s*CT_GOODS\s*,\s*T\|A\|S\s*\).*// 211 Yate Cargo ship",e)
    assert re.search(r"SVI\(\s*0,\s*128,\s*1,\s*48,\s*160,\s*150,\s*SND_06_DEPARTURE_CARGO_SHIP,\s*1\s*\).*//\s+7 Yate Cargo ship",e)
    fn = s[s.index("void Ship::GetImage("):].split("\n}\n",1)[0]
    assert "result->Set(_ship_sprites[spritenum] + direction);" in fn
    assert "cargo" not in fn and "load" not in fn


def main():
    atlas = ROOT/"mods/luanttd_core/textures/bl_yate_cargo_ship_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24]) == (256,8)
    mesh=read("yate_cargo_ship",True)
    assert "Yate_Cargo_Ship_211" in mesh
    shape=points(mesh)
    assert -.923 < min(z for x,z,h in shape) < -.912 # nose in Luanti local -Z
    assert .912 < max(z for x,z,h in shape) < .923
    assert .349 < max(abs(x) for x,z,h in shape) < .355
    assert -.190 < min(h for x,z,h in shape) < -.181
    assert .819 < max(h for x,z,h in shape) < .831
    polygons=mesh["Yate_Cargo_Ship_211"]
    assert 10000 < len(polygons) < 16000
    colors={i:set() for i in range(32)}
    for verts, uv in polygons:
        assert all(a==uv[0] for a in uv)
        u,v=uv[0]
        i=int(u*32)
        assert isclose(u,(i+.5)/32,abs_tol=1e-6) and abs(v-.5)<1e-7
        colors[i].update((x/.925,z/.923,h) for x,z,h in verts)
    # Two watertight dark hatches divided by a deliberate transverse walk,
    # amidships derrick work and aftermost cream accommodation.
    hatch={q for i in (15,16) for q in colors[i] if .211 < q[2] < .263}
    fore={z for x,z,h in hatch if z<0}
    aft={z for x,z,h in hatch if z>-.10 and z<.27}
    assert fore and aft and max(z for z in fore if z<-.14)<-.23
    assert min(aft)>-.099 and max(aft)>.21
    assert not [q for q in hatch if -.237<q[1]<-.102], "Two hold covers need a true walk between them"
    boom=colors[18]|colors[19]|colors[20]
    assert max(h for x,z,h in boom)>.554 and min(z for x,z,h in boom)<-.622
    assert any(z<-.55 for x,z,h in boom) and any(-.20<z<-.13 for x,z,h in boom)
    assert min(z for x,z,h in colors[21] if h>.33)>.410
    # The boot stripe sits on both sides of the actual waterplane.
    boot=colors[0]
    assert min(h for x,z,h in boot)<-.010 and max(h for x,z,h in boot)>.015
    assert sum(.342<x<.380 and abs(z)<.50 for x,z,h in boot)>=8
    assert sum(-.380<x<-.342 and abs(z)<.50 for x,z,h in boot)>=8
    gauge=.355
    ray_count=0
    for axis in (0,1):
        for part in (0,1):
            depot=read(f"ship_depot_{axis}_{part}")
            for p in (-gauge,-.24,-.087,0,.06,.21,gauge):
                for h in (-.191,0,.152,.237,.407,.567,.687,.831):
                    assert not ray(depot,axis,p,h,-1.0001,1.0001)
                    ray_count+=1
    for d,(dx,dz) in enumerate(DIRECTIONS):
        for label,hbase in (("lower",0),("middle",0),("upper",1)):
            lock=read(f"ship_lock_{label}_{d}")
            for phase in (0,.375,.75,1):
                for t in (-gauge,-.21,0,.21,gauge):
                    for h in (-.191,0,.258,.56,.831):
                        assert not ray(lock,0 if dx else 1,t,h+phase-hbase,-1.0001,1.0001)
                        ray_count+=1
    for key,anchor,sign in (("lower",-1.115,-1),("upper",1.115,1)):
        gate=read(f"ship_lock_gate_{key}_closed",True)
        clear = min(sign*(z+anchor) for x,z,h in points(gate)) - max(abs(z) for x,z,h in shape)
        assert clear > .031, clear
        opened=read(f"ship_lock_gate_{key}_open",True)
        for p in (-gauge,-.20,0,.22,gauge):
            for h in (-.191,0,.258,.569,.831):
                assert not ray(opened,1,p,h,-1.0,1.0)
                ray_count+=1
    if len(sys.argv)>1: source(sys.argv[1])
    print(f"PASS: genuine Yate pair of sealed holds, twin derricks, source-color aft bridge, exact native waterline, {ray_count} clear harbour bore rays, both closed lock gates clear the actual hull")


if __name__ == "__main__":
    main()
