#!/usr/bin/env python3
"""Original affordance icons for the native task-layout hotbar."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core" / "textures"
PANEL, OUTLINE, INLAY, GOLD, SKY = "#183247", "#92b1b7", "#2c4f5e", "#efcd8b", "#9fe7dc"

def plate():
    im = Image.new("RGBA", (64, 64))
    p = ImageDraw.Draw(im)
    p.rounded_rectangle((3, 3, 60, 60), radius=8, fill=PANEL, outline=OUTLINE, width=2)
    p.rounded_rectangle((7, 7, 56, 56), radius=5, outline=INLAY, width=2)
    return im, p

im, p = plate()
# Depot aperture plus a bright ingress arrow instead of another building icon.
p.line([(19, 49), (19, 27), (41, 16), (52, 24), (52, 49)], fill=GOLD, width=4, joint="curve")
p.line([(19, 49), (52, 49)], fill=GOLD, width=3)
p.rectangle((32, 29, 45, 45), outline=GOLD, width=2)
p.line([(11, 37), (34, 37)], fill=SKY, width=4)
p.polygon([(35, 37), (26, 30), (26, 44)], fill=SKY)
im.save(OUT / "bl_dispatch_service_depot.png")

im, p = plate()
# Bridge over a blue cut in the ground; lateral bolts identify the category.
p.line([(10, 28), (53, 28)], fill=GOLD, width=4)
p.line([(16, 27), (16, 43), (24, 37), (32, 36), (41, 37), (48, 43), (48, 27)],
       fill=GOLD, width=3, joint="curve")
p.line([(13, 47), (20, 45), (27, 47), (34, 45), (41, 47), (52, 45)], fill=SKY, width=3)
p.line([(14,20),(50,20)], fill=OUTLINE, width=2)
im.save(OUT / "bl_dispatch_road_spans.png")

# Mode launcher is a paired tram silhouette. The order icon is still the
# individual car's existing schedule, not another launcher silhouette.
im, p = plate()
for x, y in ((12, 26), (30, 17)):
    p.rounded_rectangle((x, y, x+21, y+23), radius=4, fill=GOLD, outline=PANEL, width=2)
    p.rectangle((x+5, y+5, x+16, y+10), fill=INLAY)
    p.line([(x+3, y+26),(x+17, y+26)], fill=SKY, width=3)
im.save(OUT / "bl_dispatch_tram_operations.png")
im, p = plate()
p.line([(16, 16),(49, 48)], fill=GOLD, width=6)
p.line([(49, 16),(16, 48)], fill=GOLD, width=6)
im.save(OUT / "bl_dispatch_order_cancel.png")
im, p = plate()
p.polygon([(15,17),(51,32),(15,48),(23,32)], fill=SKY)
p.line([(15,17),(51,32),(15,48)], fill=GOLD, width=3)
im.save(OUT / "bl_dispatch_order_dispatch.png")
im, p = plate()
p.line([(13,49),(13,26),(32,13),(51,26),(51,49),(13,49)], fill=GOLD, width=3)
p.polygon([(32,21),(36,34),(46,40),(45,43),(35,41),(35,45),(39,47),(39,49),(32,48),
           (25,49),(25,47),(29,45),(29,41),(19,43),(18,40),(28,34)], fill=SKY)
im.save(OUT / "bl_dispatch_service_hangar.png")
