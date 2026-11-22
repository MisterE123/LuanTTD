#!/usr/bin/env python3
"""Build and trace two running buses at a native OpenTTD 14.1 T-junction."""
import argparse
from hashlib import sha256
import json
import lzma
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import zlib

import openttd_sparse as fixture
from openttd_save_bus_state import SaveError, probe_bus_state
from openttd_save_tables import decode_tables

SCHEMA = "luanttd-stock-two-bus-junction/1"
STOCK = fixture.STOCK
ORIGIN = 173 * 256 + 96
THROUGH = ORIGIN + 3
JUNCTION = ORIGIN + 4
BAY = ORIGIN + 8
BRANCH = JUNCTION + 256


def prepare(ai, delay):
    script = ai / "main.nut"
    code = script.read_text()
    mark = "        local owner=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);"
    assert code.count(mark) == 1
    code = code.replace(mark, '''
        local junction=a+4, branch=junction+w;
        Require(AIRoad.BuildRoad(junction,junction+w),"Open southern arm at T-junction");
        Require(AIRoad.BuildRoadStation(branch,junction,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build south bay at flat T-junction");
        Require(AIRoad.AreRoadTilesConnected(junction,branch),"Check south-facing frontage");
''' + mark)
    dispatch = '        Require(AIVehicle.StartStopVehicle(v),"Dispatch stock bus");'
    assert code.count(dispatch) == 1
    suffix = '''
        local other=AIVehicle.BuildVehicle(d,engine);
        Require(AIVehicle.IsValidVehicle(other) && other!=v,"Build second working MPS Regal");
        Require(AIOrder.AppendOrder(other,branch,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order independent south turn");
        Require(AIOrder.AppendOrder(other,b,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order east turn");
''' + dispatch + f'''
        if ({delay}>0) this.Sleep({delay});
        Require(AIVehicle.StartStopVehicle(other),"Dispatch independently ordered bus");
        for (local i=0; i<700; i++) {{
            this.Sleep(1);
            local first=AIVehicle.GetLocation(v), second=AIVehicle.GetLocation(other);
            if (AIVehicle.GetState(v)==AIVehicle.VS_RUNNING &&
                    AIVehicle.GetState(other)==AIVehicle.VS_RUNNING && first>=a && first<=b &&
                    second>=a && second<=s) {{
                AILog.Info("SAVE_DONE");
                while (true) this.Sleep(1000);
            }}
        }}
        throw "Two independent buses did not reach the approach together";
    }}
}}
'''
    script.write_text(code[:code.index(dispatch)] + suffix)


def generate(binary, share, output, port, delay):
    if output.exists():
        raise SaveError("Private junction fixture output must be new")
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-junction-") as d:
        source, _ = STOCK.oracle(binary, share, Path(d), port,
                                 private_fixture=lambda ai: prepare(ai, delay))
        blob = source.read_bytes()
        validate_start(blob)
        with output.open("xb") as f:
            f.write(blob)
    return sha256(blob).hexdigest()


def validate_start(blob):
    world = probe_bus_state(blob)
    if world["game_clock"]["pause_mode"] != 1:
        raise SaveError("Junction capture is not a manually paused stock save")
    board = STOCK.snapshot(blob)
    if (board["width"], board["height"]) != (256, 256):
        raise SaveError("Fixture dimensions changed")
    road = board["road_tiles"]
    arena = {THROUGH: ("drive_stop",10), JUNCTION: ("road",14), BRANCH: ("bay_stop",1),
             BAY: ("bay_stop",8), **{t: ("road",10) for t in range(JUNCTION+1,BAY)}}
    heights = b"".join(bytes.fromhex(row) for row in board["corner_rows_hex"])
    for t,(kind,mask) in arena.items():
        tile=road.get(str(t),{})
        if ((tile.get("kind"),tile.get("road_bits"),tile.get("road_type")) != (kind,mask,0)
                or any(heights[t+corner]!=1 for corner in (0,1,256,257))):
            raise SaveError("Stock fixture lane topology or flat elevation changed")
    vehicles, stations = world["road_vehicles"], world["stations"]
    if len(vehicles) != 2 or set(stations) != {0, 1, 2}:
        raise SaveError("Expected only the two fixture buses and three fixture stops")
    through, east, branch = (next(i for i, s in stations.items() if s["tile"] == tile)
                             for tile in (THROUGH, BAY, BRANCH))
    routes = {tuple(o["dest"] for o in v["orders"]): (i, v) for i, v in vehicles.items()}
    if set(routes) != {(through, east), (branch, east)}:
        raise SaveError("Two independent stock bus order lists do not match fixture")
    tables=decode_tables(blob, {b"PATS",b"NGRF",b"VEHS"})
    if tables[b"NGRF"]:
        raise SaveError("The stock junction does not admit NewGRFs")
    settings, = tables[b"PATS"].values()
    if settings["vehicle.road_side"] != 1 or settings["vehicle.roadveh_acceleration_model"] != 1:
        raise SaveError("Fixture requires stock right-hand realistic driving")
    if sum(not v["effect"] for v in tables[b"VEHS"].values()) != 2 or set(world["company_balances"]) != {0}:
        raise SaveError("Only the two fixture vehicles and one company are supported")
    ids = []
    for key in ((through, east), (branch, east)):
        ident, v = routes[key]
        if (v["owner"] != 0 or v["engine_type"] != 116 or v["cargo_type"] != 0
                or v["motion"]["state"] >= 254 or v["tile"] not in range(ORIGIN, (BAY if key == (through, east) else THROUGH) + 1)):
            raise SaveError("Junction bus not active in the pinned approach and engine")
        ids.append(ident)
    if vehicles[ids[0]]["order_list_id"] == vehicles[ids[1]]["order_list_id"]:
        raise SaveError("Fixture buses must have independent order lists")
    return ids


COMMON = ("tile", "dest_tile", "x_pos", "y_pos", "z_pos", "direction",
          "cur_speed", "subspeed", "progress", "vehstatus", "cargo_age_counter",
          "current_order.type", "current_order.dest", "cur_real_order_index",
          "tick_counter", "current_order_time", "load_unload_ticks", "breakdown_ctr", "breakdown_delay")
MOTION = ("state", "frame", "blocked_ctr", "reverse_ctr", "overtaking", "overtaking_ctr", "gv_flags")


def sample(blob, ids):
    tables = decode_tables(blob, {b"DATE", b"VEHS", b"CAPA"})
    clock, = tables[b"DATE"].values()
    if not 0 <= clock["tick_counter"] < 2**53-6000:
        raise SaveError("Native fixture clock is outside the exact JSON integer aperture")
    buses = []
    for ident in ids:
        row, = tables[b"VEHS"][ident]["roadveh"]
        v, = row["common"]
        carried = [{k: tables[b"CAPA"][p-1][k] for k in ("count","periods_in_transit","source")}
                   | {"id": p-1} for p in v["cargo.packets"]]
        buses.append({"id": ident, **{k: v[k] for k in COMMON}, **{k: row[k] for k in MOTION},
                      "onboard": sum(p["count"] for p in carried), "packets": carried, "order_max_speed": v["current_order.max_speed"],
                      "cached_tiles": row["path.tile"], "cached_td": row["path.td"]})
    clock = {k: v.hex() if isinstance(v, bytes) else v for k, v in clock.items()}
    return {"clock": clock, "buses": buses}


def trace(binary, share, source, port, limit, pulse):
    blob = source.read_bytes()
    ids = validate_start(blob)
    digest = sha256(blob).hexdigest()
    start = sample(blob, ids)
    with tempfile.TemporaryDirectory(prefix="luanttd-junction-reopen-") as d:
        root = Path(d)
        private = root / ".openttd"
        (private / "ai").mkdir(parents=True)
        for name in ("lang", "baseset", "game"):
            (private / name).symlink_to(share / name, target_is_directory=True)
        observer = private / "ai" / "SaveProbe"
        observer.mkdir()
        shutil.copyfile(STOCK.HERE.with_name("openttd_save_ai") / "info.nut", observer / "info.nut")
        (observer / "main.nut").write_text(
            "class SaveProbe extends AIController { function Start() { while (true) this.Sleep(1000); } }\n")
        config = root / "server.cfg"
        config.write_text("[network]\nserver_game_type = local\nframe_freq = 1\n")
        env = {**os.environ, "HOME": str(root), "XDG_CONFIG_HOME": str(root / "config"),
               "XDG_DATA_HOME": str(root / "share")}
        args = [binary, "-s", "null", "-m", "null", "-I", "OpenGFX", "-D", f"127.0.0.1:{port}",
                "-c", config, "-g", source]
        logfile = root / "stock.log"
        with logfile.open("w") as log, subprocess.Popen(args, cwd=share, env=env, stdin=subprocess.PIPE,
                                                       stdout=log, stderr=subprocess.STDOUT,
                                                       text=True) as game:
            def send(*commands):
                game.stdin.write("\n".join(commands) + "\n")
                game.stdin.flush()

            def readlog():
                return logfile.read_text(errors="replace")

            def checked(predicate, description, timeout=8):
                until = time.monotonic() + timeout
                while time.monotonic() < until:
                    assert game.poll() is None, readlog()
                    if result := predicate():
                        return result
                    time.sleep(.008)
                raise AssertionError(description + "\n" + readlog()[-5000:])

            def capture(i):
                label = f"probe_{i:03d}"
                send("save " + label)

                def try_save():
                    for folder in (root, private):
                        p = folder / "save" / (label + ".sav")
                        if p.is_file():
                            try:
                                return sample(p.read_bytes(), ids)
                            except (SaveError, OSError, lzma.LZMAError, zlib.error):
                                pass

                return checked(try_save, "No complete stock capture " + label)

            try:
                checked(lambda: re.search(r"Network revision name: 14\.1\b", readlog()),
                        "Pinned stock 14.1 did not start", 15)
                control = capture(0)
                assert control == start, (control, start)
                output = [control]
                for i in range(1, limit + 1):
                    prior = readlog().count("Game paused (manual)")
                    resume_count = readlog().count("Game unpaused (manual)")
                    send("unpause")
                    checked(lambda: readlog().count("Game unpaused (manual)") > resume_count,
                            "Stock visibility did not reach manual unpause")
                    time.sleep(pulse)
                    send("pause")
                    checked(lambda: readlog().count("Game paused (manual)") > prior,
                            "Stock visibility did not reach manual pause")
                    point = capture(i)
                    k = point["clock"]["tick_counter"]
                    prev = output[-1]["clock"]["tick_counter"]
                    assert point["clock"]["pause_mode"] == 1 and k >= prev
                    if k > prev:
                        output.append(point)
            finally:
                game.terminate()
                try:
                    game.wait(5)
                except subprocess.TimeoutExpired:
                    game.kill()
                    game.wait()
    assert sha256(source.read_bytes()).hexdigest() == digest, "stock source save unexpectedly changed"
    return {"schema":SCHEMA, "open_ttd_source":"native unmodified 14.1",
            "source_sha256": digest, "source_unchanged": True, "vehicle_ids": ids, "junction": JUNCTION,
            "through": THROUGH, "east_bay": BAY, "branch": BRANCH, "samples": output}


# Full-length stock road vehicle box, UpdateDeltaXY and
# AddSortableSpriteToDraw. These are viewport sorting boxes, NOT collision hulls.
VIEW = ((3,3,-1,-1,0,0),(3,7,-1,-3,0,-1),(3,3,-1,-1,0,0),(7,3,-3,-1,-1,0),
        (3,3,-1,-1,0,0),(3,7,-1,-3,0,-1),(3,3,-1,-1,0,0),(7,3,-3,-1,-1,0))


def stock_box(a):
    h, w, dy, dx, by, bx = VIEW[a["direction"]]
    x, y = a["x_pos"] + dx, a["y_pos"] + dy
    return (x + bx, y + by, x + w, y + h) # half-open instead of stock inclusive maxima


def classify(trace):
    shared, blocked, turn, overlap, merging, cross_heading, merge_blocked = [], [], [], [], [], [], []
    samples = trace["samples"]
    merge_overlap_moving = []
    previous = None
    for row in samples:
        a, b = row["buses"]
        tick = row["clock"]["tick_counter"]
        if a["tile"] == b["tile"] == JUNCTION:
            shared.append(tick)
            if a["direction"] != b["direction"]:
                cross_heading.append(tick)
                if a["direction"] == 5 and b["state"] == 5:
                    turn.append(tick)
        if a["tile"] == JUNCTION and b["blocked_ctr"]:
            if a["direction"] == b["direction"] == 5 and a["cur_speed"] == b["cur_speed"]:
                blocked.append(tick)
        if (a["direction"]==5 and b["direction"]==6 and b["state"]==11 and
                b["tile"]==JUNCTION and b["blocked_ctr"] and a["cur_speed"]==b["cur_speed"]):
            merge_blocked.append(tick)
        box_a, box_b = stock_box(a), stock_box(b)
        if (min(box_a[2], box_b[2]) > max(box_a[0], box_b[0])
                and min(box_a[3], box_b[3]) > max(box_a[1], box_b[1])
                and abs(a["z_pos"] - b["z_pos"]) < 6):
            overlap.append(tick)
            if (previous and a["tile"]==b["tile"]==JUNCTION and b["state"]==11
                    and a["direction"]==5 and b["direction"]==6
                    and a["blocked_ctr"]==b["blocked_ctr"]==0
                    and all((v["x_pos"],v["y_pos"])!=(old["x_pos"],old["y_pos"])
                            for v,old in zip((a,b),previous))):
                merge_overlap_moving.append(tick)
        if (a["tile"] == b["tile"] == JUNCTION and a["direction"] == 5
                and b["direction"] in (5, 6, 7) and b["state"] == 11):
            merging.append(tick)
        previous = a,b
    return {"shared_junction_ticks": shared, "follower_blocked_ticks": blocked,
            "diverging_junction_ticks": turn, "stock_viewport_overlap_ticks": overlap,
            "different_heading_junction_ticks": cross_heading, "merging_junction_ticks": merging,
            "merge_blocked_ticks": merge_blocked, "merge_moving_overlap_ticks":merge_overlap_moving}


def native_window(trace):
    samples = trace["samples"]
    merge = bool(classify(trace)["merge_blocked_ticks"])
    if merge:
        def merge_gate(row):
            a,b = row["buses"]
            return (a["state"] == 8 and a["tile"] == b["tile"] == JUNCTION and b["state"] == 11
                    and a["direction"] == 5 and b["direction"] == 7 and b["frame"] <= 4
                    and a["blocked_ctr"] == b["blocked_ctr"] == 0)
        i = next(i for i,row in enumerate(samples) if merge_gate(row))
        j = next(j for j in range(i+1,len(samples)) if samples[j]["buses"][1]["tile"] == JUNCTION+1)
        return {**trace, "mode": "merge", "samples": samples[i:j+1]}
    def gate(row):
        a,b = row["buses"]
        return (a["tile"] == JUNCTION and a["state"] == 8 and b["tile"] == THROUGH
                and b["state"] == 72 and 5 <= b["frame"] <= 10 and a["direction"] == b["direction"] == 5
                and a["blocked_ctr"] == b["blocked_ctr"] == 0)
    i = next(i for i, row in enumerate(samples) if gate(row))
    j = next(j for j in range(i+1,len(samples)) if samples[j]["buses"][1]["tile"] == BRANCH)
    assert 20 <= j-i <= 100 and samples[j-1]["buses"][1]["frame"] >= 13
    return {**trace, "mode":"follower", "samples": samples[i:j]}


def luanti_differential(server, port, trace, author=None):
    spec = native_window(trace)
    if author is not None:
        spec["author"] = author
    with tempfile.TemporaryDirectory(prefix="luanttd-junction-native-") as name:
        root = Path(name)
        game = root / "games" / "junction_qa"
        mod = game / "mods" / "junction_qa"
        mod.mkdir(parents=True)
        (game / "game.conf").write_text("title = Stock Road Junction Differential\n")
        (mod / "mod.conf").write_text("name = junction_qa\n")
        shutil.copyfile(Path(__file__).with_name("openttd_road_junction_native.lua"), mod / "init.lua")
        kernels = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core" / "openttd"
        for module in ("road_motion", "road_motion_data", "road_speed", "road_proximity", "road_overtake"):
            shutil.copyfile(kernels / (module+".lua"), mod / (module+".lua"))
        (mod / "input.json").write_text(json.dumps(spec))
        cfg = root / "qa.conf"
        cfg.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\nprometheus_listener_address = 127.0.0.1:{port}\n")
        env = {**os.environ, "HOME": str(root), "LUANTI_GAME_PATH": str(root / "games"),
               "MINETEST_GAME_PATH": str(root / "games")}
        proc = subprocess.run([server, "--gameid", "junction_qa", "--world", root / "test",
                               "--config", cfg, "--logfile", ""], env=env,
                              capture_output=True, text=True, timeout=20)
        log = proc.stdout + proc.stderr
        proof = re.search(r"LuanTTD stock junction differential PASS (.*)", log)
        assert proc.returncode == 0 and proof, log
        report = {"clock_start": spec["samples"][0]["clock"]["tick_counter"],
                  "clock_end": spec["samples"][-1]["clock"]["tick_counter"],
                  **json.loads(proof[1])}
        if author is not None:
            intent = re.search(r"LuanTTD stock dual-active author intent (.*)", log)
            assert intent, log
            report["order_intent"] = json.loads(intent[1])
        return report


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("openttd", "share", "source"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--port", type=int, default=39839)
    p.add_argument("--dispatch-delay", type=int, default=1)
    p.add_argument("--generate", action="store_true")
    p.add_argument("--luanti", type=Path)
    p.add_argument("--luanti-port", type=int, default=39840)
    p.add_argument("--expect", choices=("follower", "merge"))
    p.add_argument("--from-trace", type=Path)
    p.add_argument("--limit", type=int, default=130)
    p.add_argument("--pulse", type=float, default=.005)
    a = p.parse_args()
    binary, share, source = (getattr(a, arg).resolve() for arg in ("openttd", "share", "source"))
    if not 0 <= a.dispatch_delay <= 250 or not 1 <= a.limit <= 600 or not 0 <= a.pulse <= .5:
        p.error("Unsupported delay, sample count or pulse interval")
    if a.generate:
        print(json.dumps({"source_sha256": generate(binary, share, source, a.port, a.dispatch_delay)}))
    else:
        result = (json.loads(a.from_trace.read_text()) if a.from_trace else
                  trace(binary, share, source, a.port, a.limit, a.pulse))
        if a.from_trace:
            source_bytes = source.read_bytes()
            assert sha256(source_bytes).hexdigest() == result["source_sha256"]
            ids = validate_start(source_bytes)
            assert ids==result["vehicle_ids"] and sample(source_bytes, ids)==result["samples"][0]
            assert (result["junction"],result["through"],result["east_bay"],result["branch"]) == (JUNCTION,THROUGH,BAY,BRANCH)
            result["schema"] = SCHEMA
            result["open_ttd_source"] = "recorded native 14.1 trace, opening checkpoint revalidated"
        result["observed"] = classify(result)
        if a.expect == "follower":
            assert result["observed"]["follower_blocked_ticks"] and result["observed"]["diverging_junction_ticks"], result["observed"]
        if a.expect == "merge":
            observed = result["observed"]
            overlaps_with_heading_difference = set(observed["stock_viewport_overlap_ticks"]) & set(observed["different_heading_junction_ticks"])
            assert (observed["merging_junction_ticks"] and observed["merge_blocked_ticks"]
                    and overlaps_with_heading_difference and observed["merge_moving_overlap_ticks"]), observed
        if a.luanti:
            result["luanti_differential"] = luanti_differential(a.luanti.resolve(), a.luanti_port, result)
        print(json.dumps(result, sort_keys=True))
