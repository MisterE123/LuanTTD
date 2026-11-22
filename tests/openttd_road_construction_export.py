#!/usr/bin/env python3
"""Stock 14.1 one-tile road construction through its actual command/save path."""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
from copy import deepcopy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from openttd_sparse import STOCK
from openttd_road_junction_fixture import ORIGIN, BAY
from openttd_dual_active_export import read_save
from openttd_export_order_experiment import Native, SaveError, decode_tables, digest, require
from openttd_bus_checkpoint_resume import forecast
from openttd_save_map import decode_map, snapshot
from openttd_save_bus_state import probe_bus_state

SPUR, GAP, STOP = (ORIGIN+256+i for i in range(3))
POOLS={b"DATE",b"VEHS",b"ORDL",b"ORDR",b"STNN",b"ROAD",b"DEPT",b"CAPA",b"CAPY",b"PLYR",b"PATS",b"ECMY",b"NGRF"}
HOME=Path(__file__).resolve().parent


def preparation(ai):
    app=ai/"main.nut"
    code=app.read_text()
    mark="        local owner=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);"
    assert code.count(mark)==1
    code=code.replace(mark,'''
        local spur=a+w, gap=spur+1, unreachable=gap+1;
        Require(AIRoad.BuildRoadFull(spur,gap),"Stage both halves of the existing junction");
        Require(AITile.DemolishTile(gap),"Leave exact unbuilt gap after staging stub");
        Require(AIRoad.BuildRoadStation(unreachable,gap,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build independent bay with no possible road connection");
        Require(!AIRoad.IsRoadTile(gap) && !AIRoad.AreRoadTilesConnected(gap,unreachable),
                "Proof bay must be initially unreachable");
'''+mark)
    dispatch='        Require(AIVehicle.StartStopVehicle(v),"Dispatch stock bus");'
    assert code.count(dispatch)==1
    app.write_text(code.replace(dispatch,'''
        local reserve=AIVehicle.BuildVehicle(d,engine);
        Require(AIVehicle.IsValidVehicle(reserve) && reserve!=v,"Build protected depot bus");
        Require(AIOrder.AppendOrder(reserve,unreachable,AIOrder.OF_NON_STOP_INTERMEDIATE),
                "Store a native order before adding the missing link");
        Require(AIVehicle.GetState(reserve)==AIVehicle.VS_IN_DEPOT,"Do not dispatch before link");
'''+dispatch))


def generate(binary,share,output,port):
    require(output.suffix==".sav" and not output.exists(),"Fixture output must be an exclusive new .sav")
    with tempfile.TemporaryDirectory(prefix="luanttd-road-author-source-") as d:
        stock,points=STOCK.oracle(binary,share,Path(d),port,private_fixture=preparation)
        blob=stock.read_bytes()
        STOCK.compare(STOCK.snapshot(blob),points)
        initial,tiles=source_gate(blob)
        with output.open("xb") as f:
            f.write(blob)
    return {"source_sha256":digest(blob),"tick":clock(initial),"land":tiles,"private_only":True}


def clock(data):
    return next(iter(data[b"DATE"].values()))["tick_counter"]


def lanes(blob):
    _,_,w,h,planes,_=decode_map(blob)
    require((w,h)==(256,256),"Wrong source width/height")
    roads=snapshot(blob)["road_tiles"]
    out=[]
    for t in (SPUR,GAP,STOP):
        p=[planes[b"MAPH"][t+i] for i in (0,1,256,257)]
        require(len(set(p))==1 and p[0]==1,"Gate requires all three tiles level at native height 1")
        if t==GAP:
            require(planes[b"MAPT"][t]>>4==0 and planes[b"MAPO"][t]&31==16
                    and planes[b"MAP5"][t]&28==0 and not (planes[b"M3LO"][t]&16),
                    "Target must be unowned clear, non-snow grass (not industry/house/field/rail)")
            out.append({"kind":"clear","slope":0,"density":planes[b"MAP5"][t]&3})
        else:
            r=roads.get(str(t),{})
            require(r.get("road_type")==0 and r.get("road_owner")==0
                    and r.get("unsupported_for_initial_bus_world")==[],
                    "An endpoint is not an ordinary eligible owner-0 stock road")
            if t==SPUR:
                require(r["kind"]=="road" and r["road_bits"]==15 and r["disallowed"]==0
                        and planes[b"MAPE"][t]>>4==0,"Start must be the established ordinary unblocked 4-bit junction")
            else:
                require(r["kind"]=="bay_stop" and r["road_bits"]==8 and r["station_id"]==2
                        and r["station_owner"]==0,"End must be the distinct isolated west-facing stock bus bay")
            out.append({"kind":r["kind"],"slope":0,"roadtype":0,"road_bits":r["road_bits"],"owner":0})
    return out


def actor(data,i):
    road,=data[b"VEHS"][i]["roadveh"]
    v,=road["common"]
    return road,v


def source_gate(blob):
    data=decode_tables(blob,POOLS)
    world=probe_bus_state(blob)
    tiles=lanes(blob)
    s=next(iter(data[b"PATS"].values()))
    econ=next(iter(data[b"ECMY"].values()))
    require(not data[b"NGRF"] and s["economy.inflation"]==0 and s["game_creation.landscape"]==0
            and s["difficulty.construction_cost"] in (0,1,2) and econ["inflation_prices"]==65536,
            "Construction quote only supports stock uninflated temperate pricing")
    require(world["game_clock"]["pause_mode"]==1 and set(world["company_balances"])=={0}
            and set(world["road_vehicles"])=={4,5} and len(data[b"STNN"])==3 and data[b"CAPY"]=={},
            "Expected exactly the sealed loaded bus and the protected station-ordered reserve")
    a,b=(world["road_vehicles"][i] for i in (4,5))
    require(a["engine_type"]==b["engine_type"]==116 and a["cargo_type"]==b["cargo_type"]==0
            and a["owner"]==b["owner"]==0 and a["dest_tile"]==BAY and a["cur_speed"]>0
            and a["onboard"]>0 and b["onboard"]==0 and b["motion"]["state"]==254
            and b["tile"]==ORIGIN-256 and b["order_list_id"]!=a["order_list_id"]
            and [o["dest"] for o in b["orders"]]==[2],
            "Closed fixture actor or existing order identity changed")
    return data,tiles


def quote(luanti,root,port,blob,data,tiles):
    game=root/"games"/"road_author"
    mod=game/"mods"/"road_author"
    mod.mkdir(parents=True)
    (game/"game.conf").write_text("title = Private stock road construction quote\n")
    (mod/"mod.conf").write_text("name = road_author\n")
    shutil.copyfile(HOME/"openttd_road_construction_native.lua",mod/"init.lua")
    kernels=HOME.parent/"mods"/"bayline"/"openttd"
    for source in ("road_slope","road_oneway","yapf_road_follow","road_bridge"):
        shutil.copyfile(kernels/(source+".lua"),mod/(source+".lua"))
    setting=next(iter(data[b"PATS"].values()))
    spec={"schema":"luanttd-stock-road-construction-input/1","source_sha256":digest(blob),
          "original_tick":clock(data),"start":SPUR,"goal":GAP,"stop":STOP,"owner":0,"axis":0,
          "inflation":65536,"width":256,"mask":10,"construction_difficulty":setting["difficulty.construction_cost"],
          "tiles":tiles}
    (mod/"input.json").write_text(json.dumps(spec))
    config=root/"game.conf"
    config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n"
                      f"prometheus_listener_address = 127.0.0.1:{port}\n")
    env={**os.environ,"HOME":str(root),"MINETEST_GAME_PATH":str(root/"games"),"LUANTI_GAME_PATH":str(root/"games")}
    proc=subprocess.run([luanti,"--gameid","road_author","--world",root/"world","--config",config,"--logfile",""],
                        env=env,capture_output=True,text=True,timeout=18)
    log=proc.stdout+proc.stderr
    m=re.search(r"LuanTTD stock road construction quote (.*)",log)
    require(proc.returncode==0 and m,log)
    receipt=json.loads(m[1])
    body=receipt["body"]
    out=json.loads(body)
    require(digest(body.encode())==receipt["sha256"] and out.get("schema")=="luanttd-stock-road-construction-quote/1"
            and all(out[k]==spec[k] for k in ("source_sha256","original_tick","start","goal","stop","owner","mask"))
            and out["cost"]==2*out["piece_cost"]+out["clear_cost"]>0 and out["rejected_lab_inputs"]==7,
            "Quote is not bound to the exact two-half-bit stock action")
    return out,receipt["sha256"]


class StockAction(Native):
    def __init__(self,root,binary,share,save,port,script):
        super().__init__(root,binary,share,save,port)
        (root/".openttd"/"ai"/"SaveProbe"/"main.nut").write_text(script)
        self.args.extend(("-d","script=5"))


BUILD = """
class SaveProbe extends AIController {
  function Require(ok, why) { if (!ok) throw why + ": " + AIError.GetLastErrorString(); }
  function Start() {
    this.SetCommandDelay(1);
    AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
    Require(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)==0,"Wrong company");
    local start=44640, gap=44641, bay=44642;
    Require(AIRoad.IsRoadTile(start) && !AIRoad.IsRoadTile(gap) && AIRoad.IsRoadStationTile(bay)
      && AIStation.GetStationID(bay)==2 && AITile.GetOwner(start)==0 && AITile.GetOwner(bay)==0
      && AITile.GetSlope(start)==0 && AITile.GetSlope(gap)==0 && AITile.GetSlope(bay)==0
      && AITile.IsBuildable(gap) && !AIRoad.AreRoadTilesConnected(gap,bay),
      "Disallowed road command site");
    local estimate=0;
    {
      local tally=AIAccounting();
      local test=AITestMode();
      Require(AIRoad.BuildRoadFull(start,gap),"Stock construction test-mode rejection");
      estimate=tally.GetCosts();
      Require(!AIRoad.IsRoadTile(gap),"Cost query must not build");
    }
    local tally=AIAccounting();
    Require(AIRoad.BuildRoadFull(start,gap),"Stock construction execution rejection");
    Require(AIRoad.AreRoadTilesConnected(start,gap) && AIRoad.AreRoadTilesConnected(gap,bay)
      && AITile.GetOwner(gap)==0,"Native construction did not connect both edges");
    AILog.Info("ROAD_AUTHOR_DONE "+estimate+" "+tally.GetCosts());
    while(true) this.Sleep(1000);
  }
}
"""


def construction_batch(stock,amount,source):
    opened=stock.save()
    require(decode_tables(opened,POOLS)==decode_tables(source,POOLS) and lanes(opened)==lanes(source),
            "Native command did not start from the sealed paused source")
    for _ in range(9):
        stock.step(0)
        log=stock.read()
        require("The script died unexpectedly" not in log,log)
        found=re.search(r"ROAD_AUTHOR_DONE ([0-9]+) ([0-9]+)",log)
        if found:
            require([int(x) for x in found.groups()]==[amount,amount],
                    "Luanti quote, native test quote and native charged command disagree")
            return stock.save()
    raise SaveError("Stock did not execute and report the quoted command within the bounded active window")


def matched_control(stock,source,target):
    saved=stock.save()
    require(decode_tables(saved,POOLS)==decode_tables(source,POOLS),"Untouched stock control mismatched source")
    for _ in range(20):
        now=clock(decode_tables(saved,{b"DATE"}))
        if now==target:
            return saved
        require(now<target,"Untouched stock missed the exact executed tick")
        stock.step(0)
        saved=stock.save()
    raise SaveError("Could not obtain exact-time untouched control")


def compare_maps(old,new):
    _,_,_,_,p,_=decode_map(old)
    _,_,_,_,q,_=decode_map(new)
    changes=set()
    for k,raw in p.items():
        unit=2 if k in (b"MAP2",b"MAP8") else 1
        require(len(raw)==len(q[k]),"Stock changed map dimensions")
        diffs={i//unit for i,(x,y) in enumerate(zip(raw,q[k])) if x!=y}
        require(diffs<={GAP} and (k!=b"MAPH" or not diffs),
                "Native construction changed terrain or an unrelated map tile")
        if diffs:
            changes.add(k.decode())
    require("MAPT" in changes and "MAP5" in changes,"No actual native road map edit")
    rb=deepcopy(snapshot(old)["road_tiles"])
    ra=snapshot(new)["road_tiles"]
    require(str(GAP) not in rb and str(GAP) in ra,"Native only tested construction without doing it")
    built=ra[str(GAP)]
    require(built["kind"]=="road" and built["road_bits"]==10 and built["road_owner"]==0
            and built["road_type"]==0 and built["disallowed"]==0 and built["unsupported_for_initial_bus_world"]==[],
            "Unexpected native road bits, type or ownership")
    rb[str(GAP)]=built
    require(ra==rb,"Unexpected stock road record changes")
    return sorted(changes)


def compared_native(old,new,amount):
    before,after=(decode_tables(x,POOLS) for x in (old,new))
    a,b=before[b"PLYR"][0],after[b"PLYR"][0]
    require(b["money"]==a["money"]-amount and b["money_fraction"]==a["money_fraction"]
            and b["yearly_expenses"][0]-a["yearly_expenses"][0]==amount,
            "Construction expense did not debit exactly the planned road purchase")
    a["money"]-=amount
    a["yearly_expenses"][0]+=amount
    if b["last_build_coordinate"]!=a["last_build_coordinate"]:
        require(b["last_build_coordinate"] in (SPUR,GAP),"Wrong native company construction focus tile")
        a["last_build_coordinate"]=b["last_build_coordinate"]
    require(before==after,"Native command affected an unrelated actor, ledger, timer or facility")
    planes=compare_maps(old,new)
    return {"tick":clock(after),"changed_map_planes":planes,"cash_fixed_before":b["money"]*256+b["money_fraction"]+amount*256,
            "cash_fixed_after":b["money"]*256+b["money_fraction"],"construction_expense_increase":amount,
            "protected_stock_pools":[x.decode() for x in sorted(POOLS-{b"PLYR"})]}


DISPATCH = """
class SaveProbe extends AIController {
  function Start() {
    this.SetCommandDelay(1);
    AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
    if (!AIRoad.IsRoadTile(44641) || !AIRoad.AreRoadTilesConnected(44640,44641)
     || !AIRoad.AreRoadTilesConnected(44641,44642) || !AIVehicle.IsValidVehicle(5)
     || AIVehicle.GetState(5)!=AIVehicle.VS_IN_DEPOT || AIVehicle.GetLocation(5)!=44128
     || AIOrder.GetOrderDestination(5,0)!=44642)
        throw "Wrong immutable authored connection and protected reserve";
    if (!AIVehicle.StartStopVehicle(5)) throw "Could not dispatch the checked reserve to its existing order";
    AILog.Info("ROAD_AUTHOR_DISPATCH");
    while(true) this.Sleep(1000);
  }
}
"""


def observe(stock,expected):
    initial=stock.save()
    original=decode_tables(expected,POOLS)
    require(decode_tables(initial,POOLS)==original and snapshot(initial)["road_tiles"]==snapshot(expected)["road_tiles"],
            "Stock reopen did not preserve the already built road or paused state")
    start=clock(original)
    _,lead=actor(original,4)
    want=forecast({p-1:original[b"CAPA"][p-1] for p in lead["cargo.packets"]},BAY,256)
    users=sum(original[b"CAPA"][p-1]["count"] for p in lead["cargo.packets"])
    require(users==5 and want==9,"Original active ledger is not the staged first trip")
    entered,visited,visit_type,credit,staged,departure=None,None,None,None,None,None
    live=original
    for _ in range(150):
        _,r=actor(live,5)
        pulse=.045 if r["tile"]==STOP and not visited else .14
        stock.step(pulse)
        require("The script died unexpectedly" not in stock.read(),stock.read())
        live=decode_tables(stock.save(),POOLS)
        tick=clock(live)
        road,reserve=actor(live,5)
        econ=live[b"PLYR"][0]["cur_economy"][0]
        if reserve["tile"]==GAP and reserve["cur_speed"]>0:
            require(reserve["current_order.dest"]==2 and reserve["dest_tile"]==STOP,
                    "Reserve did not traverse on its verified original route")
            entered=entered or tick
        if entered and reserve["tile"]==STOP and reserve["last_station_visited"]==2:
            # The empty single-order bus can clear a brief transient order
            # immediately. The stock station visit marker is authoritative.
            require(reserve["orders"]==2 and live[b"ORDR"][2]["dest"]==2,
                    "Reserve lost its unchanged stored route after arrival")
            if not visited:
                visited,visit_type=tick,reserve["current_order.type"]&15
        if road["state"]!=254 and reserve["tile"] != ORIGIN-256:
            departure=departure or tick
            if not visited:
                require(reserve["orders"]==2 and reserve["current_order.dest"]==2,
                        "Dispatched protected bus did not use its preserved station order")
        delivered=econ["delivered_cargo"][0]
        income=econ["income"]
        if os.getenv("LUANTTD_ROAD_AUTHOR_TRACE"):
            print(tick,[reserve[k] for k in ("tile","cur_speed","current_order.type","current_order.dest","last_station_visited")],
                  delivered,income,entered,visited,staged,file=sys.stderr)
        require(delivered in (0,users) and income in (0,want),"Protected first delivery or fare repeated")
        if delivered==users and not income and any(p["front"]==5 and p["route_profit"]==want for p in live[b"CAPY"].values()):
            staged=staged or tick
        if income==want:
            require(delivered==users,"Income appeared before original riders were delivered")
            credit=credit or tick
        if visited and credit:
            break
    require(departure and entered and visited and staged and credit and "ROAD_AUTHOR_DISPATCH" in stock.read()
            and start<departure<=entered<visited and start<staged<credit,
            "Native stock did not show the actual new route and independent first fare")
    return {"reserve_departure_tick":departure,"reserve_on_new_tile_tick":entered,
            "reserve_serviced_newly_connected_station_tick":visited,"reserve_stock_order_kind_after_visit":visit_type,
            "original_passengers_delivered":users,
            "original_fare":want,"original_fare_staged_tick":staged,"original_fare_booked_tick":credit}


def run(args):
    source=read_save(args.source)
    require(args.output.suffix==".sav" and args.output.resolve()!=args.source.resolve() and not args.output.exists(),
            "Output must be a distinct new private .sav")
    data,tiles=source_gate(source)
    with tempfile.TemporaryDirectory(prefix="luanttd-road-author-lab-") as d:
        root=Path(d)
        plan,intent=quote(args.luanti,root/"luanti",args.luanti_port,source,data,tiles)
        with StockAction(root/"build",args.openttd,args.share,args.source,args.port,BUILD) as stock:
            built=construction_batch(stock,plan["cost"],source)
        after=decode_tables(built,POOLS)
        completed=clock(after)
        require(0<completed-clock(data)<=18 and not after[b"CAPY"],"Expense is outside active pre-delivery window")
        with Native(root/"control",args.openttd,args.share,args.source,args.port) as control:
            plain=matched_control(control,source,completed)
        accounting=compared_native(plain,built,plan["cost"])
        # Reopen the file written by the native builder. This next stock
        # process independently rechecks the lane, full ledger and visit.
        private=root/"built.sav"
        private.write_bytes(built)
        with StockAction(root/"prove",args.openttd,args.share,private,args.port,DISPATCH) as stock:
            visit=observe(stock,built)
        require(read_save(args.source)==source and built!=source,"Protected source input changed")
        with args.output.open("xb") as f:
            f.write(built)
    return {"schema":"luanttd-stock-road-construction-proof/1","scope":"one ordinary flat stock road tile",
            "general_export":False,"source_sha256":digest(source),"source_unchanged":True,
            "native_output_sha256":digest(built),"native_test_and_charged_cost_match_luanti_quote":True,
            "native_constructed_reloaded":True,"built_tile_only":GAP,"target_road_bits":10,
            "target_operator_company":0,"native_station_and_depot_orders_unchanged":True,
            "luanti_quote_sha256":intent,"price":plan,"same_tick_control":accounting,"native_followup":visit}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for n in ("openttd","share","source"):
        p.add_argument("--"+n,type=Path,required=True)
    p.add_argument("--port",type=int,default=39865)
    p.add_argument("--generate",action="store_true")
    p.add_argument("--output",type=Path)
    p.add_argument("--luanti",type=Path)
    p.add_argument("--luanti-port",type=int,default=39866)
    a=p.parse_args()
    for n in ("openttd","share","source","output","luanti"):
        if getattr(a,n) is not None:
            setattr(a,n,getattr(a,n).resolve())
    if a.generate:
        print(json.dumps(generate(a.openttd,a.share,a.source,a.port),sort_keys=True))
    else:
        if not a.output or not a.luanti:
            p.error("road construction requires --luanti and exclusive --output")
        print(json.dumps(run(a),sort_keys=True))
