"""Read-only exact parked-reserve checks for the narrow stock fleet experiment."""
from hashlib import sha256
import json

from openttd_save_inspect import SaveError
from openttd_save_tables import reference


def stock_json(value):
    """Lossless serialization of raw table scalars, lists and text bytes."""
    if isinstance(value, bytes):
        return {"raw_hex": value.hex()}
    if isinstance(value, int) and abs(value) >= 2**53:
        return {"exact_integer": str(value)}
    if isinstance(value, list):
        return [stock_json(i) for i in value]
    if isinstance(value, dict):
        return {k:stock_json(v) for k,v in value.items()}
    return value


def fingerprint(value):
    return sha256(json.dumps(stock_json(value),sort_keys=True,ensure_ascii=True,
                             separators=(",",":")).encode("utf-8")).hexdigest()


def raw_records(pools, rid):
    whole=pools[b"VEHS"][rid]
    road,=whole["roadveh"]
    common,=road["common"]
    lid=reference(common["orders"],pools[b"ORDL"],"reserve order list")
    if lid is None:
        raise SaveError("Reserve lost its independent order list")
    ol=pools[b"ORDL"][lid]
    oid=reference(ol["first"],pools[b"ORDR"],"reserve first order")
    if oid is None:
        raise SaveError("Reserve has no independent first order")
    order=pools[b"ORDR"][oid]
    if order["next"]!=0:
        raise SaveError("Only a one-order parked reserve is accepted")
    return {"id":rid,"order_list_id":lid,"order_id":oid,
            "vehicle":whole,"order_list":ol,"order":order}


def parked(raw, binding):
    """Guard the deliberately supported reserve behavior, not future counters."""
    road,=raw["vehicle"]["roadveh"]
    v,=road["common"]
    order=raw["order"]
    if not (raw["id"]==binding["id"] and raw["order_list_id"]==binding["order_list_id"]
            and raw["order_id"]==binding["order_id"] and v["owner"]==binding["owner"]
            and v["orders"]==raw["order_list_id"]+1 and raw["order_list"]["first"]==raw["order_id"]+1
            and v["next_shared"]==0
            and v["engine_type"]==116 and v["cargo_type"]==0 and v["cargo_cap"]==31
            and v["tile"]==binding["depot_tile"] and v["x_pos"]==binding["x16"]
            and v["y_pos"]==binding["z16"] and v["z_pos"]==binding["y8"]
            and v["direction"]==binding["heading"] and v["vehstatus"]==11
            and v["cur_speed"]==v["subspeed"]==v["progress"]==0 and v["running_ticks"]==0
            and v["cargo.packets"]==[] and v["cargo.action_counts"]==[0,0,0,0]
            and v["cur_implicit_order_index"]==v["cur_real_order_index"]==0
            and v["dest_tile"]==0 and v["current_order.type"]==0 and v["current_order.flags"]==0
            and v["last_loading_station"]==65535 and v["last_station_visited"]==65535
            and v["breakdown_ctr"]==v["breakdown_delay"]==0
            and road["state"]==254 and road["frame"]==0 and road["gv_flags"]==4
            and road["path.td"]==road["path.tile"]==[]
            and road["blocked_ctr"]==road["crashed_ctr"]==road["reverse_ctr"]==road["overtaking_ctr"]==road["overtaking"]==0
            and order["dest"]==binding["order_station"] and all(order[k]==binding["raw"]["order"][k] for k in order)):
        raise SaveError("Unsupported reserve movement, cargo, order or position")


def source_record(tables, records, primary_id, rid):
    primary=records["road_vehicles"][primary_id]
    reserve=records["road_vehicles"][rid]
    got=raw_records(tables,rid)
    if len(reserve["orders"])!=1 or reserve["onboard"]!=0 or reserve["owner"]!=primary["owner"]:
        raise SaveError("The second bus must be an empty same-company reserve")
    order=reserve["orders"][0]
    served=[x["dest"] for x in primary["orders"]]
    upcoming=served[(primary["cur_real_order_index"]+1)%len(served)]
    if got["order_list_id"]==primary["order_list_id"] or order["order_id"] in {
        x["order_id"] for x in primary["orders"]} or order["dest"]!=upcoming or order["type"]!=97 or (
            order["flags"]!=0 or order["refit_cargo"]!=254 or order["max_speed"]!=65535):
        raise SaveError("The second bus's separately owned order must target the original return stop")
    depot=next((k for k,v in records["depots"].items() if v["tile"]==reserve["tile"] and
                v["owner"]==reserve["owner"]),None)
    if depot is None:
        raise SaveError("The second bus must be stopped inside the mapped depot")
    raw=stock_json(got)
    binding={"id":rid,"order_list_id":got["order_list_id"],"order_id":got["order_id"],"order_station":order["dest"],
             "owner":reserve["owner"],"depot_id":depot,"depot_tile":reserve["tile"],
             "x16":reserve["x_pos"],"z16":reserve["y_pos"],"y8":reserve["z_pos"],"heading":reserve["direction"],
             "raw":raw,"raw_sha256":fingerprint(got)}
    parked(got,binding)
    return binding
