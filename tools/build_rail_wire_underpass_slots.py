#!/usr/bin/env python3
"""Make same-world-space variants for wires that share the bridge node layer."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core/models"
for mask in (1, 2):
    for pole in (0, 1):
        stem = f"bl_rail_catenary_{mask}_{pole}"
        lines = (root / f"{stem}.obj").read_text().splitlines()
        lines[0] = "# Same rail wire in the east Luanti voxel; regenerate with tools/build_rail_wire_underpass_slots.py"
        for i, line in enumerate(lines):
            if line.startswith("v "):
                _, x, y, z = line.split()
                # Luanti reflects OBJ X. Compensate an east voxel by +1.
                lines[i] = f"v {float(x)+1:.6f} {y} {z}"
        (root / f"{stem}_under.obj").write_text("\n".join(lines) + "\n")
