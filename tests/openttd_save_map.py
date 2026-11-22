#!/usr/bin/env python3
"""Verify map extraction against unmodified OpenTTD 14.1 and its Script APIs."""
import argparse
from copy import deepcopy
from hashlib import sha256
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1] / "tools"))
from openttd_save_map import decode_road, snapshot
from openttd_save_inspect import SaveError
from openttd_save_bus_state import POOLS, normalize, probe_bus_state
from openttd_save_tables import decode_tables


def oracle(binary, share, home, port, private_fixture=None):
    personal = home / ".openttd"
    (personal / "ai").mkdir(parents=True)
    for name in ("lang", "baseset", "game"):
        (personal / name).symlink_to(share / name, target_is_directory=True)
    for f in (share/"ai").glob("*.nut"):
        (personal/"ai"/f.name).symlink_to(f)
    shutil.copytree(HERE.with_name("openttd_save_ai"), personal/"ai"/"SaveProbe")
    if private_fixture:
        private_fixture(personal/"ai"/"SaveProbe")
    config = home/"openttd.cfg"
    config.write_text("[network]\nserver_game_type = local\n")
    expected_saves = (home/"save"/"road-fixture.sav", personal/"save"/"road-fixture.sav")
    env = {**os.environ, "HOME":str(home), "XDG_CONFIG_HOME":str(home/"config"),
           "XDG_DATA_HOME":str(home/"share")}
    cmd = [binary, "-s","null", "-m","null", "-I","OpenGFX", "-D",f"127.0.0.1:{port}",
           "-G","1751", "-d","script=5", "-c",config]
    with subprocess.Popen(cmd, cwd=share, env=env, text=True, stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          bufsize=1) as game:
        lines = queue.Queue()

        def read():
            for line in game.stdout:
                lines.put(line)
            lines.put(None)

        def submit(*lines):
            game.stdin.write("\n".join(lines) + "\n")
            game.stdin.flush()

        threading.Thread(target=read, daemon=True).start()
        revision, finished, output, points = False, False, [], []
        deadline = time.monotonic()+80
        try:
            while time.monotonic() < deadline:
                expected_save = next((p for p in expected_saves if p.is_file()), None)
                if finished and expected_save is not None and expected_save.stat().st_size > 0:
                    raw = expected_save.read_bytes()
                    try:
                        snapshot(raw)
                    except (SaveError, OSError):
                        pass  # file is still being written
                    else:
                        return expected_save, points
                try:
                    line = lines.get(timeout=.2)
                except queue.Empty:
                    continue
                if line is None:
                    break
                output.append(line.strip())
                if os.getenv("LUA_NTTD_SAVE_TRACE"): print(line, end="", flush=True)
                if "Network revision name: 14.1" in line:
                    revision = True
                if "Map generated, starting game" in line:
                    assert revision, "The oracle must be stock OpenTTD 14.1"
                    submit("start_ai SaveProbe", "unpause")
                if "The script died unexpectedly" in line:
                    break
                match = re.search(r"\] SAVE_(SLOPE|CONNECTED|BAY|DEPOT|THROUGH|BUS) ([\d ]+)",line)
                if match:
                    points.append((match[1], list(map(int, match[2].split()))))
                if "] SAVE_DONE" in line:
                    submit("pause")
                if "Game paused (manual)" in line and not finished:
                    finished = True
                    submit("save road-fixture")
            raise AssertionError("Fixture not saved:\n" + "\n".join(output[-20:])+
                                 "\nSaves: "+str(list(home.rglob("*.sav"))))
        finally:
            game.terminate()
            try:
                game.wait(5)
            except subprocess.TimeoutExpired:
                game.kill()


def compare(data, points):
    assert data["schema"] == "luanttd-openttd-map/1"
    assert not data["can_resume_in_luanti"]
    assert data["source"]["save_version"] == 334
    w, h = data["width"], data["height"]
    assert w == h == 256
    heights = b"".join(bytes.fromhex(row) for row in data["corner_rows_hex"])
    tiles = b"".join(bytes.fromhex(row) for row in data["tile_type_rows_hex"])
    assert len(heights) == len(tiles) == w*h
    assert all(t==7 for t in tiles[-w:]) and all(t==7 for t in tiles[w-1::w])
    road = {int(t):r for t,r in data["road_tiles"].items()}
    counts = {"flat":0, "sloped":0, "connected":0, "disconnected":0}
    for tag, (tile,*expected) in points:
        if tag == "SLOPE":
            corners = [heights[tile+i] for i in (0,1,w,w+1)]
            base = min(corners)
            slope = sum(m for m,v in zip((8,1,4,2), corners) if v != base)
            if max(corners)-base==2:
                slope |= 16
            assert [base,slope] == expected, (tile,[base,slope],expected)
            counts["sloped" if slope else "flat"] += 1
        elif tag == "DEPOT":
            rec = road[tile]
            assert rec["kind"] == "depot" and rec["depot_id"] == 0, rec
            front = tile + [-1,w,1,-w][rec["direction"]]
            assert [front,rec["depot_owner"]] == expected, rec
        elif tag == "BAY":
            rec = road[tile]
            assert rec["kind"] == "bay_stop" and rec["stop_type"] == "bus", rec
            front = tile + [-1,w,1,-w][rec["direction"]]
            assert [front,rec["station_id"],rec["station_owner"]] == expected, rec
            assert rec["station_id"] == 0, rec
        elif tag == "THROUGH":
            rec = road[tile]
            assert [rec["kind"],rec["axis"],rec["station_id"],rec["station_owner"]] == [
                "drive_stop",0,*expected], rec
            assert rec["road_bits"] == 0xA, rec
        elif tag == "CONNECTED":
            dest, result = expected
            i = (-w,1,w,-1).index(dest-tile)
            ev = bool(road.get(tile,{}).get("road_bits",0) & 1<<i
                      and road.get(dest,{}).get("road_bits",0) & 1<<((i+2)%4))
            assert ev == bool(result), (tile,dest,road.get(tile),road.get(dest),result)
            counts["connected" if ev else "disconnected"] += 1
    assert counts["flat"] and counts["sloped"]>20, counts
    assert counts["connected"] and counts["disconnected"], counts
    return counts




def check_in_flight(raw, map_data, points):
    _, values = next(p for p in points if p[0]=="BUS")
    vid, tile, engine, cargo, load, first, second = values
    probe = probe_bus_state(raw)
    bus = probe["road_vehicles"][vid]
    assert not probe["can_resume_in_luanti"]
    assert [bus["tile"],bus["engine_type"],bus["cargo_type"],bus["onboard"]] == [
        tile,engine,cargo,load], bus
    assert probe["game_clock"]["pause_mode"] & 1, "fixture must be manually paused"
    assert bus["cur_speed"]>0 and bus["current_order.dest"]==second and bus["owner"]==0, bus
    assert bus["order_list_id"]==0 and bus["orders"][0]["order_id"]==0, bus["orders"]
    assert [o["dest"] for o in bus["orders"]]==[first,second]
    assert probe["stations"][second]["road_stops"][0]["road_stop_id"]==0
    assert probe["depots"][0]["owner"]==0 and probe["company_balances"][0]["money"]>0
    assert all(p["source"]==first for p in bus["packets"]), bus["packets"]
    older = [p["periods_in_transit"] for p in bus["packets"] if p["periods_in_transit"]>0]
    assert older, "loaded bus fixture must preserve non-zero cargo age"

    tables = decode_tables(raw,set(POOLS))
    # Target raw encoded reference to pin index 0 vs null, and catch a
    # malformed save that still looks plausible in a map-only inspection.
    row = tables[b"VEHS"][vid]["roadveh"][0]["common"][0]
    assert row["orders"]==1
    assert tables[b"ORDL"][0]["first"]==1 and tables[b"ORDR"][1]["next"]==0
    for mutate in (
        lambda x: x[b"VEHS"][vid]["roadveh"][0]["common"][0].update(orders=0xFFFF),
        lambda x: x[b"ORDR"][1].update(next=1),
        lambda x: x[b"ROAD"][0].update(xy=0),
        lambda x: x[b"VEHS"][vid]["roadveh"][0]["common"][0]["cargo.packets"].append(0xFFFF),
    ):
        damaged = deepcopy(tables)
        mutate(damaged)
        try:
            normalize(map_data,damaged)
        except SaveError:
            pass
        else:
            raise AssertionError("Accepted a damaged/cyclic in-flight state")
    print(f"PASS: in-flight bus {vid}, engine {engine}, destination {second}, "
          f"{load} rider(s), packet ages {older}; preserved 0 vs null and rejected bad links.")


def check_luanti(server, home, snapshot_path, points, port):
    games = home/"games"
    game = games/"map-probe"
    mod = game/"mods"/"map_probe"
    mod.mkdir(parents=True)
    (game/"game.conf").write_text("title = OpenTTD map adapter probe\n")
    (mod/"mod.conf").write_text("name = map_probe\n")
    shutil.copyfile(HERE.with_name("openttd_save_map_luanti.lua"),mod/"init.lua")
    modules = HERE.parents[1]/"mods"/"luanttd_core"
    for file in (modules/"openttd"/"terrain.lua", modules/"openttd"/"slope.lua",
                 modules/"import"/"openttd_map.lua"):
        shutil.copyfile(file,mod/file.name)
    shutil.copyfile(snapshot_path,mod/"snapshot.json")
    (mod/"official.json").write_text(json.dumps(points))
    config = home/"probe.conf"
    config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n")
    env = {**os.environ, "HOME":str(home), "LUANTI_GAME_PATH":str(games),
           "MINETEST_GAME_PATH":str(games)}
    command = [server,"--gameid","map-probe","--world",home/"luanti-world",
               "--config",config,"--logfile",""]
    proc = subprocess.run(command,env=env,timeout=30,capture_output=True,text=True)
    log = proc.stdout+proc.stderr
    assert proc.returncode==0 and "LuanTTD OpenTTD map adapter PASS" in log, log
    print("PASS: native Luanti loaded the JSON into its shared-corner grid; terrain and tile IDs match stock.")


def check_table_indices():
    lead = b"OTTN\x01\x4e\0\0TSTB"
    schema = b"\x05\x01n\0"  # one signed 32-bit field
    field = (-33).to_bytes(4,"big",signed=True)
    h = bytes([len(schema)+1])+schema
    dense = lead+b"\3"+h+b"\5"+field+b"\1\5"+field+bytes(5)
    sparse = lead+b"\4"+h+b"\6\0"+field+b"\7\x80\xff"+field+bytes(5)
    assert decode_tables(dense,{b"TSTB"}) == {b"TSTB":{0:{"n":-33},2:{"n":-33}}}
    assert decode_tables(sparse,{b"TSTB"}) == {b"TSTB":{0:{"n":-33},255:{"n":-33}}}
    duplicate = lead+b"\4"+h+b"\6\0"+field+b"\6\0"+field+bytes(5)
    for invalid in (duplicate,dense[:-1],sparse+b"x"):
        try:
            decode_tables(invalid,{b"TSTB"})
        except SaveError:
            pass
        else:
            raise AssertionError("Accepted duplicate or malformed table data")


def main():
    check_table_indices()
    # Non-vanilla content must be tagged rather than represented as regular road.
    trammed = decode_road(2,15,0,0xFB,0,0x2A,0,0,1<<6)
    assert trammed["tram_owner"]==16 and trammed["road_bits"]==10
    assert trammed["unsupported_for_initial_bus_world"]==["one_way_road","tram"]
    crossing = decode_road(2,0,0,0,0,0x71,0,16,63<<6)
    assert crossing["axis"]==1 and crossing["rail_axis"]==0
    assert crossing["road_bits"]==5 and crossing["reserved"] and crossing["barred"]
    assert crossing["unsupported_for_initial_bus_world"]==["rail_crossing"]
    for args in ((2,0,0,0,0,0xC0,0,0,0),(5,0,0,0,0,6,3<<3,0,0)):
        try:
            decode_road(*args)
        except SaveError:
            pass
        else:
            raise AssertionError("accepted invalid stock tile layout")

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("binary",type=Path)
    p.add_argument("share",type=Path)
    p.add_argument("--port",type=int,default=39723)
    p.add_argument("--retain-fixture",type=Path,help="new, private copy of the input")
    p.add_argument("--luanti",type=Path,help="optional Luanti server to exercise the Lua adapter")
    args = p.parse_args()
    with tempfile.TemporaryDirectory(prefix="openttd-save-") as tmp:
        source,points = oracle(args.binary.resolve(),args.share.resolve(),Path(tmp),args.port)
        raw = source.read_bytes()
        output = Path(tmp)/"snapshot.json"
        cmd = [sys.executable, str(HERE.parents[1]/"tools"/"openttd_save_map.py"),
               str(source), "--output", str(output)]
        subprocess.run(cmd,check=True)
        data = json.loads(output.read_text())
        assert data["source"]["sha256"]==sha256(raw).hexdigest()
        counts = compare(data, points)
        check_in_flight(raw, data, points)
        for target in (output, source, Path(tmp)/"source-link"):
            if target.name=="source-link":
                target.symlink_to(source)
            refused = subprocess.run([*cmd[:-1],str(target)],capture_output=True,text=True)
            assert refused.returncode==1 and "File exists" in refused.stderr, refused.stderr
        assert source.read_bytes()==raw, "map snapshot command changed original .sav"
        if args.luanti:
            check_luanti(args.luanti.resolve(),Path(tmp),output,points,args.port)
        if args.retain_fixture:
            with args.retain_fixture.open("xb") as file:
                file.write(raw)
        print("PASS: stock OpenTTD 14.1 snapshot: depot, bay, through stop, "
              f"zero-based IDs, supported/unsupported markers and {counts}")
        print("PASS: output existing path, source path and source symlink refused; source digest unchanged.")


if __name__ == "__main__":
    main()
