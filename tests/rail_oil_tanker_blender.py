"""Verify the authoring scene's motion pivots and original-only collections."""
from math import tau
import bpy

scene=bpy.context.scene
assert len(bpy.data.images)==0
assert (scene.frame_start,scene.frame_end)==(1,49)
assert set(c.name for c in scene.collection.children)=={
  "Riveted sealed tank, mounts and original fleet lettering",
  "Separate ladders, valves and manifold","Dished red oxide frame and fitted suspension",
  "Editable oil wagon axle 1","Editable oil wagon axle 2",
}
for frame,angle in ((1,0),(7,tau/4),(49,2*tau)):
    scene.frame_set(frame)
    for i,w in ((1,-.235),(2,.235)):
        a=bpy.data.objects[f"Axle {i} transverse pivot"]
        assert a.type=="EMPTY" and len(a.children)>=7
        assert abs(a.location.y-w)<1e-6 and abs(a.location.z-.067)<1e-6
        assert abs(a.rotation_euler.x-angle)<1e-6
print("RAIL_OIL_TANKER_SOURCE_PASS: two editable wheel pivots and separate chassis, vessel and service gear.")
