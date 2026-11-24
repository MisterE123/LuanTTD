#!/usr/bin/env python3
"""Require the actual cabin and outside scenery in a settled client frame."""
from pathlib import Path
import sys

from PIL import Image


def proportion(image, rect, test):
    crop=image.crop(rect)
    colors=getattr(crop,"get_flattened_data",crop.getdata)()
    return sum(test(*rgb) for rgb in colors)/len(colors)


def measure(path, mode, view):
    with Image.open(path) as raw:
        shot=raw.convert("RGB")
    assert shot.size==(1440,900), shot.size
    structure=(40,80,320,235) if mode=="cab" and view=="forward" else (585,100,850,235)
    warm=proportion(shot,structure,lambda r,g,b: r>b+9 and g>b-12)
    outside=proportion(shot,(300,210,1130,545),lambda r,g,b:
                        (b-r>22 and b-g>6 and b>100) or (g-r>12 and g-b>12))
    return warm,outside


def check(path, mode, view, explain):
    warm,outside=measure(path,mode,view)
    good=warm>.08 and outside>.025
    if explain or not good and len(sys.argv)==2:
        print(f"{mode}/{view}: cabin {warm:.3f} > 0.080, outside {outside:.3f} > 0.025"
              +("" if good else f"; invalid frame: {path}"),file=sys.stderr)
    return good


if len(sys.argv)==2:
    root=Path(sys.argv[1])
    good=all([check(root/f"{mode}-{view}.png",mode,view,True)
              for mode in ("bus","cab","coach") for view in ("forward","side")])
    if good:
        print("Six native views show the cabin and actual scenery through its windows")
    sys.exit(0 if good else 1)

if len(sys.argv) not in (4,5):
    sys.exit("usage: private_ride_pixels.py OUTPUT_DIRECTORY | IMAGE MODE VIEW [--explain]")
_,image,mode,view,*opts=sys.argv
sys.exit(0 if check(Path(image),mode,view,bool(opts)) else 1)
