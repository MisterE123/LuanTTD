#!/usr/bin/env python3
"""Mount a private real 14.1-generated snapshot in a disposable Luanti probe."""
import argparse
from hashlib import sha256
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

TESTS = Path(__file__).resolve().parent
REPO = TESTS.parent
# The existing native oracle runner and the tool have the same basename.
SPEC = importlib.util.spec_from_file_location("_stock_save_oracle", TESTS / "openttd_save_map.py")
STOCK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STOCK)
MATCH = re.compile(r"\] SAVE_(SLOPE|CONNECTED|BAY|DEPOT|THROUGH|BUS) ([\d ]+)")


def verify(server, home, data, points, port):
    games = home / "games"
    game = games / "sparseprobe"
    mod = game / "mods" / "sparseprobe"
    mod.mkdir(parents=True)
    (game / "game.conf").write_text("title = OpenTTD sparse baseline probe\n")
    (mod / "mod.conf").write_text("name = sparseprobe\n")
    shutil.copyfile(TESTS / "openttd_sparse_luanti.lua", mod / "init.lua")
    modules = REPO / "mods" / "luanttd_core"
    for file in (modules / "openttd" / "terrain.lua", modules / "openttd" / "slope.lua",
                 modules / "import" / "openttd_map.lua", modules / "import" / "openttd_sparse.lua",
                 modules / "world_storage.lua"):
        shutil.copyfile(file, mod / file.name)
    (mod / "snapshot.json").write_text(json.dumps(data, sort_keys=True))
    (mod / "official.json").write_text(json.dumps(points))
    config = home / "server.conf"
    config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n")
    env = {**os.environ, "HOME": str(home), "LUANTI_GAME_PATH": str(games),
           "MINETEST_GAME_PATH": str(games)}
    cmd = [server, "--gameid", "sparseprobe", "--world", home / "world",
           "--config", config, "--logfile", ""]
    proc = subprocess.run(cmd, env=env, timeout=30, capture_output=True, text=True)
    output = proc.stdout + proc.stderr
    match = re.search(r"LUANTTD STOCK SPARSE OVERLAY PASS: .*", output)
    assert proc.returncode == 0 and match and "ERROR[" not in output, output
    print(match.group())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luanti", type=Path, required=True)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--openttd", type=Path, help="official 14.1 executable that generates a fresh fixture")
    inputs.add_argument("--save", type=Path, help="replay a private fixture from the stock oracle")
    parser.add_argument("--share", type=Path, help="stock 14.1 resources (with OpenGFX)")
    parser.add_argument("--oracle-log", type=Path, help="captured stock oracle observations for replay")
    parser.add_argument("--oracle-port", type=int, default=39777)
    parser.add_argument("--luanti-port", type=int, default=39778)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-sparse-") as name:
        home = Path(name)
        if args.openttd:
            if not args.share:
                parser.error("--openttd requires --share")
            source, points = STOCK.oracle(args.openttd.resolve(), args.share.resolve(), home / "stock", args.oracle_port)
        else:
            if not args.oracle_log:
                parser.error("--save requires --oracle-log")
            source = args.save.resolve()
            log = args.oracle_log.read_text()
            if "Network revision name: 14.1" not in log or "SAVE_DONE" not in log:
                parser.error("expected a completed stock OpenTTD 14.1 oracle log")
            points = [(k, list(map(int, v.split()))) for k, v in MATCH.findall(log)]
        original = source.read_bytes()
        data = STOCK.snapshot(original)
        STOCK.compare(data, points)
        verify(args.luanti.resolve(), home / "luanti", data, points, args.luanti_port)
        assert sha256(source.read_bytes()).hexdigest() == data["source"]["sha256"]


if __name__ == "__main__":
    main()
