#!/usr/bin/env python3
"""Original Guru X2 stock model: canopy, contact, and independent physical axes."""
from math import atan2, hypot, pi
import struct

from darwin_100_art import CORE, ROOT, mesh

def model(suffix=""):
    return mesh(CORE/"models"/f"bl_stock_guru_x2{suffix}.obj")

body,faces=model()
low,high=[tuple(op(c) for c in zip(*body)) for op in (min,max)]
assert abs(low[1])<.00002 and high[1]>.50
assert low[2]<-.50 and high[2]>.80
assert high[0]-low[0]>.39 and len(faces)>1000
png=(CORE/"textures/bl_stock_guru_x2_atlas.png").read_bytes()
assert struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
assert (ROOT/"art/stock_guru_x2.blend").stat().st_size>140000
for plane,blade_count,span,axis in (("_rotor",5,.644,1),("_tail",4,.148,0)):
    verts,rotor_faces=model(plane)
    assert rotor_faces and all(abs(v[axis])<.045 for v in verts)
    radial=[(hypot(v[1-axis],v[2]),v[1-axis],v[2]) for v in verts]
    tip_half=(.027 if axis==0 else .041)*.48
    assert abs(max(radial)[0]-hypot(span,.026+tip_half))<.001
    sectors={round((atan2(z,x)/(2*pi))*blade_count)%blade_count for r,x,z in radial if r>span*.96}
    assert len(sectors)==blade_count,(plane,sectors)
print("PASS Guru X2: exact contact, 5-blade main and 4-blade tail on distinct axes, editable source and atlas")
