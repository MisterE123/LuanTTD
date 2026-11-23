"""Read live Luanti client positions and prove a no-edit pedestrian round trip."""
from pathlib import Path
import math
import sys


def sample(row):
    tag, mode, x, y, z, yaw, pitch, surface, hud, menu, topology = row.split()
    return tag, {"mode": mode, "pos": tuple(map(float, (x,y,z))), "yaw": float(yaw),
                 "pitch": float(pitch), "surface": float(surface),
                 "hud": hud, "menu": menu, "topology": topology}


def check_rendered_views(folder):
    if not (folder / "builder-first.png").is_file():
        return
    from PIL import Image

    def rgb(name):
        return Image.open(folder / f"{name}.png").convert("RGB")

    for name in ("builder-first", "builder-rear", "builder-front", "walk-returned"):
        image = rgb(name)
        field = image.crop((int(image.width*.06), int(image.height*.12),
                            int(image.width*.94), int(image.height*.72)))
        pixels = field.get_flattened_data() if hasattr(field, "get_flattened_data") else field.getdata()
        green = sum(r <= 3 and b <= 3 and g > 35 for r,g,b in pixels)
        assert green < 12, (name, "Luanti default player billboard visible", green)
    doorway = rgb("walk-door-eye")
    # The actual horizon line cuts the nearby pane of house-door glazing,
    # not the upper story, facade above the door, or far-off roof.
    pane = doorway.crop((int(doorway.width*.623), doorway.height//2-3,
                         int(doorway.width*.632), doorway.height//2+4))
    pixels = pane.get_flattened_data() if hasattr(pane, "get_flattened_data") else pane.getdata()
    glass = sum(17 < r < 40 and 30 < g < 57 and 46 < b < 75 for r,g,b in pixels)
    assert glass >= pane.width*pane.height*.65, "street camera is not level with house-door glazing"
    print("Rendered eye level intersects door glazing; invisible in three builder cameras and after walking.")


def main(log):
    trace = []
    phases = {}
    for line in Path(log).read_text().splitlines():
        if "WALK_QA " in line:
            tag, data = sample(line.split("WALK_QA ",1)[1])
            if tag == "trace":
                trace.append(data)
            else:
                phases[tag] = data
    before, entered, blocked, returned = (phases[tag] for tag in
                                           ("before", "entered", "blocked", "returned"))
    assert before["mode"] == returned["mode"] == "builder"
    assert entered["mode"] == blocked["mode"] == "walk"
    assert before["hud"] == returned["hud"] == "true"
    assert entered["hud"] == blocked["hud"] == "false"
    assert before["menu"] == returned["menu"] == "roads"
    assert len({d["topology"] for d in phases.values()}) == 1, "pedestrian movement edited construction"
    assert math.dist(before["pos"],returned["pos"])<.10, (before,returned)
    assert abs(before["yaw"]-returned["yaw"])<.08 and abs(before["pitch"]-returned["pitch"])<.08
    assert entered["pos"][1]<.85 and abs(entered["pitch"])<.08, entered
    cx,cy,cz=blocked["pos"]
    assert 29.2 < cx < 29.95 and 1.43 < cy < 1.60, blocked
    assert abs(cz - entered["pos"][2])<.15, (entered, blocked)
    ramp=[d for d in trace if 23.57 < d["pos"][0] < 25.43]
    assert len(ramp)>1, ramp
    assert all(abs(d["pos"][1]-d["surface"])<.26 for d in ramp), ramp
    assert any(.82<d["pos"][1]<1.42 for d in ramp), ramp
    check_rendered_views(Path(log).parent)
    print(f"Native /walk crossed {len(ramp)} grade samples, stopped at the house, returned exactly to builder.")


if __name__ == "__main__":
    main(sys.argv[1])
