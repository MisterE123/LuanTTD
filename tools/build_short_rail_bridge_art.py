"""Original conventional railway decks for RC1 bridge #1 (cast) and #2 (girder)."""
from pathlib import Path
from sys import path

path.insert(0, str(Path(__file__).resolve().parent))
import build_road_bridge_concrete_art as concrete
import build_road_bridge_girder_art as steel
import build_rail_span_art as rail
from build_bridge_clearance_meshes import BEARING_GROUPS, clear_span
from build_bridge_pier_feet import COLUMNS, write_feet

kit, bpy = rail.kit, rail.bpy


def widen(mesh, factor):
    # Expand the original shell without touching the conserved rail gauge.
    for g, data in mesh.groups.items():
        mesh.groups[g] = [(c, tuple((u*factor,v,y) for u,v,y in tri)) for c,tri in data]


def structure(kind, h, head):
    shell = kit.Mesh()
    if kind == "concrete":
        concrete.deck(shell, h, head, road_surface=False)
        concrete.parapet(shell, h, head)
        if head:
            concrete.abutment(shell, h)
        else:
            concrete.cap(shell)
    else:
        steel.continuous(shell, h, head, road_surface=False)
    widen(shell, 1.18)
    return shell


def show_short(parts):
    kit.showcase(parts)
    scene = bpy.context.scene
    # Display two interior spans so the included scene is valid for both styles.
    for ob in list(scene.objects):
        if ob.instance_type == "COLLECTION":
            if abs(ob.location.x) < .01:
                bpy.data.objects.remove(ob, do_unlink=True)
            else:
                ob.location.x += -1 if ob.location.x > 0 else 1
        elif ob.name == "Upper bank":
            ob.location.x -= 1
        elif ob.name == "Lower bank":
            ob.location.x += 1
    scene.camera.data.ortho_scale = 11.7


def build(family, author):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.name = f"LuanTTD | Conventional railway {family}"
    stem = "rail_bridge_" + family
    kit.PREFIX = "bl_" + stem
    kit.COLORS = {**rail.COLORS, **author.COLORS, "Rail trough base": "747571",
                  "Low rail trough lip": "99948a", "Set-in drainage grille": "595951"}
    mats, parts = kit.materials(), {}
    for pose, h, head in (("span",lambda v:.5,False),("head_flat",lambda v:.5,True),
                           ("head_ramp",lambda v:v/2,True)):
        mesh = structure(family,h,head)
        # Steel and ash to support the stock sleepers on both bridge styles.
        # Full raised ballast only on the approach, as with the other kits.
        mesh.box("Rail trough foundation","Rail trough base",-.351,.351,-1,1,
                 lambda v:h(v)-.010,lambda v:h(v)+.025,end_faces=False)
        for sign in (-1,1):
            a,b = sorted((sign*.350, sign*.388))
            mesh.box("Rail trough drainage lip","Low rail trough lip",a,b,-1,1,
                     lambda v:h(v)-.008,lambda v:h(v)+.029,end_faces=False)
            for v in (-.67,-.14,.39):
                mesh.box("Drainage grate","Set-in drainage grille",a+.003,b-.003,v-.016,v+.016,
                         lambda q:h(q)+.026,lambda q:h(q)+.034)
        if pose == "head_flat":
            rail.descending_land(mesh)
        rail.full_track(mesh,h,"full" if head else None,guards="head" if head else "span")
        for axis,direction in (enumerate(range(4)) if head else ((0,2),(1,1))):
            name = f"{pose}_{axis}"
            shape = mesh.oriented(direction)
            kit.export(name,shape)
            parts[name] = kit.author(shape,name,mats)
    pier = kit.Mesh()
    author.pier(pier)
    widen(pier,1.18)
    kit.atlas()
    for axis,direction in ((0,2),(1,1)):
        key = f"pier_{axis}"
        shape = pier.oriented(direction)
        kit.export(key,shape)
        parts[key] = kit.author(shape,key,mats)
        span = kit.MODELS / f"{kit.PREFIX}_span_{axis}.obj"
        span.with_name(span.stem+"_road_clear.obj").write_text(clear_span(span,BEARING_GROUPS[stem]))
        for depth in (1,2,"water"):
            write_feet(stem,COLUMNS[stem],axis,depth)
    show_short(parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/"art"/f"{stem}.blend"),compress=True)


if __name__ == "__main__":
    build("concrete",concrete)
    build("girder",steel)
