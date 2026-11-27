"""Click the actual native form using its painted panel and logged widget bounds."""
from pathlib import Path
import re
import sys
from PIL import Image, ImageChops

file, log, key = sys.argv[1:]
s = Path(log).read_text()
buttons = re.findall(r'JUMP_NATIVE_BUTTON (\w+) ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)', s)
matches = [b for b in buttons if b[0] == key or key == "jump_place" and b[0].startswith("jump_place_")]
assert matches, (key, buttons)
_, x, y, w, h = matches[-1]
im = Image.open(file).convert("RGB")
# Use the exact palette of the painted PNG (not a translucent panel that
# is blended with the 3D world). Exclude the separate one-pixel legend.
frames = re.findall(r'JUMP_NATIVE_FRAME ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)', s)
fx, fy, fw, fh = map(float, frames[-1])
# The frame uses the void color, so exclude it from raster detection.
rgb = [(45,105,133),(79,154,177),(66,105,76),(98,137,84),(114,151,93),
       (134,160,105),(154,168,117),(171,172,121),(185,170,128),(200,188,148),
       (233,185,145),(233,211,148),(170,188,201),(255,225,133),
       (213,143,80),(234,216,147)]
im = im.crop((0, 120, im.width * 3 // 5, im.height - 110))
m = Image.new("L", im.size)
for c in rgb:
    diff = ImageChops.difference(Image.new("RGB", im.size, c), im)
    r, g, b = [v.point(lambda p: 255 if p == 0 else 0) for v in diff.split()]
    m = ImageChops.lighter(m, ImageChops.darker(ImageChops.darker(r, g), b))
# A stray matching label, background pixel or border must not shift a
# narrow town-badge click. Find the sustained raster extent on each axis.
def extent(values):
    cutoff = max(values) * .16
    start = 0
    runs = []
    for i, value in enumerate(values + [0]):
        if value >= cutoff:
            continue
        if i > start:
            runs.append((start, i))
        start = i + 1
    return max(runs, key=lambda run: run[1] - run[0])

width, height = m.size
pixels = m.tobytes()
left, right = extent([pixels[x::width].count(255) for x in range(width)])
top, bottom = extent([pixels[y*width:(y+1)*width].count(255) for y in range(height)])
top += 120
bottom += 120
assert right-left > 500 and bottom-top > 500, (left,top,right,bottom)
x = left + (float(x) + float(w)/2 - fx) * (right-left) / fw
y = top + (float(y) + float(h)/2 - fy) * (bottom-top) / fh
print(round(x), round(y))
