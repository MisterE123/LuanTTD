#!/usr/bin/env python3
"""Dense preview caching must not change an asset or use stale geometry."""
from pathlib import Path
import hashlib
import importlib.util
import tempfile
from zipfile import BadZipFile, ZipFile, ZIP_DEFLATED
import zlib

spec = importlib.util.spec_from_file_location(
    "package_preview", Path(__file__).resolve().parents[1] / "tools/package_preview.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
asset = "luanttd/mods/luanttd_core/models/first.obj"
new_path = "luanttd/mods/luanttd_core/models/renamed.obj"
prior = b"v 0.4 0 1\n" * 7000
changed = prior + b"v 0 0 1\n"

with tempfile.TemporaryDirectory() as folder:
    p = Path(folder)
    a, b, c = p/"a.zip", p/"b.zip", p/"c.zip"
    with mod.dense_mesh_deflate(True), ZipFile(a, "w", ZIP_DEFLATED) as z:
        z.writestr(asset, prior, ZIP_DEFLATED, 14)
        z.writestr("unrelated/first.obj", changed, ZIP_DEFLATED, 14)
    before = mod.reusable_mesh_streams(a)
    assert set(before) == {hashlib.sha256(prior).digest()}
    with mod.dense_mesh_deflate(True, a), ZipFile(b, "w", ZIP_DEFLATED) as z:
        z.writestr(new_path, prior, ZIP_DEFLATED, 14)
        z.writestr(asset, changed, ZIP_DEFLATED, 14)
    after = mod.reusable_mesh_streams(b)
    assert all(after[k] == before[k] for k in before)
    assert set(after) == {hashlib.sha256(x).digest() for x in (prior, changed)}
    with ZipFile(b) as z:
        assert z.testzip() is None and z.read(asset) == changed and z.read(new_path) == prior
    junk = bytearray(a.read_bytes())
    junk[30 + len(asset) + 5] ^= 4
    c.write_bytes(junk)
    try:
        mod.reusable_mesh_streams(c)
    except (BadZipFile, ValueError, zlib.error):
        pass
    else:
        raise AssertionError("corrupt preview was accepted as a mesh source")

print("PASS: prior DEFLATE is reused only for equal bytes, new geometry stays distinct, ZIP CRC rejects corruption")
