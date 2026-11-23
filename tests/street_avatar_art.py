"""Verify the runtime skinned street avatar is portable, grounded and animated."""
import json
import struct
import zlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
model = root / "mods/luanttd_core/models/bl_street_pedestrian.glb"
palette = root / "mods/luanttd_core/textures/bl_street_pedestrian_atlas.png"
data = model.read_bytes()
assert struct.unpack_from("<4sII", data, 0) == (b"glTF", 2, len(data))
size, tag = struct.unpack_from("<I4s", data, 12)
assert tag == b"JSON"
doc = json.loads(data[20:20+size])
assert "images" not in doc and palette.read_bytes().startswith(b"\x89PNG")
assert len(doc["skins"]) == 1 and len(doc["skins"][0]["joints"]) == 12
mesh, = doc["meshes"]
primitive, = mesh["primitives"]
bounds = doc["accessors"][primitive["attributes"]["POSITION"]]
assert bounds["min"][1] == 0 and 5.08 <= bounds["max"][1] < 5.14
assert bounds["max"][0] - bounds["min"][0] < 1.95
assert bounds["min"][2]<-.4 and bounds["max"][2]>.50
assert 350 < doc["accessors"][primitive["indices"]]["count"] / 3 < 3000

timeline, = doc["animations"]
rotation_joints = {
    doc["nodes"][channel["target"]["node"]]["name"]
    for channel in timeline["channels"] if channel["target"]["path"] == "rotation"
}
assert {"Thigh.L","Thigh.R","Shin.L","Shin.R","UpperArm.L","UpperArm.R"} <= rotation_joints
for sample in timeline["samplers"]:
    assert sample["interpolation"] == "LINEAR"
    keys = doc["accessors"][sample["input"]]
    assert keys["min"] == [0] and keys["max"] == [14]

assert len(zlib.compress(data, 9)) + len(palette.read_bytes()) < 50_000
assert (root / "art/street_pedestrian.blend").stat().st_size > 10_000
print("Street avatar: grounded original 12-joint mesh, compact rigged gait, external runtime palette")
