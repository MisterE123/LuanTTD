#!/usr/bin/env python3
"""Read bus-world state from OpenTTD 14.1. This is not a playable save loader."""
# SPDX-License-Identifier: GPL-2.0-only
# OpenTTD 14.1 src/saveload/{depot,station,order,vehicle,misc}_sl.cpp,
# src/{order_base,cargopacket,station_type}.h. See COPYING.OpenTTD.md.
from pathlib import Path
import argparse
import json
import lzma
import zlib

from openttd_save_inspect import LIMIT, SaveError
from openttd_save_map import snapshot
from openttd_save_tables import decode_tables, reference

POOLS = (b"DATE",b"CITY",b"PLYR",b"DEPT",b"ROAD",b"STNN",b"VEHS",b"ORDL",b"ORDR",b"CAPA")
# OpenTTD order's low nibble encodes the order type; upper bits are flags.
GOTO_STATION = 1


def one(items, what):
    if not isinstance(items, list) or len(items) != 1:
        raise SaveError(f"Expected one serialized {what}")
    return items[0]


def chain(start, pool, field, what):
    result, seen = [], set()
    while (obj := reference(start,pool,what)) is not None:
        if obj in seen:
            raise SaveError(f"Cyclic {what} list")
        seen.add(obj)
        result.append(obj)
        start = pool[obj][field]
    return result


def normalize(map_data, tables):
    clock = one(list(tables[b"DATE"].values()),"clock")
    towns, companies = (tables[t] for t in (b"CITY",b"PLYR"))
    depots, stops, stations = (tables[t] for t in (b"DEPT",b"ROAD",b"STNN"))
    vehicles, orderlists, orders, packets = (tables[t] for t in (b"VEHS",b"ORDL",b"ORDR",b"CAPA"))
    mapped_roads = map_data["road_tiles"]
    relevant_stops, relevant_depots = {}, {}
    for tile, road in mapped_roads.items():
        if road["kind"]=="depot":
            number = road["depot_id"]
            if number in relevant_depots or number not in depots or depots[number]["xy"]!=int(tile):
                raise SaveError(f"Road depot at tile {tile} has an invalid depot object")
            depot = depots[number]
            relevant_depots[number] = {"tile":int(tile),"owner":road["depot_owner"],
                "town_id":reference(depot["town"],towns,"depot town")}
        elif road["kind"] in ("bay_stop","drive_stop"):
            relevant_stops[int(tile)] = (road["station_id"],road["stop_type"],road["station_owner"])

    station_records, consumed = {}, set()
    for sid in {ident for ident,_,_ in relevant_stops.values()}:
        if sid not in stations:
            raise SaveError(f"Dangling station map ID {sid}")
        station = one(stations[sid]["normal"],"non-waypoint station")
        base = one(station["base"],"station base record")
        station_records[sid] = {"tile":base["xy"],"owner":base["owner"],
            "town_id":reference(base["town"],towns,"station town"),"road_stops":[]}
        for name in ("bus","truck"):
            for ident in chain(station[name+"_stops"],stops,"next","road stop"):
                data = stops[ident]
                tile = data["xy"]
                if tile in consumed or relevant_stops.get(tile) != (sid,name,base["owner"]):
                    raise SaveError(f"Station {sid} and its road stop object disagree at tile {tile}")
                consumed.add(tile)
                station_records[sid]["road_stops"].append({"road_stop_id":ident,"tile":tile,
                                                            "status":data["status"],"type":name})
    if consumed != set(relevant_stops):
        raise SaveError("A map stop is missing from its station's road stop chain")

    result_vehicles, used_packets = {}, set()
    for vid,row in vehicles.items():
        if not row["roadveh"]:
            continue
        road = one(row["roadveh"],"road vehicle")
        v = one(road["common"],"vehicle common record")
        if v["owner"] not in companies:
            raise SaveError(f"Road vehicle {vid} has an invalid owner")
        ident = reference(v["orders"],orderlists,"vehicle order list")
        order_chain = [] if ident is None else chain(orderlists[ident]["first"],orders,"next","order")
        normalized = []
        for oid in order_chain:
            order = orders[oid]
            if order["type"]&15 == GOTO_STATION and order["dest"] not in stations:
                raise SaveError(f"Invalid station destination in order {oid}")
            normalized.append(dict(order,order_id=oid))
        carried = []
        for ref in v["cargo.packets"]:
            packet_id = reference(ref,packets,"onboard cargo packet")
            if packet_id is None or packet_id in used_packets:
                raise SaveError(f"Road vehicle {vid} has a null or repeated cargo packet")
            used_packets.add(packet_id)
            record = packets[packet_id]
            if not record["count"]:
                raise SaveError("Empty onboard cargo packet")
            carried.append(dict(record,packet_id=packet_id))
        state_fields = ("tile","dest_tile","owner","engine_type","x_pos","y_pos","z_pos",
                        "direction","vehstatus","cur_speed","subspeed","progress","cargo_type",
                        "cargo_cap","cargo_age_counter","last_loading_station",
                        "cur_implicit_order_index","cur_real_order_index","current_order.type",
                        "current_order.dest","current_order.flags","profit_this_year","cargo.action_counts")
        result_vehicles[vid] = {k:v[k] for k in state_fields if k in v}
        result_vehicles[vid].update(
            motion={k:val for k,val in road.items() if k!="common"},
            order_list_id=ident, orders=normalized, packets=carried,
            onboard=sum(p["count"] for p in carried))
    return {"can_resume_in_luanti":False, "schema":"luanttd-openttd-bus-state/1",
            "source":map_data["source"],"game_clock":{k:v for k,v in clock.items() if k!="id"},
            "stations":station_records,
            "depots":relevant_depots,"road_vehicles":result_vehicles,
            "company_balances":{i:{"money":c["money"],"loan":c["current_loan"]}
                                for i,c in companies.items()}}


def probe_bus_state(blob):
    try:
        return normalize(snapshot(blob),decode_tables(blob,set(POOLS)))
    except (KeyError,TypeError) as exc:
        raise SaveError("OpenTTD save did not contain the expected bus-world fields") from exc


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("save",type=Path)
    args = p.parse_args()
    try:
        with args.save.open("rb") as src:
            blob=src.read(LIMIT+1)
        print(json.dumps(probe_bus_state(blob),indent=2,sort_keys=True))
    except (SaveError,OSError,lzma.LZMAError,zlib.error) as exc:
        p.exit(1,f"Bus world state not extracted: {exc}\n")


if __name__=="__main__":
    main()
