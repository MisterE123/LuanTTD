#!/usr/bin/env python3
"""Build a developer-only paused bus checkpoint from a narrow stock 14.1 save."""
from pathlib import Path
import argparse
import json
import lzma
import zlib

from openttd_save_inspect import LIMIT, SaveError
from openttd_save_map import snapshot
from openttd_save_bus_state import POOLS, normalize, one
from openttd_save_tables import decode_tables
from openttd_save_reserve_bus import source_record

SCHEMA = "luanttd-openttd-bus-checkpoint/1"
REQUIRED_SETTINGS = {
    "game_creation.landscape": 0,  # Temperate
    "economy.timekeeping_units": 0,
    "economy.minutes_per_calendar_year": 12,
    "economy.inflation": 0,
    "linkgraph.distribution_pax": 0,  # manual cargo routing
    "pf.pathfinder_for_roadvehs": 2,  # YAPF
}
YAPF = ("road_slope_penalty","road_curve_penalty","road_crossing_penalty","road_stop_penalty",
        "road_stop_occupied_penalty","road_stop_bay_occupied_penalty")


def checkpoint(blob, depot_reserve=False):
    try:
        board = snapshot(blob)
        if board["source"]["save_version"]!=334 or (board["width"],board["height"])!=(256,256):
            raise SaveError("Expected one stock 14.1 256×256 source map")
        tables = decode_tables(blob,{*POOLS,b"PATS",b"NGRF"})
        if tables[b"NGRF"]:
            raise SaveError("NewGRFs are outside the supported paused checkpoint")
        settings = one(list(tables[b"PATS"].values()),"settings row")
        for key,value in REQUIRED_SETTINGS.items():
            if settings[key]!=value:
                raise SaveError(f"Unsupported checkpoint setting {key}={settings[key]}")
        settings_out = {key:settings[key] for key in REQUIRED_SETTINGS}
        for key in ("vehicle.road_side","vehicle.roadveh_acceleration_model","pf.yapf.max_search_nodes",
                    "pf.yapf.disable_node_optimization",
                    *("pf.yapf."+name for name in YAPF)):
            settings_out[key] = settings[key]
        if len(tables[b"PLYR"])!=1 or any(not (rec.get("roadveh") or rec.get("effect"))
                                          for rec in tables[b"VEHS"].values()):
            raise SaveError("Expected one company with one bus; other transport fleets are not supported")
        records = normalize(board,tables)
        fleet=records["road_vehicles"]
        vid=one([i for i,v in fleet.items() if v["onboard"]],"loaded MPS Regal Bus")
        bus=fleet[vid]
        if len(fleet)!=(2 if depot_reserve else 1):
            raise SaveError("Road vehicle count does not match its explicitly selected closed scope")
        if depot_reserve:
            rid=one([i for i in fleet if i!=vid],"depot reserve")
            records["depot_reserve"]=source_record(tables,records,vid,rid)
            records["road_vehicles"]={vid:bus}
        if bus["engine_type"]!=116 or bus["cargo_type"]!=0 or bus["cargo_cap"]!=31 or not bus["onboard"]:
            raise SaveError("Expected a loaded stock MPS Regal passenger bus")
        if records["game_clock"]["pause_mode"]!=1:
            raise SaveError("A manually paused source is required")
        if any(v not in records["stations"] for v in tables[b"STNN"]):
            raise SaveError("Non-road stations are outside the tested checkpoint")
        for station in tables[b"STNN"].values():
            row = one(station["normal"],"ordinary station")
            if row["loading_vehicles"] or row["truck_stops"] or any(row[k] for k in (
                    "train_station.w","ship_station.w","airport.w","docking_station.w","speclist")):
                raise SaveError("Unsupported station facilities or active loading")
        towns = {rec["town_id"] for pool in ("stations","depots") for rec in records[pool].values()}
        for packet in bus["packets"]:
            if packet["source_type"]!=1 or packet["source_id"] not in tables[b"CITY"]:
                raise SaveError("Expected an onboard packet originating at a stock town")
            towns.add(packet["source_id"])
            packet["feeder_share"] = str(packet["feeder_share"])
        vid = next(iter(records["road_vehicles"]))
        common = one(one(tables[b"VEHS"][vid]["roadveh"],"stock road vehicle")["common"],"stock common state")
        bus["vehicle_timers"] = {k:common[k] for k in (
            "tick_counter","running_ticks","last_loading_tick","load_unload_ticks","breakdown_ctr",
            "breakdown_delay","breakdowns_since_last_service","breakdown_chance")}
        bus["active_timetable"] = {k:common["current_order."+k] for k in (
            "max_speed","refit_cargo","travel_time","wait_time")}
        records["town_anchors"] = {i:{"tile":tables[b"CITY"][i]["xy"]} for i in towns if i is not None}
        records["game_clock"]["tick_counter"] = str(records["game_clock"]["tick_counter"])
        bus["profit_this_year"] = str(bus["profit_this_year"])
        for i,c in records["company_balances"].items():
            raw = tables[b"PLYR"][i]
            c["money"],c["loan"],c["max_loan"] = str(c["money"]),str(c["loan"]),str(raw["max_loan"])
            c["money_fraction"],c["is_ai"] = raw["money_fraction"],bool(raw["is_ai"])
        return {"schema":SCHEMA,"status":"paused-validation-only","can_resume_in_luanti":False,
                "settings":settings_out,"map":board,"bus_state":records}
    except (KeyError,TypeError) as exc:
        raise SaveError(f"Missing or invalid stock checkpoint field: {exc}") from exc


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("save",type=Path)
    p.add_argument("--output",type=Path,help="create a new checkpoint JSON file, never overwrite")
    a=p.parse_args()
    try:
        with a.save.open("rb") as src:
            data=checkpoint(src.read(LIMIT+1))
        text=json.dumps(data,sort_keys=True,separators=(",",":"))+"\n"
        if a.output:
            with a.output.open("x",encoding="utf-8") as out:
                out.write(text)
        else:
            print(text,end="")
    except (SaveError,OSError,lzma.LZMAError,zlib.error) as exc:
        p.exit(1,f"Bus checkpoint not extracted: {exc}\n")


if __name__=="__main__":
    main()
