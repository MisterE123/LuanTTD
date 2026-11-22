#!/usr/bin/env python3
"""Stock-assisted one shared-corner Raise, with exact active stock preservation."""
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from openttd_road_construction_export import (HOME, POOLS, StockAction, actor, clock,
                                              decode_map, matched_control, snapshot, source_gate)
from openttd_dual_active_export import read_save
from openttd_export_order_experiment import (Native, Reader, SaveError, chunks, decode_tables,
                                             digest, require, unpack_payload)
from openttd_bus_checkpoint_resume import forecast
from openttd_road_junction_fixture import BAY

CORNER=45159
SLOPES={44902:2,44903:4,45158:1,CORNER:8}


def terrain_source(blob):
    data,_=source_gate(blob)
    _,_,w,h,planes,_=decode_map(blob)
    require((w,h)==(256,256),"Unsupported stock dimensions")
    local=[]
    for t,mask in SLOPES.items():
        corners=[planes[b"MAPH"][t+i] for i in (0,1,256,257)]
        require(corners==[1]*4 and planes[b"MAPT"][t]==0 and planes[b"MAPO"][t]==16
                and planes[b"MAP5"][t]&31==3 and planes[b"M3LO"][t]==0 and planes[b"MAPE"][t]==0
                and planes[b"MAP7"][t]==0 and planes[b"MAP8"][2*t:2*t+2]==bytes(2),
                "Incident tile is not qualified level unowned temperate grass; no edit")
        local.append({"tile":t,"owner":16,"density":3,"kind":"grass","base":1,"slope":mask})
    return data,local


def quote(luanti,root,port,source,data,tiles):
    game=root/"games"/"terraform_lab"
    mod=game/"mods"/"terraform_lab"
    mod.mkdir(parents=True)
    (game/"game.conf").write_text("title = Stock shared-corner Raise quote\n")
    (mod/"mod.conf").write_text("name = terraform_lab\n")
    shutil.copyfile(HOME/"openttd_terraform_native.lua",mod/"init.lua")
    repo=HOME.parent/"mods"/"bayline"
    for name in ("openttd/terrain.lua","openttd/slope.lua","openttd/landscaping.lua","import/openttd_map.lua"):
        shutil.copyfile(repo/name,mod/Path(name).name)
    settings=next(iter(data[b"PATS"].values()))
    company=data[b"PLYR"][0]
    spec={"schema":"luanttd-stock-terraform-quote-input/1","source_sha256":digest(source),
          "original_tick":clock(data),"tile":CORNER,"direction":"raise","mask":8,
          "company":0,"max_height":settings["construction.map_height_limit"],
          "construction_difficulty":settings["difficulty.construction_cost"],"inflation":65536,
          "terraform_quota":company["terraform_limit"],"cash":company["money"],
          "incident":tiles,"snapshot":snapshot(source)}
    (mod/"input.json").write_text(json.dumps(spec))
    config=root/"game.conf"
    config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\n"
                      f"prometheus_listener_address = 127.0.0.1:{port}\n")
    env={**os.environ,"HOME":str(root),"MINETEST_GAME_PATH":str(root/"games"),"LUANTI_GAME_PATH":str(root/"games")}
    proc=subprocess.run([luanti,"--gameid","terraform_lab","--world",root/"world","--config",config,"--logfile",""],
                        env=env,capture_output=True,text=True,timeout=22)
    log=proc.stdout+proc.stderr
    match=re.search(r"LuanTTD stock terraform quote (.*)",log)
    require(proc.returncode==0 and match,log)
    receipt=json.loads(match[1])
    body=receipt["body"]
    plan=json.loads(body)
    require(digest(body.encode())==receipt["sha256"] and plan["schema"]=="luanttd-stock-terraform-quote/1"
            and all(plan[k]==spec[k] for k in ("source_sha256","original_tick","tile","mask","company"))
            and {m["tile"]:m["mask"] for m in plan["new_slopes"]}==SLOPES
            and plan["old_height"]==1 and plan["height"]==2 and plan["rejected_lab_inputs"]==9,
            "Native Luanti quote does not match the sealed authorized shared corner")
    return plan,receipt["sha256"]


RAISE = """
class SaveProbe extends AIController {
  function Require(ok, why) { if (!ok) throw why + ": " + AIError.GetLastErrorString(); }
  function Start() {
    this.SetCommandDelay(1);
    local tile=45159;
    local inc=[44902,44903,45158,45159];
    local masks=[AITile.SLOPE_S,AITile.SLOPE_E,AITile.SLOPE_W,AITile.SLOPE_N];
    Require(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)==0,"wrong company");
    foreach(t in inc)
      Require(AITile.IsBuildable(t) && AITile.GetSlope(t)==AITile.SLOPE_FLAT
        && AITile.GetMinHeight(t)==1,"wrong flat footprint");
    local quote=0;
    {
      local teller=AIAccounting();
      local trial=AITestMode();
      Require(AITile.RaiseTile(tile,AITile.SLOPE_N),"Stock quote refused selected corner");
      quote=teller.GetCosts();
      Require(AITile.GetCornerHeight(tile,AITile.CORNER_N)==1,"Query mutated map");
    }
    local teller=AIAccounting();
    Require(AITile.RaiseTile(tile,AITile.SLOPE_N),"Stock rejected actual Raise");
    Require(AITile.GetCornerHeight(tile,AITile.CORNER_N)==2,"Stock did not raise the shared corner");
    foreach(i,t in inc) {
      Require(AITile.GetSlope(t)==masks[i] && AITile.GetMinHeight(t)==1,"Stock produced a different neighbor slope");
      AILog.Info("LAND_AUTHOR_SLOPE "+t+" "+AITile.GetSlope(t));
    }
    AILog.Info("LAND_AUTHOR_DONE "+quote+" "+teller.GetCosts());
    while(true) this.Sleep(1000);
  }
}
"""


def execute(stock,source,plan):
    control=stock.save()
    require(terrain_source(control)==terrain_source(source),"Stock Raise started from an unsealed checkpoint")
    for _ in range(12):
        stock.step(0)
        log=stock.read()
        require("The script died unexpectedly" not in log,log)
        match=re.search(r"LAND_AUTHOR_DONE (\d+) (\d+)",log)
        if match:
            require([int(x) for x in match.groups()]==[plan["cost"]]*2
                    and {int(i):int(mask) for i,mask in re.findall(r"LAND_AUTHOR_SLOPE (\d+) (\d+)",log)}==SLOPES,
                    "Native cost or independently observed stock slope differs from Luanti")
            return stock.save()
    raise SaveError("Stock did not run the one permitted Raise command")


def slope_at(planes,t):
    ns=[planes[b"MAPH"][t+i] for i in (0,1,256,257)]
    lo,hi=min(ns),max(ns)
    return sum(bit for bit,h in zip((8,1,4,2),ns) if h!=lo)+(16 if hi>lo+1 else 0),lo,hi


def map_comparison(original,edited):
    _,_,_,_,before,_=decode_map(original)
    _,_,_,_,after,_=decode_map(edited)
    changes={}
    for k,b in before.items():
        stride=2 if k in (b"MAP2",b"MAP8") else 1
        require(len(b)==len(after[k]),"Stock changed map dimensions")
        diff={i//stride for i,(x,y) in enumerate(zip(b,after[k])) if x!=y}
        require(diff<={CORNER} if k==b"MAPH" else diff<=SLOPES.keys(),
                "Stock terrain or ancillary map planes changed outside the four incident tiles")
        if diff: changes[k.decode()]=sorted(diff)
    require(changes.get("MAPH")==[CORNER] and changes.get("MAP5")==list(SLOPES)
            and before[b"MAPH"][CORNER]==1 and after[b"MAPH"][CORNER]==2
            and all(after[b"MAP5"][i]&31==0 for i in SLOPES),
            "Stock did not raise one shared vertex and clear the four affected grass surfaces")
    require(all(slope_at(after,i)==(mask,1,2) for i,mask in SLOPES.items())
            and snapshot(original)["road_tiles"]==snapshot(edited)["road_tiles"],
            "Native edited plane does not reproduce all four slopes and unchanged transport geometry")
    return changes


def protected_wire(blob):
    """Whole decompressed encoded stock chunks, not only decoded values."""
    _,_,body=unpack_payload(blob)
    tuple(chunks(body))
    r=Reader(body)
    wanted=POOLS-{b"PLYR"}
    out={}
    while True:
        start=r.at
        tag=bytes(r.take(4))
        if tag==bytes(4):
            break
        mode=r.byte()
        if mode&15==0:
            r.take(((mode>>4)<<24)|int.from_bytes(r.take(3),"big"))
        else:
            if mode in (3,4): r.record()
            while r.record() is not None: pass
        if tag in wanted:
            out[tag]=bytes(body[start:r.at])
    require(out.keys()==wanted,"Missing expected protected serialized native chunk")
    return out


def compare(original,edited,plan):
    old,new=(decode_tables(b,POOLS) for b in (original,edited))
    a,b=old[b"PLYR"][0],new[b"PLYR"][0]
    amount=plan["cost"]
    require(b["money"]==a["money"]-amount and b["money_fraction"]==a["money_fraction"]
            and b["yearly_expenses"][0]-a["yearly_expenses"][0]==amount,
            "Stock finance does not agree with the exact Raise quote")
    a["money"]-=amount
    a["yearly_expenses"][0]+=amount
    if b["last_build_coordinate"]!=a["last_build_coordinate"]:
        require(b["last_build_coordinate"]==CORNER,"Stock edited a different company focus tile")
        a["last_build_coordinate"]=b["last_build_coordinate"]
    # Native update caps the rapidly replenished allowance, so the saved
    # value may already equal control. The clear allowance never decreases
    # here: the command's automatic clears run with DC_AUTO.
    settings=next(iter(new[b"PATS"].values()))
    debit=a["terraform_limit"]-b["terraform_limit"]
    require(debit in (0,65536) and settings["construction.terraform_per_64k_frames"]>=65536,
            "Unexpected native terraform allowance ledger")
    a["terraform_limit"]=b["terraform_limit"]
    require(old==new,"Native Raise affected protected actor, order or financial records")
    wire=protected_wire(edited)
    require(protected_wire(original)==wire,"Protected encoded stock chunks are not byte-identical")
    return {"tick":clock(new),"changed_map_planes":map_comparison(original,edited),
            "cash_fixed_before":(b["money"]+amount)*256+b["money_fraction"],
            "cash_fixed_after":b["money"]*256+b["money_fraction"],
            "construction_expense_increase":amount,"terraform_quota_net_debit_at_pause":debit,
            "active_and_parked_vehicle_pool_identical":True,"protected_wire_chunks_byte_identical":True,
            "vehicle_chunk_sha256":digest(wire[b"VEHS"]),
            "protected_pools":[k.decode() for k in sorted(POOLS-{b"PLYR"})]}


def prove_reopen(stock,changed):
    opened=stock.save()
    initial=decode_tables(changed,POOLS)
    require(decode_tables(opened,POOLS)==initial and decode_map(opened)[4]==decode_map(changed)[4]
            and protected_wire(opened)==protected_wire(changed),
            "Stock writer/reopen did not preserve edited terrain and paused transport")
    _,lead=actor(initial,4)
    packets={p-1:initial[b"CAPA"][p-1] for p in lead["cargo.packets"]}
    wanted=forecast(packets,BAY,256)
    count=sum(p["count"] for p in packets.values())
    require(wanted==9 and count==5,"Unsupported original loaded state")
    stage,credit,events,prior=None,None,0,0
    for _ in range(80):
        stock.step(.14)
        now=decode_tables(stock.save(),POOLS)
        _,r=actor(now,5)
        require(actor(now,5)[0]["state"]==254 and r["tile"]==44128 and r["orders"]==2,
                "Independent parked reserve unexpectedly changed")
        firm=now[b"PLYR"][0]["cur_economy"][0]
        fare,units=firm["income"],firm["delivered_cargo"][0]
        t=clock(now)
        require(units in (0,count) and fare in (0,wanted) and fare>=prior,
                "Original riders or fare were lost/duplicated")
        if units==count and fare==0 and any(p["front"]==5 and p["route_profit"]==wanted for p in now[b"CAPY"].values()):
            stage=stage or t
        if fare>prior:
            credit=t
            events+=1
        if credit and t>=credit+18:
            require(stage and stage<credit and events==1 and units==count and fare==wanted and not now[b"CAPY"],
                    "The original trip did not settle exactly once")
            return {"staged_observed_tick":stage,"paid_observed_tick":credit,"post_settlement_tick":t,
                    "paid":fare,"delivered":units,"credit_events":events}
        prior=fare
    raise SaveError("Native reopened world did not finish the unchanged first trip")


def run(a):
    source=read_save(a.source)
    require(a.output.suffix==".sav" and a.output.resolve()!=a.source.resolve() and not a.output.exists(),
            "Output must be a distinct exclusive private .sav")
    data,affected=terrain_source(source)
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-terraform-") as name:
        root=Path(name)
        plan,sha=quote(a.luanti,root/"luanti",a.luanti_port,source,data,affected)
        with StockAction(root/"raise",a.openttd,a.share,a.source,a.port,RAISE) as stock:
            changed=execute(stock,source,plan)
        tick=clock(decode_tables(changed,{b"DATE"}))
        require(0<tick-clock(data)<=24,"Terraform handoff outside the original active gate")
        with Native(root/"control",a.openttd,a.share,a.source,a.port) as stock:
            control=matched_control(stock,source,tick)
        difference=compare(control,changed,plan)
        private=root/"candidate.sav"
        private.write_bytes(changed)
        with Native(root/"reopen",a.openttd,a.share,private,a.port) as stock:
            continuation=prove_reopen(stock,changed)
        require(read_save(a.source)==source and changed!=source,"Source save unexpectedly changed or output not authored")
        with a.output.open("xb") as f:
            f.write(changed)
    return {"schema":"luanttd-stock-terraform-proof/1","source_sha256":digest(source),"source_unchanged":True,
            "native_output_sha256":digest(changed),"native_stock_query_and_command_cost_match":True,
            "native_saved_and_reopened":True,"general_export":False,"luanti_quote_sha256":sha,"quote":plan,
            "same_tick_control":difference,"unrelated_stock_trip":continuation}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for n in ("openttd","share","luanti","source","output"):
        p.add_argument("--"+n,type=lambda s:Path(s).resolve(),required=True)
    p.add_argument("--port",type=int,default=39871)
    p.add_argument("--luanti-port",type=int,default=39872)
    args=p.parse_args()
    print(json.dumps(run(args),sort_keys=True))
