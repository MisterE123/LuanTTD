#!/usr/bin/env python3
"""Edit one future station order from an exact Luanti-played two-bus stock merge."""
# SPDX-License-Identifier: GPL-2.0-only
from copy import deepcopy
import argparse
import json
from pathlib import Path
import tempfile

from openttd_road_junction_fixture import (BAY, BRANCH, JUNCTION, SCHEMA, classify,
                                          luanti_differential, sample, validate_start)
from openttd_bus_checkpoint_resume import forecast
from openttd_export_order_experiment import (Native, ORDER_SCHEMA, Reader, SaveError, chunks,
                                             decode_tables, digest, read_schema, require, unpack_payload)
from openttd_save_inspect import LIMIT

POOLS = {b"DATE",b"VEHS",b"ORDR",b"ORDL",b"CAPA",b"CAPY",b"PLYR",b"ROAD",b"STNN",b"DEPT",b"PATS"}
KEYS = ("id","x_pos","y_pos","z_pos","tile","direction","frame","state","cur_speed","subspeed",
        "progress","blocked_ctr","tick_counter","current_order_time","cargo_age_counter","dest_tile","onboard")
OWNER = 0
ACTION = {"id":4,"list":0,"order":0,"active_index":1,"next_index":0,"current":0,"old":1,"new":2}


def read_save(path):
    with path.open("rb") as f:
        blob=f.read(LIMIT+1)
    require(len(blob)<=LIMIT,"Private source exceeds the save budget")
    return blob


def tables(blob):
    return decode_tables(blob,POOLS)


def actors(data):
    roads=[data[b"VEHS"][n]["roadveh"][0] for n in (4,5)]
    return [v["common"][0] for v in roads]


def economy(data):
    company=data[b"PLYR"][OWNER]["cur_economy"][0]
    return company["income"],company["delivered_cargo"][0]


def choose(source,trace):
    ids=validate_start(source)
    require(ids==[4,5] and trace.get("schema")==SCHEMA and trace.get("source_sha256")==digest(source)
            and trace["vehicle_ids"]==ids and trace["samples"][0]==sample(source,ids),
            "Saved trace does not match this exact sealed stock input")
    actual=classify(trace)
    gate_ticks=actual["merge_moving_overlap_ticks"]
    require(gate_ticks and actual["merge_blocked_ticks"],"Source is not the active merge lab")
    # The first observed moving overlap precedes the real merge wait.
    target=gate_ticks[0]
    replay=next(row for row in trace["samples"] if row["clock"]["tick_counter"]==target)
    require(len(replay["buses"])==2 and all(v["tile"]==JUNCTION and v["cur_speed"]>0
            and v["current_order.type"]==97 and v["cur_real_order_index"]==1 and v["dest_tile"]==BAY
            and v["blocked_ctr"]==0 for v in replay["buses"])
            and replay["buses"][0]["onboard"]==5 and replay["buses"][1]["onboard"]==0,
            "Expected one loaded lead and empty merge bus on both active east-bay legs")
    return replay, dict(ACTION,tick=target)


def read_intent(report,action,source,point):
    intent=report["order_intent"]
    body=intent["body"]
    require(isinstance(body,str) and len(body)<4000 and digest(body.encode())==intent["sha256"],
            "Invalid dual-active Luanti journal checksum")
    rows=[[v[k] for k in KEYS] for v in point["buses"]]
    expected={"schema":"luanttd-dual-active-destination-intent/1","source_sha256":digest(source),
              "authored_tick":action["tick"],"edit":action,"actors":rows}
    require(json.loads(body)==expected,"Intent does not identify the exact two unmodified active cursors")
    return intent["sha256"]


def open_draft(stock,source,target):
    start=sample(source,[4,5])
    blob=stock.save()
    require(sample(blob,[4,5])==start,"Opened wrong source")
    for _ in range(28):
        now=sample(blob,[4,5])
        delta=target["clock"]["tick_counter"]-now["clock"]["tick_counter"]
        require(delta>=0,f"Missed exact played traffic tick by {-delta}; no export was written")
        if delta==0:
            require(now==target,"Live native state differs from played traffic checkpoint")
            return blob
        # Stock console pause costs two ticks on the qualified server.
        # Correct coarse-pulse parity well before the exact gate; an
        # unattainable or overshot clock still aborts without writing.
        interval=(delta-20)*.028 if delta>23 else (.035 if delta>=5 and delta%2 else 0)
        stock.step(interval)
        blob=stock.save()
    raise SaveError("Did not reach the exact active boundary")


def verify_gate(blob,point,edited=False):
    data=tables(blob)
    a,b=actors(data)
    require(sample(blob,[4,5])==point,"Paused state or either actor changed at the author boundary")
    require(economy(data)==(0,0) and not data[b"CAPY"],"Unexpected pre-delivery stock finance")
    require(a["owner"]==b["owner"]==OWNER and a["orders"]==1 and b["orders"]==2
            and a["current_order.dest"]==b["current_order.dest"]==0 and b["last_station_visited"]==2
            and data[b"ORDL"]=={0:{"first":1},1:{"first":3}},
            "Expected independent active lists with the same current bay")
    order=data[b"ORDR"]
    require(set(order)=={0,1,2,3} and all(x["type"]==97 and x["flags"]==0 and x["refit_cargo"]==254 for x in order.values())
            and [order[i]["dest"] for i in range(4)]==[2 if edited else 1,0,2,0]
            and [order[i]["next"] for i in range(4)]==[2,0,4,0],
            "Order used by another actor or target is not a future station order")
    require(data[b"ROAD"][0]["xy"]==BAY and {r["xy"] for r in data[b"ROAD"].values()} >= {BAY,BRANCH},
            "Target stations are not the verified reachable native bays")
    return data


def author(draft,point):
    expected=verify_gate(draft,point)
    version,_,body=unpack_payload(draft)
    require(version==334,"Unknown stock layout")
    tuple(chunks(body))
    reader=Reader(body)
    pos=None
    while (tag:=bytes(reader.take(4)))!=bytes(4):
        mode=reader.byte()
        if mode&15==0:
            reader.take(((mode>>4)<<24)|int.from_bytes(reader.take(3),"big"))
            continue
        schema=reader.record() if mode in (3,4) else None
        if tag==b"ORDR":
            require(mode==3 and read_schema(Reader(schema))==[(k,t,False,None) for k,t in ORDER_SCHEMA],
                    "Unknown pinned order schema")
        n=0
        while (row:=reader.record()) is not None:
            if tag==b"ORDR" and n==0:
                require(len(row)==15 and row[0]==97 and row[1]==0 and row[2:4]==b"\0\x01" and row[8]==254,
                        "The precise old future record is not present")
                pos=reader.at-len(row)+3
            n+=1
    require(pos is not None,"Missing exact destination byte")
    body=bytes(body)
    edited=b"OTTN"+draft[4:8]+body[:pos]+b"\x02"+body[pos+1:]
    expected[b"ORDR"][0]["dest"]=2
    require(verify_gate(edited,point,edited=True)==expected,"Other paused stock state changed")
    return edited,pos


def observe(stock,trace,point,expected):
    control=stock.save()
    require(verify_gate(control,point,edited=True)==expected,"Native read changed protected stock state")
    start=point["clock"]["tick_counter"]
    forecasted=forecast({p-1:expected[b"CAPA"][p-1] for p in actors(expected)[0]["cargo.packets"]},BAY,256)
    require(forecasted>0,"Original loaded leg must have a positive fare")
    live=control
    refs={r["clock"]["tick_counter"]:r for r in trace["samples"]
          if start<r["clock"]["tick_counter"]<=start+48}
    # Preserve both short-run behaviors, including the stock merge hold and release.
    compared, hold, release=[],None,None
    for _ in range(31):
        stock.step(0)
        live=stock.save()
        row=sample(live,[4,5])
        t=row["clock"]["tick_counter"]
        if t in refs:
            require(row==refs[t],"Authored future order altered an active junction clock/cursor/packet")
            compared.append(t)
            merge=row["buses"][1]
            if merge["blocked_ctr"] and merge["direction"]==6:
                hold=t
            elif hold and not merge["blocked_ctr"] and merge["direction"]==5:
                release=t
        if release and len(compared)>=6:
            break
    require(hold and release and len(compared)>=6,"Native warm merge hold/release not reproduced")
    payment_count,delivery,settled,activated,lead_branch,follower_bay=0,None,None,None,None,None
    last_income=0
    staged=None
    for _ in range(230):
        stock.step(.18)
        live=stock.save()
        d=tables(live)
        t=next(iter(d[b"DATE"].values()))["tick_counter"]
        a,b=actors(d)
        income,n=economy(d)
        if not activated:
            require(n in (0,5) and income in (0,forecasted) and income>=last_income,
                    "Original rider/fare repeated or changed before the next order became active")
            if income>last_income:
                payment_count+=1
                settled=t
            if n==5:
                delivery=delivery or t
                pending=[x for x in d[b"CAPY"].values() if x["front"]==5]
                if not income and pending:
                    require(len(pending)==1 and pending[0]["route_profit"]==forecasted,
                            "Wrong staged payment for the original passengers")
                    staged=staged or t
            if a["current_order.type"]&15==1 and a["current_order.dest"]==2:
                require(a["cur_real_order_index"]==0 and a["dest_tile"]==BRANCH
                        and n==5 and income==forecasted and payment_count==1
                        and not any(x["front"]==5 for x in d[b"CAPY"].values()),
                        "Wrong fare lifecycle or expected future order not activated")
                activated=t
        # An empty can finish its zero-transfer loading pulse between
        # checkpoints; the stock visit marker must change and the actor
        # must still be physically inside the ordered bay.
        if (b["tile"]==BAY and b["last_station_visited"]==0
                and d[b"ORDR"][3]["dest"]==0 and d[b"ORDR"][2]["dest"]==2
                and ((b["current_order.type"]&15==3 and b["current_order.dest"]==0)
                     or (b["cur_real_order_index"]==0 and b["current_order.dest"]==2))):
            follower_bay=follower_bay or t
        if activated and a["tile"]==BRANCH and a["current_order.type"]&15==3 and a["current_order.dest"]==2:
            lead_branch=t
        if lead_branch and follower_bay:
            break
        last_income=income
    require(lead_branch and follower_bay and delivery and staged and settled and activated
            and release<delivery<=staged<settled<=activated<=lead_branch and payment_count==1,
            "Did not observe both preserved services and distinct authored later visit")
    return {"warm_exact_ticks":compared,"warm_hold_tick":hold,"warm_release_tick":release,
            "original_delivered":5,"original_fare_booked":forecasted,"native_credit_events_before_activation":payment_count,
            "delivery_observed_tick":delivery,"staged_fare_observed_tick":staged,"settled_observed_tick":settled,"new_order_observed_tick":activated,
            "lead_new_bay_visit_tick":lead_branch,"follower_original_bay_visit_tick":follower_bay}


def check_rejections(source,trace,draft,point,report,action):
    def rejects(label,work):
        try:
            work()
        except SaveError:
            return label
        raise AssertionError("Unsafe dual-active handoff accepted: "+label)

    wrong_input=trace.copy()
    wrong_input["source_sha256"]="0"*64
    wrong_begin=deepcopy(trace)
    wrong_begin["samples"][0]["buses"][1]["tick_counter"]+=1
    paused_other_pose=deepcopy(point)
    paused_other_pose["buses"][1]["x_pos"]+=1
    paused_other_packet=deepcopy(point)
    paused_other_packet["buses"][0]["packets"][0]["count"]-=1
    altered_intent=deepcopy(report)
    altered_intent["order_intent"]["sha256"]="0"*64
    wrong_order=dict(action,order=1)
    return [
        rejects("source digest mismatch",lambda: choose(source,wrong_input)),
        rejects("second actor initial clock mismatch",lambda: choose(source,wrong_begin)),
        rejects("second actor played pose mismatch",lambda: author(draft,paused_other_pose)),
        rejects("lead packet count mismatch",lambda: author(draft,paused_other_packet)),
        rejects("played intent checksum mismatch",lambda: read_intent(altered_intent,action,source,point)),
        rejects("intent attempts changing active order",lambda: read_intent(report,wrong_order,source,point)),
    ]


def run(paths, port, luanti_port):
    source=read_save(paths.source)
    require(paths.output.suffix==".sav" and paths.output.resolve()!=paths.source.resolve() and not paths.output.exists(),
            "Output must be a distinct new private .sav")
    trace=json.loads(paths.trace.read_bytes())
    point, action=choose(source,trace)
    replay=luanti_differential(paths.luanti,luanti_port,trace,author=action)
    journal=read_intent(replay,action,source,point)
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-dual-active-author-") as temp:
        root=Path(temp)
        with Native(root/"acquire",paths.openttd,paths.share,paths.source,port) as stock:
            draft=open_draft(stock,source,point)
        negatives=check_rejections(source,trace,draft,point,replay,action)
        patched,pos=author(draft,point)
        _version,_compression,body=unpack_payload(draft)
        require(sum(a!=b for a,b in zip(body,patched[8:]))==1 and len(body)==len(patched)-8,
                "The decoded native file changed outside the exact order destination byte")
        edited=root/"one-byte-edit.sav"
        edited.write_bytes(patched)
        wanted=verify_gate(patched,point,edited=True)
        with Native(root/"resave",paths.openttd,paths.share,edited,port) as stock:
            final=stock.save()
            require(verify_gate(final,point,edited=True)==wanted,"Stock writer did not preserve the full active roster and ledger")
        candidate=root/"candidate.sav"
        candidate.write_bytes(final)
        with Native(root/"verify",paths.openttd,paths.share,candidate,port) as stock:
            observations=observe(stock,trace,point,wanted)
        require(read_save(paths.source)==source and final!=source,"Original stock source changed")
        with paths.output.open("xb") as out:
            out.write(final)
    return {"schema":"luanttd-stock-dual-active-export-proof/1","general_export":False,
            "source_sha256":digest(source),"source_unchanged":True,"output_sha256":digest(final),
            "stock_wrote_and_reopened":True,"edit":action,"paused_both_raw_rows_identical":True,
            "paused_other_orders_packets_clocks_finances_identical":True,
            "decoded_difference_byte":pos,"luanti_intent_sha256":journal,"negative_cases_rejected":negatives,
            "luanti_differential_start_tick":replay["clock_start"],"luanti_differential_end_tick":replay["clock_end"],
            **observations}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("openttd","share","luanti","source","trace","output"):
        p.add_argument("--"+name,type=Path,required=True)
    p.add_argument("--port",type=int,default=39855)
    p.add_argument("--luanti-port",type=int,default=39856)
    a=p.parse_args()
    print(json.dumps(run(a,a.port,a.luanti_port),sort_keys=True))
