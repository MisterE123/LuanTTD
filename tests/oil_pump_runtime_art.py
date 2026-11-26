#!/usr/bin/env python3
"""Check the shared oil-pump frame pack and coordinate trace."""
from pathlib import Path

models = Path("mods/luanttd_core/models")
base = sorted(models.glob("bl_industry_oil_well_base_*.obj"))
poses = sorted(models.glob("bl_industry_oil_well_pose_*.obj"))
assert len(base) == 5 and len(poses) == 12
for f in base:
    s = f.read_text()
    assert "production_casing" in s and "curved_solid_horsehead" not in s
    assert "Anchored_pumpjack_A-frame" in s
heights = set()
for f in poses:
    raw = f.read_text().splitlines()
    v = [tuple(map(float, x.split()[1:])) for x in raw if x.startswith("v ")]
    assert len(v) == 238 and sum(x.startswith("f ") for x in raw) == 412
    assert len([x for x in raw if x.startswith("g ")]) == 1
    assert any("recognizable_curved_solid_horsehead" in x for x in raw)
    assert -14 < min(x for x, _, _ in v) < -13.5 and 4 < min(z for _, _, z in v) < 8
    heights.add(max(y for _, y, _ in v))
assert len(heights) == 12 and 1 < max(heights) - min(heights) < 1.2
assert sum(f.stat().st_size for f in poses)<350000
assert sum(f.stat().st_size for f in base+poses)<1100000
print("PASS five original static pads and 12 distinct in-place moving meshes (shared moving set under 350 kB)")
