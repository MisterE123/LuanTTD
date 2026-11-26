"""Require both real movement and contact with the projected rail surfaces."""
from pathlib import Path
from collections import defaultdict
import re
import sys

trace = defaultdict(list)
finish = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    m = re.search(r"RAIL_WALK_(STEP|FINISH) (\w+) ([-.0-9]+) ([-.0-9]+) ([-.0-9]+)", line)
    if m:
        action, case, *coords = m.groups()
        p = tuple(map(float, coords))
        if action == "STEP":
            trace[case].append(p)
        else:
            finish[case] = p
assert finish["flat_along"][0] > 21.0
assert finish["flat_across"][2] > 21.15
assert finish["grade_along"][0] > 25.55 and finish["grade_along"][1] > 2.55
assert finish["grade_across"][2] > 23.10
assert finish["diagonal_along"][0] > 30.60 and finish["diagonal_along"][2] < 25.40
assert finish["diagonal_across"][0] > 30.85 and finish["diagonal_across"][2] > 26.10
assert finish["crossing"][2] > 31.20
assert finish["fence"][2] > 19.75
for case, height in (
    ("flat_along", 1.571), ("flat_across", 1.571), ("grade_across", 2.050),
    ("diagonal_along", 2.571), ("diagonal_across", 2.571), ("crossing", 2.608),
):
    assert any(abs(p[1]-height) < .006 for p in trace[case]), (case, "avatar clipped through the rail")
print("PASS native Walk along/across flat, grade, diagonal, and road crossing; fences stop walking and allow jumping")
