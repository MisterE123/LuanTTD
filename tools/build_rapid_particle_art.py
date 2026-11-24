#!/usr/bin/env python3
"""Generate original semi-transparent spray and wake sprites."""
from argparse import ArgumentParser
from io import BytesIO
from math import hypot
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/textures"

# Overlapping, asymmetric foam bubbles rather than points or streaks.
WAKE = ((-.48, -.04, .43, .36, .64), (-.06, -.26, .35, .32, .74),
        (.10, .01, .46, .27, .77), (.45, .13, .38, .33, .64),
        (-.29, .24, .29, .23, .61), (.47, -.23, .23, .18, .48))
SPRAY = ((-.11, .03, .38, .65, .94), (.24, -.34, .16, .20, .63),
         (-.36, -.24, .14, .17, .42), (.16, .31, .24, .29, .61))

def images():
    for name, bubbles in (("wake", WAKE), ("spray", SPRAY)):
        im = Image.new("RGBA", (32, 32))
        for y in range(32):
            for x in range(32):
                X, Y = (x - 15.5) / 15.5, (y - 15.5) / 15.5
                transmit = 1.
                for u, v, rx, ry, power in bubbles:
                    d = hypot((X-u)/rx, (Y-v)/ry)
                    transmit *= 1-power*max(0, 1-d)**.8
                a = round(255*(1-transmit))
                im.putpixel((x,y),(211+a//8, 232+a//13, 230+a//13, a))
        output = BytesIO()
        im.save(output, format="PNG", optimize=True)
        yield root / f"bl_river_{name}.png", output.getvalue()

if __name__ == "__main__":
    p = ArgumentParser()
    p.add_argument("--check", action="store_true")
    check = p.parse_args().check
    for path, data in images():
        if check:
            assert path.read_bytes() == data, path
        else:
            temp = path.with_suffix(".tmp")
            temp.write_bytes(data)
            temp.replace(path)
