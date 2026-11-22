#!/usr/bin/env python3
"""Validate and mount the private real loaded OpenTTD fixture in native Luanti."""
from hashlib import sha256
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import openttd_sparse as fixture
from openttd_save_bus_checkpoint import checkpoint

TESTS,REPO=fixture.TESTS,fixture.REPO


def verify(server, save, port, reference=None):
    raw=save.read_bytes()
    digest=sha256(raw).hexdigest()
    state=checkpoint(raw)
    assert state["map"]["source"]["sha256"]==digest
    assert state["status"]=="paused-validation-only" and not state["can_resume_in_luanti"]
    with tempfile.TemporaryDirectory(prefix="luanttd-paused-bus-") as name:
        home=Path(name)
        games=home/"games"
        game=games/"buscheckpoint"
        mod=game/"mods"/"buscheckpoint"
        mod.mkdir(parents=True)
        (mod/"mod.conf").write_text("name = buscheckpoint\n")
        (game/"game.conf").write_text("title = OpenTTD paused bus acceptance probe\n")
        shutil.copyfile(TESTS/"openttd_bus_checkpoint_native.lua",mod/"init.lua")
        modules=REPO/"mods"/"bayline"
        for file in ("world_storage.lua","import/openttd_map.lua","import/openttd_sparse.lua",
                     "import/openttd_bus_checkpoint.lua",
                     *("openttd/"+x+".lua" for x in ("slope","road_slope","road_motion","road_motion_data",
                                                "yapf_road_follow","yapf_road_cost","yapf_road_search","income"))):
            shutil.copyfile(modules/file,mod/Path(file).name)
        (mod/"checkpoint.json").write_text(json.dumps(state,sort_keys=True))
        (mod/"reference.json").write_text(json.dumps(json.loads(reference.read_text()) if reference else {}))
        conf=home/"luanti.conf"
        conf.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n")
        cmd=[server,"--gameid","buscheckpoint","--world",home/"world","--config",conf,"--logfile",""]
        env={**os.environ,"HOME":str(home),"LUANTI_GAME_PATH":str(games),"MINETEST_GAME_PATH":str(games)}
        p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=30)
        log=p.stdout+p.stderr
        assert p.returncode==0 and "ERROR[" not in log and "LUANTTD PAUSED STOCK BUS CHECKPOINT PASS" in log,log
        if reference:
            assert "LUANTTD STOCK FARE DIFFERENTIAL PASS" in log,log
        for line in log.splitlines():
            if "LUANTTD PAUSED STOCK BUS CHECKPOINT PASS" in line or "LUANTTD STOCK FARE DIFFERENTIAL PASS" in line:
                print(line)
    assert sha256(save.read_bytes()).hexdigest()==digest


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--luanti",type=Path,required=True)
    p.add_argument("--save",type=Path,required=True,help="private unmodified loaded-bus oracle save")
    p.add_argument("--port",type=int,default=39782)
    p.add_argument("--reference-json",type=Path,help="stock-only continuation report for fare differential")
    a=p.parse_args()
    verify(a.luanti.resolve(),a.save.resolve(),a.port,a.reference_json)
