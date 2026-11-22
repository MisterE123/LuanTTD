"""Run Blender -b art/rail_ginzu_a4.blend --python-exit-code 1 --python this."""
from math import isclose, tau

import bpy

s=bpy.context.scene
assert (s.frame_start,s.frame_end,s.frame_current)==(1,65,1)
axles=[o for o in s.objects if o.name.endswith("working X axle pivot")]
assert len(axles)==10
assert sum(o.name.startswith("Main driver") for o in axles)==3
assert sum(o.name.startswith("Tender ") for o in axles)==4
assert all(len(o.children)>4 for o in axles)
p=next(x for x in axles if x.name.startswith("Main driver"))
q=next(x for x in axles if x.name.startswith("Pilot bogie"))
gear=s.objects["External split side rod with working crosshead"]
assert len(gear.data.shape_keys.key_blocks)==16

def vertices():
    dg=bpy.context.evaluated_depsgraph_get()
    return [v.co.copy() for v in gear.evaluated_get(dg).data.vertices]

base=vertices()
s.frame_set(17)
quarter=vertices()
assert isclose(p.rotation_euler.x,tau/4,rel_tol=2e-6)
assert isclose(q.rotation_euler.x,tau/4*.059/.030,rel_tol=2e-6)
assert max((v-w).length for v,w in zip(base,quarter))>.01
s.frame_set(65)
end=vertices()
assert all((v-w).length<1e-6 for v,w in zip(base,end))
print("GINZU_RIG_PASS: ten real pivots, separately sprung tender wheelsets, live quartered rods return to whole-turn base.")
