#!/usr/bin/env python3
"""Native 14.1 one-tile drive-through bus-stop authoring on an existing owned road."""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from openttd_road_construction_export import (HOME, POOLS, StockAction, actor, clock, decode_map,
                                              matched_control, snapshot, source_gate)
from openttd_dual_active_export import read_save
from openttd_export_order_experiment import Native, SaveError, decode_tables, digest, require
from openttd_save_bus_state import probe_bus_state
from openttd_terraform_export import protected_wire, prove_reopen

SITE,FRONT,NEW=44385,44386,3


def qualified(blob):
    c,_=source_gate(blob)
    _,_,w,h,p,_=decode_map(blob)
    board=snapshot(blob)
    roads=board["road_tiles"]
    r=roads.get(str(SITE),{})
    require((w,h)==(256,256) and [p[b"MAPH"][SITE+i] for i in (0,1,w,w+1)]==[1]*4
            and p[b"MAPT"][SITE]==0x20 and p[b"MAPE"][SITE]>>4==0
            and r.get("kind")=="road" and r.get("road_bits")==10 and r.get("road_owner")==0
            and r.get("road_type")==0 and r.get("disallowed")==0
            and r.get("unsupported_for_initial_bus_world")==[],
            "Site is not a flat unblocked company-owned regular stock road")
    require(all(roads[str(SITE+i)]["kind"]=="road" for i in (-1,1))
            and roads[str(SITE-1)]["road_bits"]&2 and roads[str(SITE+1)]["road_bits"]&8,
            "Unsupported through topology or adjacent station merge")
    world=probe_bus_state(blob)
    require(not any(v["tile"]==SITE for v in world["road_vehicles"].values())
            and set(world["stations"])=={0,1,2} and set(c[b"ROAD"])=={0,1,2},
            "Closed station/stop pool or site occupancy changed")
    return c,board


def quote(luanti,root,port,blob,data,board):
    game=root/"games"/"drive_stop_lab"
    mod=game/"mods"/"drive_stop_lab"
    mod.mkdir(parents=True)
    (game/"game.conf").write_text("title = Stock drive-through stop quote\n")
    (mod/"mod.conf").write_text("name = drive_stop_lab\n")
    shutil.copyfile(HOME/"openttd_drive_stop_native.lua",mod/"init.lua")
    repo=HOME.parent/"mods"/"luanttd_core"
    for name in ("openttd/terrain.lua","openttd/slope.lua","openttd/road_slope.lua",
                 "openttd/road_bridge.lua","openttd/yapf_road_follow.lua","import/openttd_map.lua"):
        shutil.copyfile(repo/name,mod/Path(name).name)
    settings=next(iter(data[b"PATS"].values()))
    company=data[b"PLYR"][0]
    spec={"schema":"luanttd-drive-stop-input/1","source_sha256":digest(blob),
          "source_tick":clock(data),"site":SITE,"front":FRONT,"stop_type":"bus",
          "owner":0,"road_type":0,"platform":"drive_stop","new_station":True,
          "requested_tile_count":1,"occupied":False,"roadworks":False,"inflation":65536,
          "no_existing_join":True,"construction_difficulty":settings["difficulty.construction_cost"],
          "cash":company["money"],"snapshot":board}
    (mod/"input.json").write_text(json.dumps(spec))
    config=root/"game.conf"
    config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n"
                      f"prometheus_listener_address = 127.0.0.1:{port}\n")
    env={**os.environ,"HOME":str(root),"MINETEST_GAME_PATH":str(root/"games"),"LUANTI_GAME_PATH":str(root/"games")}
    proc=subprocess.run([luanti,"--gameid","drive_stop_lab","--world",root/"world","--config",config,"--logfile",""],
                        env=env,capture_output=True,text=True,timeout=20)
    log=proc.stdout+proc.stderr
    match=re.search(r"LuanTTD stock drive-through quote (.*)",log)
    require(proc.returncode==0 and match,log)
    receipt=json.loads(match[1])
    body=receipt["body"]
    result=json.loads(body)
    require(digest(body.encode())==receipt["sha256"] and result["schema"]=="luanttd-drive-stop-quote/1"
            and all(result[k]==spec[k] for k in ("source_sha256","source_tick","site","front","owner"))
            and [result[k] for k in ("axis","road_bits","new_road_pieces","rejected_lab_inputs")]==[0,10,0,9]
            and result["cost"]==result["facility_cost"]>0 and result["station_site_is_new"],
            "Native Luanti did not produce the exact closed qualified quote")
    return result,receipt["sha256"]


COMMAND = """
class SaveProbe extends AIController {
  function Require(ok, why) { if (!ok) throw why + ": " + AIError.GetLastErrorString(); }
  function Start() {
    this.SetCommandDelay(1);
    AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
    local s=44385,front=44386;
    local bus=AIRoad.ROADVEHTYPE_BUS, isolated=AIStation.STATION_NEW;
    Require(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)==0 && AITile.GetOwner(s)==0
      && AIRoad.IsRoadTile(s) && !AIRoad.IsRoadStationTile(s)
      && AITile.GetSlope(s)==AITile.SLOPE_FLAT && AITile.GetMinHeight(s)==1
      && AIRoad.AreRoadTilesConnected(s,s-1) && AIRoad.AreRoadTilesConnected(s,s+1),
      "Wrong unoccupied straight company road");
    local quote=0;
    {
      local tally=AIAccounting();
      local dry=AITestMode();
      Require(AIRoad.BuildDriveThroughRoadStation(s,front,bus,isolated),"Stock through-stop query failed");
      quote=tally.GetCosts();
      Require(!AIRoad.IsRoadStationTile(s),"Quote attempted to change map");
    }
    local tally=AIAccounting();
    Require(AIRoad.BuildDriveThroughRoadStation(s,front,bus,isolated),"Stock rejected actual construction");
    local station=AIStation.GetStationID(s);
    Require(station==3 && AIRoad.IsDriveThroughRoadStationTile(s) && AITile.GetOwner(s)==0
      && AIRoad.AreRoadTilesConnected(s,s-1) && AIRoad.AreRoadTilesConnected(s,s+1),
      "Native new through stop did not preserve both road edges");
    AILog.Info("DRIVE_AUTHOR_DONE "+quote+" "+tally.GetCosts()+" "+station);
    while(true) this.Sleep(1000);
  }
}
"""


def execute(stock,source,plan):
    c=stock.save()
    require(qualified(c)==qualified(source),"Native build did not open the same original state")
    for _ in range(12):
        stock.step(0)
        log=stock.read()
        require("The script died unexpectedly" not in log,log)
        m=re.search(r"DRIVE_AUTHOR_DONE (\d+) (\d+) (\d+)",log)
        if m:
            require([int(x) for x in m.groups()]==[int(plan["cost"]),int(plan["cost"]),NEW],
                    "Native dry and charged station quotation mismatch")
            return stock.save()
    raise SaveError("Native station construction callback did not complete")


def compare_map(old,new):
    _,_,_,_,p,_=decode_map(old)
    _,_,_,_,q,_=decode_map(new)
    changes=[]
    for k,b in p.items():
        stride=2 if k in (b"MAP2",b"MAP8") else 1
        require(len(b)==len(q[k]),"Invalid native map dimensions")
        diff={i//stride for i,(x,y) in enumerate(zip(b,q[k])) if x!=y}
        require(diff<={SITE} and (k!=b"MAPH" or not diff),"Native command changed unrelated land")
        if diff: changes.append(k.decode())
    require("MAPT" in changes and "MAP2" in changes,"Native build did not modify an official station map record")
    old_r=snapshot(old)["road_tiles"]
    new_r=snapshot(new)["road_tiles"]
    expected={"kind":"drive_stop","unsupported_for_initial_bus_world":[],"axis":0,"station_id":NEW,
              "station_owner":0,"stop_type":"bus","custom_stop_spec":0,"road_bits":10,"road_type":0,"road_owner":0}
    require(new_r[str(SITE)]==expected,"Expected a genuine stock two-way through bus stop and original carriageway")
    old_r[str(SITE)]=expected
    require(old_r==new_r,"Unexpected change outside the requested road stop")
    return sorted(changes),expected


def stock_random_next(s,t):
    # 14.1 Randomizer::Next, exactly one AddFacility() RNG draw.
    word=2**32-1
    def rotr(x,n): return ((x>>n)|(x<<(32-n)))&word
    return (s+rotr(t^0x1234567F,7)+1)&word,(rotr(s,3)-1)&word


def compare(old,new,expense):
    price=int(expense)
    a,b=(decode_tables(x,POOLS) for x in (old,new))
    ca,cb=a[b"PLYR"][0],b[b"PLYR"][0]
    require(ca["money"]-cb["money"]==price and ca["money_fraction"]==cb["money_fraction"]
            and cb["yearly_expenses"][0]-ca["yearly_expenses"][0]==price,
            "Native company did not pay the exact fixture construction cost")
    ca["money"]-=price
    ca["yearly_expenses"][0]+=price
    if ca["last_build_coordinate"]!=cb["last_build_coordinate"]:
        require(cb["last_build_coordinate"]==SITE,"Wrong native build site ledger")
        ca["last_build_coordinate"]=cb["last_build_coordinate"]
    wire_old,wire_new=(protected_wire(x) for x in (old,new))
    old_date,=a[b"DATE"].values()
    new_date,=b[b"DATE"].values()
    rng=("random_state[0]","random_state[1]")
    expected_rng=stock_random_next(*(old_date[k] for k in rng))
    require(tuple(new_date[k] for k in rng)==expected_rng,"Unexpected stock station creation RNG transition")
    old_date.update(dict(zip(rng,expected_rng)))
    wire_old.pop(b"DATE")
    wire_new.pop(b"DATE")
    for tag in (b"STNN",b"ROAD"):
        require(set(b[tag])-set(a[tag])=={NEW} and set(a[tag])<=set(b[tag]),
                "Unexpected addition/deletion in native station pool")
        b[tag].pop(NEW)
        wire_old.pop(tag)
        wire_new.pop(tag)
    if a!=b or wire_old!=wire_new:
        report={}
        for tag in a:
            if a[tag]!=b[tag]:
                ids=sorted(a[tag].keys()|b[tag].keys())
                report[tag.decode()]={i:sorted(k for k in a[tag].get(i,{}).keys()|b[tag].get(i,{}).keys()
                                              if a[tag].get(i,{}).get(k)!=b[tag].get(i,{}).get(k))
                                      for i in ids if a[tag].get(i)!=b[tag].get(i)}
        raise SaveError("Existing stock state changed beyond intended station allocation: "
                        +str(report)+"; raw differences: "+str([tag for tag in wire_old if wire_old[tag]!=wire_new[tag]]))
    stations=probe_bus_state(new)["stations"]
    station=stations[NEW]
    require(station["tile"]==SITE and station["owner"]==0
            and station["road_stops"]==[{"road_stop_id":NEW,"tile":SITE,"status":67,"type":"bus"}],
            "New native facility is not its own linked road-stop object")
    planes,record=compare_map(old,new)
    return {"tick":clock(b),"changed_map_planes":planes,"stock_map_record":record,
            "station_pool_id":NEW,"stop_pool_id":station["road_stops"][0]["road_stop_id"],
            "native_expense_delta":price,"stock_station_rng_draws":1,"fixed_cash_before":(ca["money"]+price)*256+ca["money_fraction"],
            "fixed_cash_after":cb["money"]*256+cb["money_fraction"],
            "protected_chunks_byte_identical":[k.decode() for k in sorted(wire_new)],
            "vehicle_chunk_sha256":digest(wire_new[b"VEHS"])}


EXERCISE = """
class SaveProbe extends AIController {
  function Require(ok, why) { if (!ok) throw why + ": " + AIError.GetLastErrorString(); }
  function Start() {
    this.SetCommandDelay(1);
    AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
    local v=5,stop=44385;
    Require(AIRoad.IsDriveThroughRoadStationTile(stop) && AIStation.GetStationID(stop)==3 &&
      AIVehicle.GetLocation(v)==44128 && AIVehicle.GetState(v)==AIVehicle.VS_IN_DEPOT &&
      AIOrder.GetOrderDestination(v,0)==44642,"Reloaded service-control buses/site differ");
    Require(AIOrder.AppendOrder(v,stop,AIOrder.OF_NON_STOP_INTERMEDIATE),"Assign new stop just for disposable exercise");
    Require(AIOrder.SkipToOrder(v,1),"Choose the new stop");
    Require(AIVehicle.StartStopVehicle(v),"Dispatch reserve in independent clone");
    AILog.Info("DRIVE_AUTHOR_EXERCISE");
    while(true) this.Sleep(1000);
  }
}
"""


def exercise(stock,built):
    restored=stock.save()
    native=decode_tables(built,POOLS)
    require(decode_tables(restored,POOLS)==native and protected_wire(restored)==protected_wire(built),
            "Separate service-control initial copy has changed")
    original=native[b"ORDL"][1]["first"]
    require(native[b"ORDR"][original-1]["dest"]==2,"Protected initial order not present")
    first=None
    live=native
    for _ in range(80):
        _,previous=actor(live,5)
        stock.step(0 if previous["tile"]==SITE else .14)
        log=stock.read()
        require("The script died unexpectedly" not in log,log)
        live=decode_tables(stock.save(),POOLS)
        _,v=actor(live,5)
        if v["tile"]==SITE:
            first=first or clock(live)
            if v["last_station_visited"]==NEW:
                first_order=live[b"ORDR"][original-1]
                second_order=live[b"ORDR"][first_order["next"]-1]
                require(first_order["dest"]==2 and second_order["dest"]==NEW and v["orders"]==2
                        and "DRIVE_AUTHOR_EXERCISE" in log,"Exercise was not a native ordered visit")
                return {"reserve_id":5,"departed_and_traversed_tile_tick":first,
                        "actual_new_station_visit_tick":clock(live),"facility_id":NEW,
                        "temporary_disposable_orders_only":True}
    raise SaveError("Native test bus never serviced the new through stop")


def run(a):
    source=read_save(a.source)
    require(a.output.suffix==".sav" and a.output.resolve()!=a.source.resolve() and not a.output.exists(),
            "Output must be a distinct exclusive private .sav")
    data,board=qualified(source)
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-drive-stop-") as name:
        root=Path(name)
        q,receipt=quote(a.luanti,root/"luanti",a.luanti_port,source,data,board)
        with StockAction(root/"build",a.openttd,a.share,a.source,a.port,COMMAND) as stock:
            built=execute(stock,source,q)
        tick=clock(decode_tables(built,{b"DATE"}))
        require(0<tick-clock(data)<=24,"Stock build stepped past the active save gate")
        with Native(root/"control",a.openttd,a.share,a.source,a.port) as stock:
            old=matched_control(stock,source,tick)
        difference=compare(old,built,q["cost"])
        candidate=root/"candidate.sav"
        candidate.write_bytes(built)
        with Native(root/"restore",a.openttd,a.share,candidate,a.port) as stock:
            first_trip=prove_reopen(stock,built)
        with StockAction(root/"exercise",a.openttd,a.share,candidate,a.port,EXERCISE) as stock:
            visit=exercise(stock,built)
        require(read_save(a.source)==source and built!=source,"Protected original changed or no actual new save")
        with a.output.open("xb") as f:
            f.write(built)
    return {"schema":"luanttd-stock-drive-stop-proof/1","general_export":False,
            "source_sha256":digest(source),"source_unchanged":True,
            "created_stock_sha256":digest(built),"native_constructed_saved_reloaded":True,
            "quote_sha256":receipt,"luanti_stock_quote":q,"same_tick_control":difference,
            "unchanged_first_trip":first_trip,"separate_native_service_test":visit}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for field in ("openttd","share","luanti","source","output"):
        p.add_argument("--"+field,type=lambda n:Path(n).resolve(),required=True)
    p.add_argument("--port",type=int,default=39875)
    p.add_argument("--luanti-port",type=int,default=39876)
    args=p.parse_args()
    print(json.dumps(run(args),sort_keys=True))
