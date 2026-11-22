#!/usr/bin/env python3
"""Extract inputs for one isolated delivery/settlement exercise, not an importer."""
from pathlib import Path
import argparse
import json

from openttd_save_inspect import LIMIT, SaveError
from openttd_save_bus_checkpoint import checkpoint, one
from openttd_save_tables import decode_tables, reference


def resume_input(blob, third_station=False, depot_reserve=False):
    if depot_reserve and not third_station:
        raise SaveError("The reserve case requires the separately selected third-stop fixture")
    stage=checkpoint(blob,depot_reserve)
    tables=decode_tables(blob,{b"STNN",b"CAPA",b"CAPY",b"SUBS",b"PLYR",b"PATS",b"VEHS"})
    if tables[b"CAPY"] or tables[b"SUBS"]:
        raise SaveError("Pending payments or subsidies are outside the isolated delivery exercise")
    states=stage["bus_state"]
    vid,bus=next(iter(states["road_vehicles"].items()))
    company=next(iter(states["company_balances"]))
    served={o["dest"] for o in bus["orders"]}
    station_ids=set(states["stations"])
    if len(served)!=2 or not served<=station_ids or len(station_ids)!=(3 if third_station else 2):
        raise SaveError("Fixture station count does not match its explicitly selected closed scope")
    additional=station_ids-served
    if third_station:
        alt,=additional
        if alt in served or len(states["stations"][alt]["road_stops"])!=1 or states["stations"][alt]["owner"]!=company:
            raise SaveError("The additional station must already be an owned, distinct, one-tile bus stop")
    sid=bus["current_order.dest"]
    town=states["stations"][sid]["town_id"]
    src=one(tables[b"STNN"][sid]["normal"],"destination station")
    goods=src["goods"][0]  # cargo ID already checked as stock temperate PAX
    pats=one(list(tables[b"PATS"].values()),"settings")
    acc=int(goods["status"] & 1)
    if goods["cargo.reserved_count"] or goods["flow"] or not acc:
        raise SaveError("Destination must accept passengers with manual, unreserved cargo")
    waiting=[]
    seen={p["packet_id"] for p in bus["packets"]}
    for bucket in goods["cargo"]:
        if bucket["first"]!=65535:
            raise SaveError("Support only the stock unaddressed station cargo bucket")
        for ref in bucket["second"]:
            i=reference(ref,tables[b"CAPA"],"destination waiting passenger")
            if i is None or i in seen:
                raise SaveError("Null or duplicate waiting passenger reference")
            seen.add(i)
            p=tables[b"CAPA"][i]
            if not (p["source"]==sid and p["source_xy"]==4294967295 and p["source_type"]==1
                    and p["source_id"]==town and p["feeder_share"]==0 and 0<p["count"]<=31):
                raise SaveError("Support only local, never-boarded waiting passengers")
            waiting.append(dict(p,packet_id=i,feeder_share=str(p["feeder_share"])))
    if not waiting or sum(p["count"] for p in waiting)>31:
        raise SaveError("Expected a bounded waiting queue at the target bay")
    veh=one(one(tables[b"VEHS"][vid]["roadveh"],"bus")["common"],"bus")
    ec=one(tables[b"PLYR"][company]["cur_economy"],"current economy")
    extra={"schema":"luanttd-bus-first-delivery/1","paused":True,"source_sha256":stage["map"]["source"]["sha256"],
           "target_station":sid,"target_town":town,"target_goods":{k:goods[k] for k in (
               "status","time_since_pickup","rating","last_speed","last_age","amount_fract","max_waiting_cargo")},
           "queue":waiting,"gradual_loading":pats["order.gradual_loading"],
           "stock_breakdown_setting":pats["difficulty.vehicle_breakdowns"],
           "current_order_time":veh["current_order_time"],"lateness_counter":veh["lateness_counter"],
           "starting_company_delivered":ec["delivered_cargo"][0],
           "starting_company_income":str(ec["income"])}
    if third_station:
        extra["existing_third_station"]=alt
    if depot_reserve:
        extra["depot_reserve_id"]=states["depot_reserve"]["id"]
    if extra["gradual_loading"]!=1 or extra["starting_company_delivered"]!=0 or extra["starting_company_income"]!="0":
        raise SaveError("Expected the first gradual passenger delivery in the stock fixture")
    return {"schema":"luanttd-bus-first-delivery-input/1","checkpoint":stage,"resume":extra}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("save",type=Path)
    p.add_argument("--output",type=Path,required=True,help="new private fixture output; never overwrite")
    p.add_argument("--with-existing-third-station",action="store_true")
    p.add_argument("--with-depot-reserve",action="store_true")
    a=p.parse_args()
    try:
        with a.save.open("rb") as source:
            data=resume_input(source.read(LIMIT+1),a.with_existing_third_station,a.with_depot_reserve)
        with a.output.open("x",encoding="utf-8") as out:
            json.dump(data,out,sort_keys=True,separators=(",",":"))
            out.write("\n")
    except (KeyError,TypeError,SaveError,OSError) as exc:
        p.exit(1,f"Resume fixture not extracted: {exc}\n")


if __name__=="__main__":
    main()
