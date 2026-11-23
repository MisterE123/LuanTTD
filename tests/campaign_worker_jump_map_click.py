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
rgb = [(23,42,54),(45,105,133),(66,105,76),(98,137,84),(114,151,93),
       (134,160,105),(154,168,117),(171,172,121),(185,170,128),(200,188,148)]
im = im.crop((0, 120, im.width * 3 // 5, im.height - 110))
m = Image.new("L", im.size)
for c in rgb:
    diff = ImageChops.difference(Image.new("RGB", im.size, c), im)
    r, g, b = [v.point(lambda p: 255 if p == 0 else 0) for v in diff.split()]
    m = ImageChops.lighter(m, ImageChops.darker(ImageChops.darker(r, g), b))
left, top, right, bottom = m.getbbox()
top += 120
bottom += 120
assert right-left > 500 and bottom-top > 500, (left,top,right,bottom)
x = left + (float(x) + float(w)/2 - fx) * (right-left) / fw
y = top + (float(y) + float(h)/2 - fy) * (bottom-top) / fh
print(round(x), round(y))
