"""Run Blender -b art/chaney_jubilee.blend --python-exit-code 1 --python this."""
from math import isclose, tau

import bpy

scene = bpy.context.scene
assert (scene.frame_start, scene.frame_end, scene.frame_current) == (1, 65, 1)

wheels = [o for o in scene.objects if o.type == "EMPTY" and
          o.name.endswith("native X rotation")]
assert len(wheels) == 8
assert sum("Driver" in o.name for o in wheels) == 3
assert all(len(o.children) >= 4 and o.location.z > 0 for o in wheels)

r = next(o for o in scene.objects if o.name == "Eccentric main crosshead piston rod")
keys = r.data.shape_keys
assert len(keys.key_blocks) == 16
# Validate real evaluated vertex change, not just nonzero Blender timeline data.
scene.frame_set(1)
after = bpy.context.evaluated_depsgraph_get()
base = [v.co.copy() for v in r.evaluated_get(after).data.vertices]
assert all(isclose(o.rotation_euler.x, 0, abs_tol=1e-6) for o in wheels)
scene.frame_set(17)
after = bpy.context.evaluated_depsgraph_get()
moved = [v.co.copy() for v in r.evaluated_get(after).data.vertices]
assert max((b-m).length for b, m in zip(base, moved)) > .01
assert isclose(next(o for o in wheels if "Driver" in o.name).rotation_euler.x,
               tau/4, rel_tol=1e-6)
scene.frame_set(65)
after = bpy.context.evaluated_depsgraph_get()
end = [v.co.copy() for v in r.evaluated_get(after).data.vertices]
assert all((a-b).length < 1e-6 for a, b in zip(base, end))
print("JUBILEE_RIG_PASS: 8 editable wheelsets, quartered rod motion, seamless link cycle")
