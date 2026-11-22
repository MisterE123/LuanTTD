#!/usr/bin/env python3
"""Original mid-century rigid cargo van. Run with Blender in background mode."""
from pathlib import Path
import os
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_balogh_goods_truck_art as h

r, soft, bpy, Vector = h.r, h.soft, h.bpy, h.Vector
B, T = h.B, h.T
NAME = "bl_craighead_goods_truck"
CAB = "Blue coachwork"
TRIM = "High sky blue"
LOW = "Deep blue firewall"
FRAME = "Frame"
GLASS = "Cab glazing"
LIGHT = "Headlamp glass"
TYRE = "Dark tyre"
HUB = "Hub enamel"
BOX = "Floor timber"
ROOF = "Offwhite paint"
METAL = "Bright nickel"


def build():
    m = r.Mesh(r.terrain_height(0))
    # A compact postwar forward-control cab and straight dry-freight
    # body. Low nose, full-width windshield and no early separate bonnet.
    B(m, "Two steel chassis rails", FRAME, -.105, .014, .065, 1.49, .121, .169, .008)
    B(m, "Opposite steel chassis rail", FRAME, .105, .014, .065, 1.49, .121, .169, .008)
    B(m, "Tall pressed-steel cab", CAB, 0, -.500, .460, .512, .157, .506, .025)
    B(m, "Cab curved roof", TRIM, 0, -.490, .455, .486, .490, .540, .023)
    B(m, "Wrapped bus-style bumper", FRAME, 0, -.775, .483, .048, .116, .164, .014)
    B(m, "Black radiator inset", LOW, 0, -.760, .268, .018, .190, .298, .007)
    for y in (.207, .229, .251, .273):
        B(m, "Horizontal nickel grille bar", METAL, 0, -.774, .230, .010, y, y+.010, .003)
    for s in (-1, 1):
        B(m, "Two-pane front windshield rubber", LOW, s*.109, -.759, .203, .013, .335, .485, .006)
        B(m, "Two-pane front glazing", GLASS, s*.109, -.768, .176, .011, .345, .474, .004)
        B(m, "Side quarter glass", GLASS, s*.234, -.492, .013, .306, .343, .473, .007)
        B(m, "Side drop glass daylight", "Daylight glass", s*.242, -.548, .008, .171, .448, .464, .004)
        B(m, "Cab lower step", LOW, s*.231, -.460, .059, .220, .140, .161, .006)
        B(m, "Door latch", METAL, s*.239, -.376, .013, .033, .293, .304, .004)
        h.tube(m, "Mirror steel stalk", METAL, (s*.225,-.713,.430),(s*.273,-.711,.453), .004, steps=6)
        B(m, "Cab square rear-view mirror", LOW, s*.276, -.711, .030, .015, .431, .482, .005)
        T(m, "Recessed headlight bowl", LOW, (s*.182,-.758,.237), .045, "z", -.016,.001, 12)
        T(m, "Front headlight lens", LIGHT, (s*.182,-.775,.237), .024, "z", -.004,.002, 12)
        B(m, "Front amber turn signal", "Road amber", s*.196,-.767,.042,.018,.172,.191,.006)
        B(m, "Full lower fender brow", LOW,s*.196,-.481,.136,.250,.198,.230,.015)
        for z in (-.495, .490):
            T(m, "Road tire sidewall", TYRE, (s*.212,z,.105), .105, "x", -.052,.052, 18)
            T(m, "Pressed steel wheel and hub", HUB, (s*.264,z,.105), .052, "x", -.010,.010, 12)
    B(m, "Varnished rigid cargo shell", BOX, 0, .281, .514, .998, .199, .625, .018)
    B(m, "Raised light cargo roof", ROOF, 0, .281, .527, 1.012, .613, .655, .012)
    for s in (-1, 1):
        for y,mat in ((.255,LOW),(.340,"Weathered plank end"),(.577,TRIM)):
            B(m, "Riveted side rail", mat,s*.260,.281,.011,.988,y,y+.014,.003)
        for z in (-.159,.073,.310,.548,.755):
            B(m, "Cargo shell strengthening seam", "Weathered plank end",s*.261,z,.009,.011,.286,.581,.002)
        B(m, "Recessed split rear cargo door", "Weathered plank end",s*.126,.787,.230,.017,.251,.591,.008)
        B(m, "Rear door drop-bar", METAL,s*.086,.801,.016,.011,.280,.552,.003)
        B(m, "Rear hinge plates", METAL,s*.202,.801,.041,.014,.504,.522,.003)
        B(m, "Rear ruby marker", "Rear ruby",s*.210,.787,.041,.017,.161,.183,.004)
    B(m, "Modern rear step plate", FRAME,0,.803,.451,.080,.125,.159,.010)
    h.LETTERS["9"] = ("111", "101", "111", "001", "111")
    h.little_numbers(m, "139", .174, -.797)
    h.little_numbers(m, "139", .181, .825)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.name = "LuanTTD | Craighead Goods Truck #139"
    mats = r.materials()
    for mat, label in zip(mats, h.PAL):
        mat.name = label
    mesh = build()
    collection = r.stash(mesh, mats, "Craighead #139 | full editable cargo van")
    r.export_obj(r.MODELS/(NAME+".obj"), soft.local_obj(mesh))
    h.NAME = NAME
    h.atlas()
    h.review(scene, collection)
    bpy.ops.wm.save_as_mainfile(filepath=str(r.ROOT/"art"/"craighead_goods_truck.blend"),compress=True)
    if target := os.getenv("CRAIGHEAD_RENDER"):
        scene.render.resolution_percentage = 55
        scene.render.filepath = target
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
