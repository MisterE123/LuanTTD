#!/usr/bin/env python3
"""Small original square texture kit for stock Temperate crossing shoulders."""
from pathlib import Path
import random
import struct
import zlib

OUT=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
SIZE=32

def chunk(name,value):
    return struct.pack(">I",len(value))+name+value+struct.pack(">I",zlib.crc32(name+value))

def pavement():
    rng=random.Random(1601)
    row=[]
    for z in range(SIZE):
        row.append(0)
        for x in range(SIZE):
            r,g,b=(146,143,131)
            if z in (0,16) or (x+(8 if z>=16 else 0))%16==0:
                r,g,b=(116,116,106)
            v=rng.choice((-4,-2,-1,0,0,0,1,3))
            row.extend((r+v,g+v,b+v))
    png=b"\x89PNG\r\n\x1a\n"
    png+=chunk(b"IHDR",struct.pack(">IIBBBBB",SIZE,SIZE,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress(bytes(row),9))+chunk(b"IEND",b"")
    (OUT/"bl_stock_crossing_paved.png").write_bytes(png)

if __name__=="__main__":
    pavement()
