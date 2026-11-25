"""Native crossing wire aligns with both ordinary electrified approaches."""
from collections import defaultdict
from pathlib import Path

mods = Path("mods/luanttd_core/models")
source = Path("art/electric_crossing_wire.blend")
assert source.is_file() and source.stat().st_size > 2000

def positions(p, east_offset):
    named = defaultdict(list)
    group = ""
    for line in p.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "o":
            group = fields[1]
        elif fields[0] == "v":
            x, y, z = map(float, fields[1:])
            named[group].append((round(east_offset-x-.5, 6), round(y+1.5, 6), round(z-.5, 6)))
    return named

for bits in (1, 2):
    ordinary = positions(mods / f"bl_rail_catenary_{bits}_0.obj", 0)
    assert ordinary
    for pole in (0, 1):
        crossing = positions(mods / f"bl_electric_crossing_wire_{bits}_{pole}.obj", 1)
        assert all(crossing[key] == values for key,values in ordinary.items()), (bits,pole)
        wire = next(v for k,v in crossing.items() if k.startswith("Continuous_shaped_contact_wire"))
        axis = 0 if bits == 1 else 2
        lateral = 2-axis
        assert min(v[axis] for v in wire) == -1 and max(v[axis] for v in wire) == 1
        assert min(v[1] for v in wire) == .898
        # Stock tram wire crossing uses .500 above the same travel deck.
        assert min(v[1] for v in wire)-.513 >= .38
        if pole:
            foot = next(v for k,v in crossing.items() if k.startswith("Chamfered_grounded_masonry"))
            assert min(v[1] for v in foot) == 0
            # A perpendicular road uses the rail longitudinal coordinate
            # as its lateral envelope. Keep the full foot outside it and
            # away from the railway running surface as well.
            assert .70 < min(abs(v[axis]) for v in foot) < max(abs(v[axis]) for v in foot) < 1
            assert .62 < min(abs(v[lateral]) for v in foot) < max(abs(v[lateral]) for v in foot) < 1
print("PASS both ELRL crossing axes: exact matched ends, independent tram wire height and off-road mast footing")
