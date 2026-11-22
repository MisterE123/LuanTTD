"""Check editable Floss 47 scene geometry and parented bogie/rotor pivots.

blender -b art/rail_floss_47.blend -t 2 --python-exit-code 1 --python tests/floss_47_blender.py
"""
from math import pi, tau
import bpy

scene=bpy.context.scene
objects=bpy.data.objects
assert (scene.frame_start,scene.frame_end)==(1,49)
assert len(bpy.data.images)==0
scene.frame_set(1)
items=[]
for i in (1,2):
    bogie=objects[f"Bogie {i} · central pivot pivot"]
    assert bogie.type=="EMPTY" and not bogie.parent and not bogie.animation_data
    z0=bogie.matrix_world.translation.y
    zs=[]
    for a in (1,2,3):
        axle=objects[f"Bogie {i} · axle {a} pivot"]
        assert axle.parent==bogie
        assert axle.type=="EMPTY" and len(axle.children)>=7
        x,y,z=axle.matrix_world.translation
        assert abs(x)<1e-6 and abs(z-.045)<1e-6 and abs(y-z0)<.071
        zs.append(y)
        items.append((axle,0,2*tau))
    assert zs==sorted(zs) and zs[2]-zs[0]>.128
    # Swiveling one truck rotates all three wheelsets together. Existing
    # native OBJ is the neutral position, not a compatibility change.
    bogie.rotation_euler.z=pi/5
    bpy.context.view_layer.update()
    for a in (1,3):
        axle=objects[f"Bogie {i} · axle {a} pivot"]
        assert abs(axle.matrix_world.translation.x)>.035
    bogie.rotation_euler.z=0
for j in (1,2):
    fan=objects[f"Roof fan {j} pivot"]
    assert len(fan.children)==3 and not fan.parent
    assert any("Nine angled" in p.name for p in fan.children)
    items.append((fan,2,6*tau))

scene.frame_set(7) # one-eighth wheel rotation sequence
for item,axis,end in items:
    assert abs(item.rotation_euler[axis]-end/8)<1e-5
scene.frame_set(49)
for item,axis,end in items:
    assert abs(item.rotation_euler[axis]-end)<1e-5
print("FLOSS_47_SOURCE_PASS: two independent swivels, six axle pivots and two opening rotors successfully evaluated.")
