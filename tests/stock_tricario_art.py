#!/usr/bin/env python3
"""Stock RC1 Tricario data, three independent meshes and real tire/deck contact."""
# SPDX-License-Identifier: GPL-2.0-only
from math import cos,hypot,pi,sin
from pathlib import Path
import re
import struct
import subprocess
import sys
from darwin_100_art import ROOT, CORE, mesh

if len(sys.argv)>1:
    engines=Path(sys.argv[1]).read_text()
    assert re.search(r"MA\(\s*13575,\s*20,\s*20,\s*40,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*253 Tricario Helicopter",engines)
    assert re.search(r"AVI\(\s*9,\s*15,\s*81,\s*H,\s*SND_09_TAKEOFF_JET,\s*20,\s*25,\s*15,\s*40\s*\),\s*//\s*38 Tricario Helicopter",engines)
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    verify='''local a=dofile("mods/luanttd_core/openttd/airport_roster.lua")
    local p,r=assert(a.quote(253)),assert(a.entry(253))
    assert(r.helicopter and r.image==9 and r.intro_after_1920==13575 and r.life==20 and r.model_life==40)
    assert(p.price==41015 and p.annual_fp==777600 and p.max_speed==320 and p.acceleration==20 and p.mail==15 and p.passengers==40)
    for _,v in ipairs(a.catalog()) do assert(v.stock_id~=253) end'''
    subprocess.run([lua,"-e",verify],check=True,cwd=ROOT)

stems=("tricario_heli","tricario_heli_rotor","tricario_heli_tail")
(p,faces),(r,main),(t,tail)=[mesh(CORE/"models"/f"bl_stock_{s}.obj") for s in stems]
assert (ROOT/"art/stock_tricario_heli.blend").stat().st_size>120000
png=(CORE/"textures/bl_stock_tricario_heli_atlas.png").read_bytes()
assert struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
assert len(faces)>3500 and 112<len(main)<150 and 75<len(tail)<120
assert .553<=max(hypot(x,z) for x,y,z in r)<=.570
assert .152<=max(hypot(y,z) for x,y,z in t)<=.161
wheels=sorted({(x,z) for x,y,z in p if y==0})
assert len(wheels)==6 and len({round(x,3) for x,z in wheels})==6
assert min(y for x,y,z in p)==0 and max(y for x,y,z in p)>.424
# Exact pad from the generated OBJ. Both heading variants that can occur
# around the approach and the final turn are verified at every sixteenth
# of a tile; the flight controller doesn't need to cheat or teleport.
deck=CORE/"models/bl_industry_oil_rig_1_0.obj"
vp,boxes=[],[]
for line in deck.read_text().splitlines()[1:]:
    k,*f=line.split()
    if k=="o":g=f[0]
    if k=="v":
        x,y,z=map(float,f)
        vp.append((2-x,z,y+.5))
    elif k=="f" and g.startswith("Clear_green_"):
        a=[vp[int(i.split("/")[0])-1] for i in f]
        if all(y==6.75 for x,z,y in a):
            boxes.append(tuple((min(v),max(v)) for v in zip(*a)))
assert boxes
for k in range(23,32):
    for d in range(8):
        a=d*pi/4
        for x,z in wheels:
            u=k/8-.5+x*cos(a)-z*sin(a)
            v=.625+x*sin(a)+z*cos(a)
            assert any(X[0]<=u<=X[1] and Z[0]<=v<=Z[1] for X,Z,_ in boxes),(k,d,u,v)
print("PASS Tricario #253 original Blender cabin, 3 fixed tires and independently driven rotors; 432 worst-heading wheel contacts on oil-rig terminal")
