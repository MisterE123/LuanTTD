"""Original continuous through-truss for OpenTTD RC1 cantilever stocks #6–8."""
from pathlib import Path
from sys import path

path.insert(0, str(Path(__file__).resolve().parent))
import build_concrete_suspension_art as common
import build_steel_suspension_art as steel

kit, rail, bpy = common.kit, common.rail, common.bpy
COLORS = {**common.COLORS, "Rolled angle": "797974", "Angle flange": "98958a",
          "Lower chord": "515953", "Compression plate": "696d63",
          "Gusset": "4f5651", "Fastener": "aa9e87", "Foundation": "858477",
          "Cutwater": "706e62", "Reflector": "d2a350"}
PALETTES = {
    "brown": {**COLORS, "Rolled angle": "8a6550", "Angle flange": "b88a66",
              "Lower chord": "564842", "Compression plate": "795a48",
              "Gusset": "695040", "Fastener": "a88f75"},
    "red": {**COLORS, "Rolled angle": "973f39", "Angle flange": "c26351",
            "Lower chord": "68403c", "Compression plate": "863c36",
            "Gusset": "6a3330", "Fastener": "a99586"},
}
BEARING = {"Cantilever_cast_seat", "Cantilever_elastomer"}
CORE = "Cantilever_cutwater_core"


def steel_bar(mesh, group, u, start, end, wide=.066, depth=.052, color="Rolled angle"):
    steel.member(mesh, group, (u, *start), (u, *end), wide, depth, color)


def truss(mesh, mode, head=False):
    # Course from the approach's land edge to its river edge. All interior
    # chords meet at identical boundaries so no apertures or double faces.
    h = lambda v: v / 2 if head == "ramp" else .5
    if mode == "road":
        kit.running_surface(mesh, h)
    else:
        if head == "flat":
            rail.descending_land(mesh)
        rail.full_track(mesh, h, "full" if head else None, guards="head" if head else "span")
    w = .51 if mode == "road" else .553
    mesh.box("Running deck diaphragm", "Concrete deep", -w, w, -1, 1,
             lambda v: h(v) - .119, lambda v: h(v) - .012, end_faces=False)
    last = -.72 if head else -1
    outer = lambda v: h(v) + (.86 if not head else .16 + .70 * (v - last) / (1 - last))
    for side in (-1, 1):
        u = side * (w - .023)
        for group, off, thickness, half, color in (
                ("Rolled bottom chord", -.234, .086, .059, "Lower chord"),
                ("Deck edge stringer", -.112, .045, .049, "Compression plate")):
            mesh.box(group, color, u - half, u + half, -1, 1,
                     lambda v, k=off: h(v) + k,
                     lambda v, k=off+thickness: h(v) + k, end_faces=False)
        mesh.box("Boxed upper chord", "Angle flange", u-.057, u+.057, last, 1,
                 lambda v: outer(v)-.046, lambda v: outer(v)+.046, end_faces=False)
        # Staggered Warren web plus bolted vertical tension members.
        joints = [last + (1 - last) * j / 4 for j in range(5)]
        for i, (a, b) in enumerate(zip(joints, joints[1:])):
            if i % 2 == 0:
                steel_bar(mesh, "Cantilever diagonal web", u, (a + .035, h(a) - .151),
                          (b - .025, outer(b) - .012), .087, .072)
            else:
                steel_bar(mesh, "Cantilever diagonal web", u, (a + .025, outer(a) - .012),
                          (b - .035, h(b) - .151), .087, .072)
        for v in joints[1:-1]:
            steel_bar(mesh, "Vertical tension stiffener", u, (v, h(v)-.163),
                      (v, outer(v)), .036, .048, "Compression plate")
            for y in (h(v) - .148, outer(v) - .042):
                x = u + side * .040
                mesh.box("Splice gusset plates", "Gusset", x-.007, x+.007, v-.074, v+.074, y-.044, y+.046)
                for shift in (-.046, .046):
                    xx = x + side * .010
                    mesh.box("Rivet heads", "Fastener", xx-.005, xx+.005,
                             v+shift-.008, v+shift+.008, y-.014, y+.003)
        if head:
            mesh.box("Concrete wingwall footing", "Foundation", u-.089,u+.089, -.53,.57,
                     lambda v: h(v)-.53,lambda v: h(v)-.216)
            mesh.box("Approach marker", "Reflector", u-.025,u+.025,last-.035,last+.014,
                     h(last)+.094,h(last)+.181)
    if not head:
        for v in (-.77, 0, .77):
            mesh.box("Under deck cross ties", "Lower chord", -w, w, v-.039,v+.039, .265,.383)


def bearing(mesh):
    # Canonical minus end is OpenTTD NE/NW. No under-deck support on piece 0.
    for u in (-.40, .40):
        common.block(mesh,"Cantilever cast seat","Foundation",u,-1,-.706,.206,-.5,.226)
        common.block(mesh,"Cantilever elastomer","Gusset",u,-1,-.687,.224,.226,.283)


def pier():
    mesh = kit.Mesh()
    for u in (-.40, .40):
        common.block(mesh,CORE.replace("_"," "),"Cutwater",u,-1,-.706,.206,-.5,.5)
        common.block(mesh,"Cast band","Foundation",u,-1,-.695,.222,.203,.237)
    return mesh


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.name = "LuanTTD | Original three-finish steel cantilever"
    kit.COLORS = COLORS
    mats = kit.materials()
    for finish, palette in PALETTES.items():
        assert list(palette) == list(COLORS)
        kit.COLORS = palette
        for name, mat in kit.materials().items():
            mat.name = name + " | " + finish.title()
            mat.use_fake_user = True
    showcase = {}
    for mode in ("road", "rail"):
        stem = f"{mode}_bridge_cantilever"
        kit.COLORS = COLORS
        kit.PREFIX = "bl_" + stem
        parts = {}
        for head in ("flat", "ramp"):
            m = kit.Mesh()
            truss(m, mode, head)
            for direction in range(4):
                parts[f"head_{head}_{direction}"] = m.oriented(direction)
        for key in ("clear", "minus"):
            m = kit.Mesh()
            truss(m, mode)
            if key == "minus":
                bearing(m)
            for axis, direction in ((0,2), (1,1)):
                parts[f"span_{axis}_{key}"] = m.oriented(direction)
                if key == "minus":
                    parts[f"pier_{axis}_{key}"] = pier().oriented(direction)
        kit.atlas()
        for name, mesh in parts.items():
            kit.export(name, mesh)
            obj = kit.author(mesh, mode.capitalize()+" "+name, mats)
            if mode == "road":
                showcase[name] = obj
        for axis in (0, 1):
            span = kit.MODELS / f"{kit.PREFIX}_span_{axis}_minus.obj"
            span.with_name(span.stem+"_road_clear.obj").write_text(common.clear_span(span, BEARING))
            for depth in (1, 2, "water"):
                common.write_feet(stem, CORE, axis, depth, variant="minus")
        for finish, palette in PALETTES.items():
            kit.PREFIX, kit.COLORS = "bl_"+stem+"_"+finish, palette
            kit.atlas()
    kit.showcase({**showcase, "span_0": showcase["span_0_minus"], "pier_0": showcase["pier_0_minus"]})
    for ob in list(bpy.context.scene.objects):
        if ob.instance_type != "COLLECTION" or abs(ob.location.x + 2) > .01:
            continue
        if "span" in ob.instance_collection.name:
            ob.instance_collection = showcase["span_0_clear"]
        elif "pier" in ob.instance_collection.name:
            bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/"art"/"steel_cantilever.blend"),compress=True)


if __name__ == "__main__":
    main()
