#!/usr/bin/env python3
"""Generate the original soft lighthouse beam's translucent cards and atlas."""
from math import cos, exp, pi, sin, sqrt
from pathlib import Path
from struct import pack
from zlib import compress, crc32

ROOT = Path(__file__).resolve().parents[1] / 'mods' / 'luanttd_core'


def write_png(path, width, height, pixel):
    def chunk(tag, data):
        body = tag + data
        return pack('>I', len(data)) + body + pack('>I', crc32(body))

    rows = b''.join(b'\0' + bytes(value for x in range(width) for value in pixel(x, y))
                    for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'
                     + chunk(b'IHDR', pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
                     + chunk(b'IDAT', compress(rows, 9)) + chunk(b'IEND', b''))


def smooth(low, high, value):
    t = max(0, min(1, (value-low)/(high-low)))
    return t*t*(3-2*t)


def rgba(x, y):
    if x < 96:
        along = x/95
        across = abs((y+.5)/32-1)
        edge = (1-smooth(.08, .98, across))**1.55
        ends = smooth(0, .032, along)*(1-smooth(.33, 1, along))
        alpha = round(75*exp(-1.95*along)*edge*ends)
        return 255, 226, 155, alpha
    r = sqrt(((x-111.5)/15.5)**2 + ((y-31.5)/23.5)**2)
    alpha = round(198*(1-smooth(0, .98, r))**1.6)
    return 255, 239, 181, alpha


def mesh():
    # The cards taper with the emitted cone and supply a volume-like
    # density gradient from above, below and either side. The small last
    # card faces outward, adding the rotating optic's concentrated glint.
    out = ["# LuanTTD original translucent optic: tools/build_lighthouse_beam.py",
           "o Lighthouse_optic"]
    def card(points, us, vs):
        start = sum(line.startswith('v ') for line in out) + 1
        for x, y, z in points:
            # Luanti OBJ importer reflects X.
            out.append(f"v {-x:.6f} {y:.6f} {z:.6f}")
        for u, v in ((us[0], vs[0]), (us[0], vs[1]), (us[1], vs[1]), (us[1], vs[0])):
            out.append(f"vt {u:.7f} {v:.7f}")
        out.append("f "+" ".join(f"{i}/{i}" for i in range(start, start+4)))
    for i in range(5):
        a = i*pi/5
        near, far = .080, .94
        card([(x, r*cos(a), r*sin(a)) for x, r in ((.165,-near),(.165,near),
                                                 (10.50,far),(10.50,-far))],
             (.5/128,95.5/128),(.5/64,63.5/64))
    card([(.176,y,z) for y,z in ((-.125,-.098),(.125,-.098),(.125,.098),(-.125,.098))],
         (96.5/128,127.5/128),(8.5/64,55.5/64))
    return '\n'.join(out)+'\n'


if __name__ == '__main__':
    (ROOT/'models/bl_lighthouse_beam.obj').write_text(mesh())
    write_png(ROOT/'textures/bl_lighthouse_beam.png', 128, 64, rgba)
