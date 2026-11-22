#!/usr/bin/env python3
"""Package a committed LuanTTD preview and separate verified evidence/source."""
import argparse
from contextlib import contextmanager
import ctypes as ct
import ctypes.util
import os
import hashlib
import io
from pathlib import Path
import shutil
import struct
import subprocess as sp
import tempfile
import zipfile
import zlib

CAP = 20 * 1024 * 1024
REPO = Path(__file__).resolve().parents[1]
# Keep the playable zip install-sized; the companion .git.bundle carries
# all Blender scenes, porting tools, test programs and version history.
GUIDES = {"README.md", "PORTING.md", "CHANGELOG.md", "IMPORTING.md", "TIMBER_WORLD.md",
          "TESTING.md", "ROADMAP.md", "COPYING.OpenTTD.md", "RAIL_SPAN_PREVIEW.md",
          "docs/original-terrain.md", "docs/original-terrain-exploration.md",
          "TERRAIN_STREAM.md", "STOCK_ENGINE_CALENDAR.md", "RAIL_BLOCK_DISPATCH.md",
          "RAIL_BLOCK_SIGNALS.md", "FARM_FACTORY_WORLD.md", "FARM_FACTORY_PORT.md",
          "ROAD_ORDER_LISTS.md", "ROAD_BREAKDOWNS.md", "ROAD_DEPOT_SERVICE.md",
          "OIL_INDUSTRY_PORT.md", "OIL_FREIGHT_WORLD.md",
          "docs/generated-campaign.md", "docs/terragenesis-port.md",
          "docs/stock-river-worldgen.md", "docs/stock-town-worldgen.md",
          "docs/stock-industry-worldgen.md", "docs/scenery-object-worldgen-port.md",
          "docs/tree-worldgen-port.md", "docs/harbor-valley.md",
          "docs/generated-world-scale-audit.md",
          "docs/electric-rail.md", "docs/railtype-port.md",
          "docs/rail-electrification-world.md",
          "docs/hotbar-layout.md", "docs/autorail.md", "docs/build-in-3d.md",
          "LEVEL_CROSSING_WORLD.md",
          "STOCK_AREA_DEMOLITION.md",
          "tools/extract_original_terrain_masks.py"}


def playable_member(name):
    if not name.startswith("bayline/"):
        return False
    rel = name[len("bayline/"):]
    return rel.startswith("mods/") or rel in {"game.conf", "settingtypes.txt"} or rel in GUIDES


def git(*args, cwd=REPO):
    return sp.check_output(["git", *args], cwd=cwd, text=True).strip()


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(path):
    with zipfile.ZipFile(path) as z:
        broken = z.testzip()
        if broken:
            raise ValueError(f"{path.name}: bad bytes for {broken}")
    inf = path.stat()
    print(f"{path.name}: {inf.st_size:,} bytes; SHA-256 {checksum(path)}")
    if inf.st_size > CAP:
        print("Above the ChatGPT attachment cap; retain in artifacts, don't try to attach it.")


def reusable_mesh_streams(previous):
    """Index verified prior mesh member bytes by raw SHA-256.

    Use an already qualified standard playable ZIP as a cache, never as
    the source of asset contents. This parser reads local member offsets;
    ZipFile.read validates each member's CRC and original byte length.
    """
    if previous is None:
        return {}
    result = {}
    with zipfile.ZipFile(previous) as archive, previous.open("rb") as raw:
        for info in archive.infolist():
            if (info.compress_type != zipfile.ZIP_DEFLATED or info.flag_bits & 1
                    or not playable_member(info.filename)
                    or not info.filename.endswith(".obj") or info.file_size < 8192):
                continue
            original = archive.read(info)
            if len(original) != info.file_size:
                raise ValueError(f"Incorrect reused mesh length: {info.filename}")
            raw.seek(info.header_offset)
            header = raw.read(30)
            if len(header) != 30 or header[:4] != b"PK\x03\x04":
                raise ValueError(f"Invalid cached mesh header: {info.filename}")
            namelen, extralen = struct.unpack_from("<HH", header, 26)
            raw.seek(namelen + extralen, 1)
            stream = raw.read(info.compress_size)
            if len(stream) != info.compress_size or zlib.decompress(stream, wbits=-15) != original:
                raise ValueError(f"Invalid reused DEFLATE stream: {info.filename}")
            key = hashlib.sha256(original).digest()
            if key not in result or len(stream) < len(result[key]):
                result[key] = stream
    return result


@contextmanager
def dense_mesh_deflate(active, previous=None):
    """Write stock ZIP DEFLATE streams, without changing any playable bytes.

    Only explicitly selected OBJ members use the optional Zopfli compressor.
    Restore the regular compressor before writing guides, proofs or history.
    """
    if not active:
        if previous is not None:
            raise ValueError("--reuse-dense-meshes requires --dense-playable")
        yield
        return
    regular = zipfile._get_compressor
    reused = reusable_mesh_streams(previous)
    compressor = None
    # Optional local lossless optimization. Existing verified streams win
    # whenever this one is not smaller. Normal archive readers still use
    # ordinary ZIP DEFLATE and every extracted OBJ byte is unchanged.
    if os.getenv("LUANTTD_PACKAGE_TRY_LIBDEFLATE") == "1":
        library = ctypes.util.find_library("deflate")
        if library:
            lib = ct.CDLL(library)
            pointer, size = ct.c_void_p, ct.c_size_t
            defs = [
                ("libdeflate_alloc_compressor", pointer, [ct.c_int]),
                ("libdeflate_deflate_compress_bound", size, [pointer, size]),
                ("libdeflate_deflate_compress", size, [pointer, pointer, size, pointer, size]),
                ("libdeflate_free_compressor", None, [pointer]),
            ]
            for name, result, args in defs:
                f = getattr(lib, name)
                f.restype, f.argtypes = result, args
            compressor = lib.libdeflate_alloc_compressor(12)

    class DenseMesh:
        def __init__(self):
            self.data = io.BytesIO()

        def compress(self, block):
            self.data.write(block)
            return b""

        def flush(self):
            raw = self.data.getvalue()
            self.data.close()
            stream = reused.get(hashlib.sha256(raw).digest()) if reused else None
            if compressor:
                cap = lib.libdeflate_deflate_compress_bound(compressor, len(raw))
                buf = ct.create_string_buffer(cap)
                n = lib.libdeflate_deflate_compress(compressor, raw, len(raw), buf, cap)
                if n:
                    candidate = buf.raw[:n]
                    ordinary = stream or zlib.compress(raw, level=9, wbits=-15)
                    return min(candidate, ordinary, key=len)
            if stream is not None:
                return stream
            # Python zopfli provides a zlib wrapper, while ZIP uses the same
            # DEFLATE data raw. The fixed header has no preset dictionary.
            # An unchanged, verified prior mesh cache needs no extra module.
            try:
                from zopfli import zlib as zopfli_zlib
            except ImportError as e:
                if previous is not None:
                    # Continue using verified dense streams for unchanged
                    # assets. New meshes are ordinary compatible DEFLATE.
                    return zlib.compress(raw, level=9, wbits=-15)
                raise RuntimeError("A mesh was not cached; --dense-playable needs Python's zopfli module") from e
            wrapped = zopfli_zlib.compress(raw, numiterations=2)
            assert wrapped[1] & 32 == 0
            chosen = wrapped[2:-4]
            ordinary = zlib.compress(raw, level=9, wbits=-15)
            return chosen if len(chosen) < len(ordinary) else ordinary

    def factory(kind, level=None):
        if kind == zipfile.ZIP_DEFLATED and level == 14:
            return DenseMesh()
        return regular(kind, level)

    zipfile._get_compressor = factory
    try:
        yield
    finally:
        zipfile._get_compressor = regular
        if compressor:
            lib.libdeflate_free_compressor(compressor)


def write_history_parts(repo, out, temp, ref, short, base_ref):
    """Keep complete Git history deliverable as smaller prerequisite bundles."""
    base = git("rev-parse", "--verify", base_ref + "^{commit}", cwd=repo)
    git("merge-base", "--is-ancestor", base, ref, cwd=repo)
    if base == ref:
        raise ValueError("Delivery history base must precede the target commit")
    mirror = temp / "bundle-mirror"
    git("clone", "--shared", "--bare", "-q", str(repo), str(mirror), cwd=repo)
    previous = None
    ready = []
    ends = [base, ref]
    while ends:
        end = ends.pop(0)
        n = len(ready) + 1
        git("update-ref", "refs/heads/main", end, cwd=mirror)
        git("symbolic-ref", "HEAD", "refs/heads/main", cwd=mirror)
        leaf = f"LuanTTD-history-{short}-part{n}.git.bundle"
        bundle = temp / leaf
        bundle.unlink(missing_ok=True)
        args = ["bundle", "create", str(bundle), "HEAD", "main"]
        reachable_tags = git("tag", "--merged", end, cwd=mirror).splitlines()
        earlier_tags = set(git("tag", "--merged", previous, cwd=mirror).splitlines()) if previous else set()
        args.extend("refs/tags/" + name for name in reachable_tags if name not in earlier_tags)
        if previous:
            args.append("^" + previous)
        git(*args, cwd=mirror)
        staged = temp / f"LuanTTD-source-{short}-part{n}.zip"
        with zipfile.ZipFile(staged, "w", compression=zipfile.ZIP_DEFLATED) as z:
            z.write(bundle, leaf)
        # Allow space for the final numbered restore directions. Large
        # steps are split on a real first-parent revision, never raw bytes.
        if staged.stat().st_size > CAP - 2048:
            range_ref = previous + ".." + end if previous else end
            commits = git("rev-list", "--first-parent", "--reverse", range_ref, cwd=mirror).splitlines()
            if len(commits) < 2:
                raise ValueError(f"A commit at {end[:7]} is too large for one delivery part; complete bundle retained")
            ends[0:0] = [commits[len(commits) // 2 - 1], end]
            continue
        ready.append((bundle, staged))
        previous = end
    trial = temp / "assembled"
    git("clone", "-q", str(ready[0][0]), str(trial), cwd=repo)
    instructions = [
        f"Git history for {ref}.",
        "Extract all numbered ZIPs next to each other. Then:",
        f"  git clone {ready[0][0].name} bayline",
        "  cd bayline",
    ]
    for bundle, _ in ready[1:]:
        git("fetch", "--tags", str(bundle), "main", cwd=trial)
        git("merge", "--ff-only", "FETCH_HEAD", cwd=trial)
        instructions.extend((f"  git fetch --tags ../{bundle.name} main", "  git merge --ff-only FETCH_HEAD"))
    instructions.append("  git rev-parse HEAD")
    if git("rev-parse", "HEAD", cwd=trial) != ref or git("tag", "--merged", ref, cwd=trial) != git("tag", "--merged", ref, cwd=repo):
        raise ValueError("Restored segmented Git history or tags do not match the playable revision")
    names = []
    for _, staged in ready:
        with zipfile.ZipFile(staged, "a", compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr("RESTORE.txt", "\n".join(instructions) + "\n")
        if staged.stat().st_size > CAP:
            raise ValueError(f"{staged.name} exceeds the file cap after restore instructions")
        deliver = out / staged.name
        shutil.copyfile(staged, deliver)
        verify(deliver)
        names.append(deliver)
    return names


def package(out, start, evidence, revision="HEAD", history_base=None, dense_playable=False,
            mesh_base=None):
    ref = git("rev-parse", "--verify", revision + "^{commit}")
    short = ref[:7]
    if ref != git("rev-parse", "HEAD"):
        raise ValueError("Package from the selected commit checked out as HEAD")
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="luanttd-package-") as tmp:
        p = Path(tmp)
        game = out / f"LuanTTD-overnight-playable-{short}.zip"
        source = out / f"LuanTTD-source-and-Linux-playtests-{short}.zip"
        bundle = out / f"LuanTTD-dev-{short}.git.bundle"
        tracked = p / "tracked.zip"
        git("archive", "--format=zip", "--prefix=bayline/", "--output", str(tracked), ref)
        git("bundle", "create", str(bundle), "HEAD", "main", "--tags")
        clone = p / "clone"
        git("clone", "-q", str(bundle), str(clone))
        if git("rev-parse", "HEAD", cwd=clone) != ref:
            raise ValueError("Bundle HEAD does not match the playable revision")
        if mesh_base is not None and mesh_base.resolve() == game.resolve():
            raise ValueError("Reuse meshes from a different, already verified preview")
        with dense_mesh_deflate(dense_playable, mesh_base), zipfile.ZipFile(tracked) as src, zipfile.ZipFile(
            game, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as z:
            z.writestr("START-HERE.txt", start.read_text().replace("@REVISION@", short))
            for member in src.infolist():
                if playable_member(member.filename):
                    level = 14 if dense_playable and member.filename.endswith(".obj") and member.file_size >= 65536 else 9
                    z.writestr(member, src.read(member), compress_type=zipfile.ZIP_DEFLATED, compresslevel=level)
            assert {"bayline/game.conf", "bayline/mods/bayline/init.lua",
                    "bayline/docs/generated-campaign.md"}.issubset(z.namelist())
        with zipfile.ZipFile(source, "w", compression=zipfile.ZIP_DEFLATED) as z:
            z.write(bundle, f"LuanTTD-source-{short}.git.bundle")
            names = set()
            for f in evidence:
                if not f.is_file() or f.is_symlink() or f.name in names:
                    raise ValueError(f"Not a unique evidence file: {f}")
                names.add(f.name)
                z.write(f, "Linux-playtest/" + f.name)
        verify(game)
        verify(source)
        if source.stat().st_size > CAP:
            # Large versions retain the complete Git bundle in artifacts.
            # Separate it from evidence for delivery, then fall back to a
            # committed full source snapshot only if history alone won't fit.
            src_only = out / f"LuanTTD-source-{short}.zip"
            proof_only = out / f"LuanTTD-Linux-playtests-{short}.zip"
            with zipfile.ZipFile(src_only, "w", compression=zipfile.ZIP_DEFLATED) as z:
                z.write(bundle, f"LuanTTD-source-{short}.git.bundle")
                z.writestr("RESTORE.txt", "Extract the bundle and run: git clone <bundle> bayline\n")
            if src_only.stat().st_size > CAP and history_base:
                write_history_parts(REPO, out, p, ref, short, history_base)
            elif src_only.stat().st_size > CAP:
                with zipfile.ZipFile(tracked) as src, zipfile.ZipFile(
                    src_only, "w", compression=zipfile.ZIP_DEFLATED
                ) as z:
                    z.writestr("SOURCE-REVISION.txt", f"Git commit {ref}. Full history retained separately.\n")
                    for member in src.infolist():
                        z.writestr(member, src.read(member), compress_type=zipfile.ZIP_DEFLATED)
            with zipfile.ZipFile(proof_only, "w", compression=zipfile.ZIP_DEFLATED) as z:
                for f in evidence:
                    z.write(f, "Linux-playtest/" + f.name)
            verify(src_only)
            verify(proof_only)
        return game, source, bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--start", type=Path, required=True)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--history-base", help="Known small ancestor for two delivery archives")
    parser.add_argument("--dense-playable", action="store_true",
                        help="Use optional Zopfli for large meshes while retaining ordinary unpackable ZIP")
    parser.add_argument("--reuse-dense-meshes", type=Path,
                        help="Reuse verbatim verified compression for unchanged meshes in this prior preview ZIP")
    parser.add_argument("evidence", type=Path, nargs="*")
    args = parser.parse_args()
    package(args.out, args.start, args.evidence, args.revision, args.history_base,
            args.dense_playable, args.reuse_dense_meshes)


if __name__ == "__main__":
    main()
