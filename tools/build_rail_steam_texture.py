"""Original soft condensed steam sprite; no OpenTTD artwork."""
import math
from pathlib import Path
import struct
import zlib

N = 64
LOBES = [
    (-.21, .20, .39, .36, .96), (.20, .24, .45, .29, .77),
    (-.31, -.17, .42, .43, .69), (.22, -.18, .45, .42, .88),
    (.01, -.34, .39, .38, .68), (-.02, .01, .49, .44, 1.0),
]

def pixel(x, y):
    xx = (2 * x + 1) / N - 1
    yy = (2 * y + 1) / N - 1
    mist = 1.0
    for cx, cy, rx, ry, density in LOBES:
        d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
        bump = max(0, 1 - d * .64) ** 2
        mist *= 1 - density * bump
    grain = 1 + .05 * math.sin(xx * 36 + yy * 41) + .06 * math.sin(xx * 20 - yy * 19)
    edge = min(1, 4 * (1 - abs(xx)), 4 * (1 - abs(yy)))
    alpha = min(.86, (1 - mist) * grain * .83) * edge
    light = round(238 - 10 * yy + 2 * math.sin(xx * 7 - yy * 5))
    return bytes((min(255, light + 2), light, max(0, light - 3), round(255 * alpha)))

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

data = b"".join(b"\0" + b"".join(pixel(x, y) for x in range(N)) for y in range(N))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(data, 9)) + chunk(b"IEND", b"")
root = Path(__file__).resolve().parents[1]
(root / "mods/luanttd_core/textures/bl_rail_steam.png").write_bytes(png)
