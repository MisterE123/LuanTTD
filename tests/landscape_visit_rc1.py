#!/usr/bin/env python3
"""Differential for OpenTTD 16.0-RC1 src/landscape.cpp RunTileLoop only."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/landscape.cpp#L742-L776
MASKS = (0xD8F, 0x1296, 0x2496, 0x4357, 0x8679, 0x1030E, 0x206CD,
         0x403FE, 0x807B8, 0x1004B2, 0x2006A8, 0x4004B2, 0x800B87)
LUA = """
local h=dofile("mods/luanttd_core/openttd/town_passengers.lua")
for line in io.lines() do
  local a,b,c,d,n=line:match("(%d+) (%d+) (%d+) (%d+) (%d+)")
  local clock=h.new_clock(tonumber(a),tonumber(b),tonumber(c),tonumber(d))
  local t=h.tape(clock,tonumber(n))
  io.write(t)
  for _,v in ipairs({clock.head,clock.counter}) do
    for i=1,4 do io.write(string.char(v%256));v=math.floor(v/256) end
  end
end
"""


def reference(x, y, head, clock, ticks):
    taps = MASKS[x + y - 12]
    count = 1 << (x + y - 8)
    tape = bytearray()
    for tick in range(clock + 1, clock + ticks + 1):
        zero = tick % 256 == 0
        if zero:
            tape.extend(b"\0\0\0")
        for _ in range(count - int(zero)):
            tape.extend(head.to_bytes(3, "little"))
            head = (head >> 1) ^ (taps if head & 1 else 0)
    return tape + head.to_bytes(4, "little") + (clock + ticks).to_bytes(4, "little")


cases = [(x, y, ((1 << (x + y)) - 1) ^ 5, 254, 4)
         for x in range(6, 13) for y in range(6, 13)
         if x in {6, 9, 12} or y in {6, 9, 12}]
cases.extend([(6, 6, 1, 184, 74), (6, 12, 1, 183, 74), (12, 6, 11, 501, 74)])
args = "".join(" ".join(map(str, case)) + "\n" for case in cases).encode()
out = subprocess.run(["lua5.1", "-e", LUA], input=args, stdout=subprocess.PIPE,
                     check=True, cwd=ROOT).stdout
offset, visits = 0, 0
for case in cases:
    expected = reference(*case)
    assert out[offset:offset+len(expected)] == expected, (case, offset)
    offset += len(expected)
    visits += (len(expected) - 8) // 3
assert offset == len(out)
print(f"PASS RC1 RunTileLoop: {visits:,} exact visits, {len(cases)} dimensions/cursor cases")
