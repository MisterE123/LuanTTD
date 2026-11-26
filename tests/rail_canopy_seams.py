"""Confirm Blender-exported supplements meet the selected shared tile edges."""
from pathlib import Path

models = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
for gfx in range(4, 8):
    for mask in range(1, 8):
        p = models / f"bl_rail_station_gfx_{gfx}_join_{mask}.obj"
        vertices = [tuple(map(float, s[2:].split())) for s in p.read_text().splitlines() if s.startswith("v ")]
        assert vertices and all(1.00 < h < 1.28 for _, h, _ in vertices)
        # The base tile origin is one node left of the overlay. Undo the
        # reflected OBJ X axis and restore signed coords about the tile centre.
        v = [(-x + .5, z - .5) for x, _, z in vertices]
        assert all(-1.000001 <= u <= 1.000001 for a in v for u in a)
        axis = gfx % 2
        assert (min(a[axis] for a in v) <= -1) == bool(mask & 1), p
        assert (max(a[axis] for a in v) >= 1) == bool(mask & 2), p
        edge = 1 if gfx < 6 else -1
        assert any(a[1-axis] == edge for a in v) == bool(mask & 4), p
print("PASS 28 Blender canopy seam variants close only selected sides at exact tile boundaries")
