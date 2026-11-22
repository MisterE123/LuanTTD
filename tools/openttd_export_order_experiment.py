#!/usr/bin/env python3
"""Stock-assisted, single-next-order export experiment for the played bus fixture."""
# SPDX-License-Identifier: GPL-2.0-only
# Order field/mask pinned to OpenTTD 14.1: order_base.h SetLoadType,
# order_type.h OLFB_NO_LOAD, order_cmd.cpp MOF_LOAD and saveload/order_sl.cpp.
from hashlib import sha256
from pathlib import Path
import argparse
import json
import lzma
import os
import re
import subprocess
import tempfile
import time
import zlib

from openttd_save_inspect import LIMIT, Reader, SaveError, chunks, unpack_payload
from openttd_save_tables import decode_tables, read_schema, reference
from openttd_save_bus_resume import resume_input
from openttd_save_reserve_bus import fingerprint, parked, raw_records, stock_json

FILES = {b"DATE",b"PLYR",b"VEHS",b"CAPA",b"CAPY",b"ORDR",b"ORDL"}
ORDER_SCHEMA = [
    ("type",2),("flags",2),("dest",4),("next",6),("refit_cargo",2),
    ("wait_time",4),("travel_time",4),("max_speed",4),
]
# OLFB_NO_LOAD=4 in the 3-bit loading field at bits 4..6.
NO_LOAD = 4 << 4
NO_LOAD_ACTION = "no_loading_on_next_stop"
THIRD_ACTION = "reroute_next_to_existing_third_stop"
RESERVE_ACTION = "reroute_next_with_parked_reserve"


def flags_for(d,edited):
    return NO_LOAD if edited and d["action"]==NO_LOAD_ACTION else 0


def destination_for(d,edited):
    return d["third"]["station"] if edited and d["action"] in (THIRD_ACTION,RESERVE_ACTION) else d["upcoming"]["station"]


def digest(data):
    return sha256(data).hexdigest()


def require(test,reason):
    if not test:
        raise SaveError(reason)


def checked_receipt(original,d):
    require(isinstance(d,dict) and d.get("schema")=="luanttd-stock-order-intent/1" and
            d.get("action") in (NO_LOAD_ACTION,THIRD_ACTION,RESERVE_ACTION) and d.get("source_sha256")==digest(original),
            "Receipt action/version/source does not match the private example")
    change_destination=d["action"] in (THIRD_ACTION,RESERVE_ACTION)
    with_reserve=d["action"]==RESERVE_ACTION
    require("_reserve_binding" not in d,"Unexpected private stock binding in receipt")
    r=resume_input(original,change_destination,with_reserve)
    src=r["checkpoint"]["bus_state"]
    vid,vehicle=next(iter(src["road_vehicles"].items()))
    company=vehicle["owner"]
    journal=d["journal"].encode("ascii")
    m=re.fullmatch(rb"(LTBUS-R1\n[0-9a-f]{64}\n([1-9][0-9]{0,2})\n)([0-9a-f]{64})\n",journal)
    require(m and digest(journal)==d.get("journal_sha256") and digest(m[1]).encode()==m[3],
            "Invalid played Luanti journal")
    start=int(src["game_clock"]["tick_counter"])
    target=start+int(m[2])
    idx=vehicle["cur_real_order_index"]
    next_index=(idx+1)%len(vehicle["orders"])
    current,upcoming=vehicle["orders"][idx],vehicle["orders"][next_index]
    require(d["start_tick"]==start and d["authored_tick"]==target and 0<target-start <=640 and
            start<d["arrival_tick"]<d["delivery_tick"]==target and
            d["vehicle_id"]==vid and d["company_id"]==company and d["order_list_id"]==vehicle["order_list_id"] and
            d["upcoming"]=={"index":next_index,"order_id":upcoming["order_id"],"station":upcoming["dest"]} and
            d["current"]=={"index":idx,"order_id":current["order_id"],"station":current["dest"],"tile":vehicle["dest_tile"]} and
            d["delivered"]==vehicle["onboard"] and 0<d["fare_pending"]<=1000 and d["loaded"]==0 and
            len(d["stock_motion"])==11 and all(isinstance(v,(int,float)) and v==int(v) for v in d["stock_motion"]),
            "Receipt is outside the supported played route/station/clock")
    require(upcoming["flags"]==0 and upcoming["type"]==97 and upcoming["refit_cargo"]==254,
            "Unsupported original order")
    if change_destination:
        alt=r["resume"]["existing_third_station"]
        station=src["stations"][alt]
        t=d["third"]
        route=t["route"]
        roads=r["checkpoint"]["map"]["road_tiles"]
        road=roads[str(station["tile"])]
        width=r["checkpoint"]["map"]["width"]
        require(isinstance(route,list) and 2<=len(route)<=128 and
                all(isinstance(v,(int,float)) and v==int(v) and str(int(v)) in roads for v in route) and
                t["station"]==alt and alt not in (current["dest"],upcoming["dest"]) and
                t["tile"]==station["tile"]==route[-1] and route[0]==vehicle["dest_tile"] and
                road["kind"]=="bay_stop" and road["station_id"]==alt and road["road_type"]==0 and
                road["station_owner"]==company and not road["unsupported_for_initial_bus_world"],
                "Wrong or unsupported distinct third station or route")
        for x,y in zip(route,route[1:]):
            x,y=int(x),int(y)
            delta=(y%width-x%width,y//width-x//width)
            edges={(0,-1):(1,4),(1,0):(2,8),(0,1):(4,1),(-1,0):(8,2)}
            require(delta in edges,"Third station receipt route must follow adjoining stock road tiles")
            a,b=edges[delta]
            left,right=roads[str(x)],roads[str(y)]
            require(left["road_type"]==0==right["road_type"]
                    and not (left["unsupported_for_initial_bus_world"] or right["unsupported_for_initial_bus_world"])
                    and left["road_bits"]&a and right["road_bits"]&b,
                    "Third station receipt route must follow reciprocally connected stock road")
    else:
        require("third" not in d,"Third station only valid for its explicit scope")
    if with_reserve:
        reserve=src["depot_reserve"]
        keys=("id","order_list_id","order_id","order_station","depot_id","depot_tile","raw_sha256")
        require(d.get("reserve")=={k:reserve[k] for k in keys},"Reserve order/vehicle receipt does not match real source records")
        d=dict(d,_reserve_binding=dict(reserve,order_tile=src["stations"][reserve["order_station"]]["tile"]))
    else:
        require("reserve" not in d,"Parked reserve only valid for its explicit roster scope")
    # Lua JSON transports exact small integers as floats. Canonicalize this
    # closed readout for native author diagnostics after range checks.
    def integral(value):
        if isinstance(value,float): return int(value)
        if isinstance(value,list): return [integral(v) for v in value]
        if isinstance(value,dict): return {k:integral(v) for k,v in value.items()}
        return value
    return integral(d)


def state(blob,d):
    p=decode_tables(blob,FILES)
    clock=next(iter(p[b"DATE"].values()))
    vid,company,oid=(int(d[k]) for k in ("vehicle_id","company_id","order_list_id"))
    veh=p[b"VEHS"][vid]["roadveh"][0]
    v=veh["common"][0]
    firm=p[b"PLYR"][company]
    c=firm["cur_economy"][0]
    users=sum(1 for row in p[b"VEHS"].values() for part in row["roadveh"]
              if part["common"][0]["orders"]==oid+1)
    req=int(d["upcoming"]["order_id"])
    packets=[p[b"CAPA"][reference(i,p[b"CAPA"],"resumed onboard")] for i in v["cargo.packets"]]
    result={"tick":clock["tick_counter"],"paused":clock["pause_mode"],
            "tile":v["tile"],"dest":v["dest_tile"],"income":c["income"],"delivered":c["delivered_cargo"][0],
            "company":v["owner"],"list":v["orders"]-1,"cursor":v["cur_real_order_index"],
            "engine":v["engine_type"],"shared_order_users":users,"cash":firm["money"],
            "loan":firm["current_loan"],"cash_fraction":firm["money_fraction"],"order_type":v["current_order.type"],
            "active_flags":v["current_order.flags"],"active_dest":v["current_order.dest"],
            "last_station":v["last_station_visited"],
            "order":p[b"ORDR"][req],"active_record":p[b"ORDR"][int(d["current"]["order_id"])],
            "first":p[b"ORDL"][oid]["first"],"pending_payments":list(p[b"CAPY"].values()),
            "units":sum(k["count"] for k in packets),
            "motion":[v[k] for k in ("x_pos","y_pos","z_pos","direction","cur_speed","subspeed","progress","cargo_age_counter")]
                     +[veh["state"],veh["frame"],v["load_unload_ticks"]]}
    if d.get("_reserve_binding"):
        reserve=raw_records(p,d["_reserve_binding"]["id"])
        result["reserve_full"]=stock_json(reserve)
        result["reserve_sha256"]=fingerprint(reserve)
    return result


def reserve_parked(s,d):
    reserve=d.get("_reserve_binding")
    if reserve:
        raw=s["reserve_full"]
        parked(raw,reserve)
        original=reserve["raw"]["vehicle"]["roadveh"][0]["common"][0]
        actual=raw["vehicle"]["roadveh"][0]["common"][0]
        elapsed=s["tick"]-d["start_tick"]
        require(elapsed>=0 and actual["tick_counter"]==(original["tick_counter"]+elapsed)%256
                and actual["cargo_age_counter"]==1+(original["cargo_age_counter"]-elapsed-1)%185
                and actual["current_order_time"]==original["current_order_time"]+elapsed,
                "Parked reserve's own stock clocks did not advance exactly")


def gate(s,d,edited=False):
    """The single authorized, non-shared, not-current stock order must match."""
    reserve_parked(s,d)
    now,up=d["current"],d["upcoming"]
    order=s["order"]
    require(s["tick"]==d["authored_tick"] and s["paused"]==1 and s["engine"]==116 and
            s["company"]==d["company_id"] and s["list"]==d["order_list_id"] and s["cursor"]==now["index"] and
            s["shared_order_users"]==1 and
            s["tile"]==now["tile"] and s["order_type"]&15==3 and s["active_dest"]==now["station"] and s["last_station"]==now["station"] and
            s["active_flags"]==0 and s["pending_payments"]==[{
                "front":d["vehicle_id"]+1,"route_profit":d["fare_pending"],
                "visual_profit":d["fare_pending"],"visual_transfer":0,
            }] and
            s["first"]==up["order_id"]+1 and order["next"]==now["order_id"]+1 and
            s["active_record"]["next"]==0 and s["active_record"]["dest"]==now["station"] and
            order["type"]==97 and order["flags"]==flags_for(d,edited) and order["dest"]==destination_for(d,edited) and
            order["refit_cargo"]==254 and s["income"]==0 and
            s["delivered"]==d["delivered"] and s["units"]==d["loaded"] and s["motion"]==d["stock_motion"],
            "Native draft is not the exact journal handoff, or next order is unsupported")


def author(draft,d):
    before=state(draft,d)
    gate(before,d)
    version,_,body=unpack_payload(draft)
    require(version==334,"Wrong native draft save version")
    # Validate the entire chunk framing via the existing strict walker.
    tuple(chunks(body))
    r=Reader(body)
    field_at=None
    while (tag:=bytes(r.take(4)))!=bytes(4):
        mode=r.byte()
        if mode&15==0:
            r.take(((mode>>4)<<24)|int.from_bytes(r.take(3),"big"))
            continue
        schema=r.record() if mode in (3,4) else None
        if tag==b"ORDR":
            require(mode==3 and read_schema(Reader(schema))==[(k,t,False,None) for k,t in ORDER_SCHEMA],
                    "Unknown pinned v334 native order schema")
        i=0
        while True:
            row=r.record()
            if row is None: break
            if tag==b"ORDR" and i==d["upcoming"]["order_id"]:
                require(len(row)==15 and row[0]==97 and row[1]==0 and row[8]==254,
                        "Order record cannot be narrowly patched")
                start=r.at-len(row)
                raw_dest=int.from_bytes(row[2:4],"big")
                require(raw_dest==d["upcoming"]["station"],"Stock upcoming destination field changed")
                field_at=start+1
            i+=1
    require(field_at is not None,"No editable native next order record")
    if d["action"] in (THIRD_ACTION,RESERVE_ACTION):
        pos=field_at+1
        new_field=destination_for(d,True).to_bytes(2,"big")
    else:
        pos=field_at
        new_field=bytes((flags_for(d,True),))
    body=bytes(body)
    edited=body[:pos]+new_field+body[pos+len(new_field):]
    require(len(edited)==len(body) and 0<sum(x!=y for x,y in zip(body,edited))<=len(new_field),
            "Only the requested stock next-order field may change")
    patch=b"OTTN"+draft[4:8]+edited
    after=state(patch,d)
    gate(after,d,True)
    require(after==dict(before,order=dict(before["order"],
            flags=flags_for(d,True),dest=destination_for(d,True))),"Unexpected state change")
    return patch


class Native:
    def __init__(self,root,binary,share,save,port,dispatch=None):
        self.root,self.share,self.initial=root,share,save
        private=root/".openttd"
        (private/"ai").mkdir(parents=True)
        for name in ("lang","baseset","game"):
            (private/name).symlink_to(share/name,target_is_directory=True)
        for item in (share/"ai").glob("*.nut"):
            (private/"ai"/item.name).symlink_to(item)
        watch=private/"ai"/"SaveProbe"
        watch.mkdir()
        (watch/"info.nut").write_text('''class Watch extends AIInfo {
 function GetAuthor() { return "Private interchange test"; }
 function GetName() { return "SaveProbe"; }
 function GetDescription() { return "Idle company for the isolated handoff"; }
 function GetVersion() { return 1; }
 function GetDate() { return "2026-11-22"; }
 function GetShortName() { return "SVQA"; }
 function GetAPIVersion() { return "14"; }
 function CreateInstance() { return "SaveProbe"; }
}
RegisterAI(Watch());
''')
        if dispatch is None:
            (watch/"main.nut").write_text("class SaveProbe extends AIController { function Start() { while (true) this.Sleep(1000); } }\n")
        else:
            # Only the opt-in disposable dispatch observation uses an AI
            # command, and only on the verified preserved reserve.
            (watch/"main.nut").write_text("""class SaveProbe extends AIController {
 function Start() {
   local id=%d;
   if (!AIVehicle.IsValidVehicle(id) || AIVehicle.GetState(id)!=AIVehicle.VS_IN_DEPOT ||
       AIVehicle.GetLocation(id)!=%d || AIOrder.GetOrderDestination(id,0)!=%d)
       throw "Refused unexpected stock reserve";
   if (!AIVehicle.StartStopVehicle(id)) throw "Could not dispatch verified reserve";
   AILog.Info("RESERVE_NATIVE_DISPATCH");
   while (true) this.Sleep(1000);
 }
}
""" % (dispatch["id"],dispatch["depot_tile"],dispatch["order_tile"]))
        self.cfg=root/"openttd.cfg"
        self.cfg.write_text("[network]\nserver_game_type = local\n")
        self.env={**os.environ,"HOME":str(root),"XDG_CONFIG_HOME":str(root/"config"),"XDG_DATA_HOME":str(root/"data")}
        self.args=[binary,"-s","null","-m","null","-I","OpenGFX","-D",f"127.0.0.1:{port}",
                   "-c",self.cfg,"-g",save]
        if dispatch is not None: self.args.extend(["-d","script=5"])
        self.log_path=root/"native.log"
        self.index=0

    def __enter__(self):
        self.log=self.log_path.open("w")
        self.proc=subprocess.Popen(self.args,cwd=self.share,env=self.env,stdin=subprocess.PIPE,
                                   stdout=self.log,stderr=subprocess.STDOUT,text=True)
        try:
            self.wait("Network revision name: 14.1")
        except Exception:
            self.__exit__(None,None,None)
            raise
        return self

    def __exit__(self,*exc):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(5)
        self.log.close()

    def read(self):
        return self.log_path.read_text(errors="replace")

    def wait(self,text,prior=0,timeout=8):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline and self.proc.poll() is None:
            if self.read().count(text)>prior: return
            time.sleep(.001)
        raise SaveError(f"Native 14.1 did not report {text!r}:\n{self.read()[-3500:]}")

    def send(self,text):
        self.proc.stdin.write(text+"\n")
        self.proc.stdin.flush()

    def step(self,seconds):
        pre=self.read().count("Game unpaused (manual)")
        post=self.read().count("Game paused (manual)")
        self.send("unpause")
        self.wait("Game unpaused (manual)",pre)
        if seconds: time.sleep(seconds)
        self.send("pause")
        self.wait("Game paused (manual)",post)

    def save(self):
        name=f"private_handoff_{self.index}"
        self.index+=1
        self.send("save "+name)
        self.wait(f"Map successfully saved to '{name}.sav'")
        options=(self.root/"save",self.root/".openttd"/"save")
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            for p in options:
                path=p/(name+".sav")
                if path.is_file():
                    with path.open("rb") as f:
                        blob=f.read(LIMIT+1)
                    try:
                        version,_,body=unpack_payload(blob)
                        require(version==334,"wrong version for native output")
                        tuple(chunks(body))
                    except (SaveError,lzma.LZMAError,zlib.error):
                        continue
                    return blob
            time.sleep(.025)
        raise SaveError("Cannot find the completed disposable native save")



def exact_stock_draft(stock,receipt):
    blob=stock.save()
    s=state(blob,receipt)
    require(s["tick"]==receipt["start_tick"] and s["paused"]==1 and s["income"]==0 and s["delivered"]==0,
            "Original stock paused control differs")
    target=receipt["authored_tick"]
    for _ in range(20):
        gap=target-s["tick"]
        if gap==0:
            gate(s,receipt)
            return blob
        require(gap>0,"Native stock missed the exact played tick; no export was written")
        stock.step((gap-5)*.027 if gap>6 else 0)
        blob=stock.save()
        s=state(blob,receipt)
    raise SaveError("Cannot reproducibly reach the exact played stock tick")


def export(original_path,receipt_path,binary,share,port,output):
    require(not output.exists() and output.resolve()!=original_path.resolve(),"Output must be a distinct new .sav")
    require(output.suffix==".sav","Output must have .sav extension")
    with original_path.open("rb") as f:
        original=f.read(LIMIT+1)
    with receipt_path.open("rb") as f:
        d=checked_receipt(original,json.loads(f.read(32769)))
    with tempfile.TemporaryDirectory(prefix="luanttd-order-export-") as t:
        root=Path(t)
        with Native(root/"control",binary,share,original_path,port) as stock:
            draft=exact_stock_draft(stock,d)
        edited=author(draft,d)
        private=root/"edited.sav"
        private.write_bytes(edited)
        with Native(root/"stock_write",binary,share,private,port) as stock:
            # Original stock writer creates the output candidate at the same
            # game tick. Initial 32-bit IDs and transient pointers are loaded
            # by the real engine, not just by the Python byte reader.
            final=stock.save()
            final_state=state(final,d)
            gate(final_state,d,True)
            require(final_state==state(edited,d),"Native resave changed the tested tick/cursor/finances")
        if final==original or digest(final)==digest(original):
            raise SaveError("Experiment unexpectedly produced untouched source bytes")
        private=root/"export_native.sav"
        private.write_bytes(final)
        with Native(root/"stock_read",binary,share,private,port) as stock:
            s=state(stock.save(),d)
            gate(s,d,True)
            require(s==final_state,"Reopening the stock export changed the tested paused state")
            credits=0
            last_income=s["income"]
            destination=destination_for(d,True)
            activated,visited=None,None
            max_observations=180 if d["action"] in (THIRD_ACTION,RESERVE_ACTION) else 24
            for _ in range(max_observations):
                near=bool(d.get("third") and s["tile"]==d["third"]["tile"])
                stock.step(0 if near else .32)
                s=state(stock.save(),d)
                reserve_parked(s,d)
                require(last_income<=s["income"]<=d["fare_pending"] and s["delivered"]==d["delivered"],
                        "First fare or delivery repeated before the next stop")
                if s["income"]>last_income:
                    require(s["income"]==d["fare_pending"],"Native payment did not match the played pending fare")
                    credits+=1
                last_income=s["income"]
                if s["active_dest"]==destination and s["order_type"]&15==1:
                    require(s["active_flags"]==flags_for(d,True) and s["cursor"]==d["upcoming"]["index"] and credits==1
                            and s["income"]==d["fare_pending"] and not s["pending_payments"],
                            "Edited stock order did not become the active upcoming order")
                    activated=activated or s["tick"]
                    if not d.get("third"):
                        break
                if d.get("third") and activated and s["order_type"]&15==3:
                    require(s["tile"]==d["third"]["tile"] and s["last_station"]==destination and
                            s["active_dest"]==destination and s["active_flags"]==flags_for(d,True),
                            "Bus stopped somewhere other than the selected distinct stock bay")
                    visited=s["tick"]
                    break
            require(activated is not None and (not d.get("third") or visited is not None),
                    "Edited stock upcoming order did not activate and visit its tested destination")
        reserve_proof=None
        if d.get("_reserve_binding"):
            reserve=d["_reserve_binding"]
            with Native(root/"stock_reserve_dispatch",binary,share,private,port,dispatch=reserve) as stock:
                control=state(stock.save(),d)
                gate(control,d,True)
                require(control==final_state,"Reserve dispatch control did not reopen the identical saved roster")
                released,service=None,None
                rv=control["reserve_full"]["vehicle"]["roadveh"][0]["common"][0]
                for _ in range(105):
                    stock.step(0 if rv["tile"]==reserve["order_tile"] else .32)
                    live=state(stock.save(),d)
                    rr=live["reserve_full"]["vehicle"]["roadveh"][0]
                    rv=rr["common"][0]
                    require(live["order"]["dest"]==destination and live["income"] in (0,d["fare_pending"]),
                            "Dispatch control changed the primary edit or credited unexpected fare")
                    if rv["tile"]!=reserve["depot_tile"] and rr["state"]!=254:
                        require(rv["owner"]==reserve["owner"] and not rv["vehstatus"]&2
                                and rv["orders"]==reserve["order_list_id"]+1
                                and rv["current_order.dest"]==reserve["order_station"]
                                and live["reserve_full"]["order"]["dest"]==reserve["order_station"],
                                "Native reserve did not follow its independent stored order")
                        if not released:
                            require(rv["cur_speed"]>0 and rv["current_order.type"]&15==1 and rv["cargo.packets"]==[],
                                    "Native reserve did not depart empty on the stored order")
                            released=live["tick"],rv["tile"]
                    if released and rv["current_order.type"]&15==3:
                        require(rv["tile"]==reserve["order_tile"] and rv["last_station_visited"]==reserve["order_station"]
                                and rv["cargo.packets"]==[],"Native reserve entered the wrong loading berth")
                        service=live["tick"]
                        break
                require(released and service and "RESERVE_NATIVE_DISPATCH" in stock.read(),
                        "Preserved depot reserve did not leave and serve its own unedited stop")
                reserve_proof={"reserve_vehicle":reserve["id"],"reserve_order_list":reserve["order_list_id"],
                    "reserve_order":reserve["order_id"],"reserve_destination":reserve["order_station"],
                    "reserve_parked_through_primary_visit":True,"reserve_full_handoff_sha256":final_state["reserve_sha256"],
                    "reserve_departure_control_tick":released[0],"reserve_departure_control_tile":released[1],
                    "reserve_visit_control_tick":service,"reserve_visit_control_tile":reserve["order_tile"]}
        require(digest(original_path.read_bytes())==digest(original),"Source bytes changed unexpectedly")
        with output.open("xb") as out:
            out.write(final)
        result={"schema":"luanttd-stock-order-experiment-proof/1","native_reopened":True,
                "source_unchanged":True,"stock_writer_used":True,"authored_tick":d["authored_tick"],
                "reopened_paused_tick":d["authored_tick"],"changed_order_id":d["upcoming"]["order_id"],
                "changed_order_station":destination,"old_station":d["upcoming"]["station"],
                "old_flags":0,"new_flags":flags_for(d,True),
                "active_order_observed_by_tick":activated,"delivered":d["delivered"],
                "fare_pending_at_export":d["fare_pending"],"fare_booked_after_reopen":s["income"],
                "native_credit_events":credits,
                "initial_save_sha256":digest(original),"new_save_sha256":digest(final),"general_export":False}
        if visited is not None:
            result.update(third_station_visit_tick=visited,third_station_tile=d["third"]["tile"],
                          third_station_visited=True,luanti_stock_route_tiles=len(d["third"]["route"]))
        if reserve_proof:
            result.update(reserve_proof)
        return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for field in ("openttd","share","source","receipt","output"):
        p.add_argument("--"+field,type=Path,required=True)
    p.add_argument("--port",type=int,default=39792)
    a=p.parse_args()
    try:
        proof=export(a.source.resolve(),a.receipt.resolve(),a.openttd.resolve(),a.share.resolve(),a.port,a.output.resolve())
        print(json.dumps(proof,sort_keys=True))
    except (SaveError,KeyError,TypeError,ValueError,OSError,lzma.LZMAError,zlib.error) as exc:
        p.exit(1,f"Stock order experiment not exported: {exc}\n")


if __name__=="__main__":
    main()
