#!/usr/bin/env python3
"""Exercise sidecar and bounded stream with a private 14.1 save in Luanti."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import openttd_sparse as fixtures
from openttd_save_ground import ground_sidecar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luanti", type=Path, required=True)
    parser.add_argument("--save", type=Path, required=True)
    parser.add_argument("--oracle-log", type=Path, required=True)
    parser.add_argument("--port", type=int, default=39779)
    args = parser.parse_args()
    source = args.save.resolve()
    blob = source.read_bytes()
    initial_hash = sha256(blob).hexdigest()
    log = args.oracle_log.read_text()
    assert "Network revision name: 14.1" in log and "SAVE_DONE" in log
    points = [(k, list(map(int,v.split()))) for k,v in fixtures.MATCH.findall(log)]
    data = fixtures.STOCK.snapshot(blob)
    fixtures.STOCK.compare(data,points)
    sidecar = ground_sidecar(blob)
    assert sidecar["source_sha256"] == initial_hash
    with tempfile.TemporaryDirectory(prefix="luanttd-stream-native-") as name:
        home = Path(name)
        games = home/"games"
        game = games/"stockstream"
        mod = game/"mods"/"stockstream"
        mod.mkdir(parents=True)
        (mod/"mod.conf").write_text("name = stockstream\n")
        (game/"game.conf").write_text("title = OpenTTD bounded terrain streaming probe\n")
        shutil.copyfile(fixtures.TESTS/"terrain_stream_native.lua",mod/"init.lua")
        modules = fixtures.REPO/"mods"/"luanttd_core"
        for file in ("import/openttd_ground.lua", "import/openttd_map.lua", "import/openttd_sparse.lua",
                     "openttd/slope.lua", "world_storage.lua", "terrain_stream.lua", "terrain_word.lua"):
            shutil.copyfile(modules/file,mod/Path(file).name)
        for key,payload in (("snapshot",data),("ground",sidecar),("official",points)):
            (mod/(key+".json")).write_text(json.dumps(payload,sort_keys=True))
        config = home/"luanti.conf"
        config.write_text(f"port = {args.port}\nbind_address = 127.0.0.1\nserver_announce = false\n")
        command = [args.luanti.resolve(),"--gameid","stockstream","--world",home/"world",
                   "--config",config,"--logfile",""]
        env = {**os.environ,"HOME":str(home),"LUANTI_GAME_PATH":str(games),"MINETEST_GAME_PATH":str(games)}
        proc = subprocess.run(command,env=env,timeout=50,capture_output=True,text=True)
        log = proc.stdout+proc.stderr
        m = re.search(r"LUANTTD STOCK TERRAIN STREAM PASS: .*",log)
        assert proc.returncode==0 and m and "ERROR[" not in log,log
        print(m.group())
    assert sha256(source.read_bytes()).hexdigest() == initial_hash


if __name__ == "__main__":
    main()
