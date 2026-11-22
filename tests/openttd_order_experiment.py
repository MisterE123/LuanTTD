#!/usr/bin/env python3
"""Fail-closed schema/receipt checks on private real input and native output."""
import argparse
from copy import deepcopy
from pathlib import Path
import json
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from openttd_export_order_experiment import author, checked_receipt, digest, gate, state, THIRD_ACTION, RESERVE_ACTION, NO_LOAD, SaveError


def rejected(call, why):
    try:
        call()
    except SaveError:
        return
    raise AssertionError("unsafe export path accepted: "+why)


def verify(original, outcome, receipt, proof=None):
    decoded=checked_receipt(original,receipt)
    before=digest(original)
    after=digest(outcome)
    assert before==receipt["source_sha256"] and before!=after
    restored=state(outcome,decoded)
    gate(restored,decoded,True)
    reserve=receipt["action"]==RESERVE_ACTION
    third=receipt["action"] in (THIRD_ACTION,RESERVE_ACTION)
    assert restored["order"]["flags"]==(0 if third else NO_LOAD) and restored["active_record"]["flags"]==0
    assert restored["active_record"]["dest"]==receipt["current"]["station"]
    assert restored["last_station"]==receipt["current"]["station"]
    if third:
        assert restored["order"]["dest"]==receipt["third"]["station"]!=receipt["upcoming"]["station"]
        assert proof and proof["source_unchanged"] and proof["third_station_visited"] and proof["native_credit_events"]==1
        assert proof["new_save_sha256"]==after and proof["initial_save_sha256"]==before
        assert proof["authored_tick"]==proof["reopened_paused_tick"]==receipt["authored_tick"]
        assert proof["third_station_visit_tick"]>proof["active_order_observed_by_tick"]>proof["authored_tick"]
        assert proof["fare_booked_after_reopen"]==9 and proof["third_station_tile"]==receipt["third"]["tile"]
    elif proof:
        assert proof["reopened_paused_tick"]==2726 and not proof.get("third_station_visited")
    assert restored["income"]==0 and restored["delivered"]==5 and restored["units"]==0
    assert restored["pending_payments"][0]["route_profit"]==9
    for role,broken in (
        ("source provenance",{"source_sha256":"0"*64}),
        ("changed intent kind",{"action":"skip_entire_order"}),
        ("forged tick",{"authored_tick":receipt["authored_tick"]+1}),
        ("already-boarded outgoing passengers",{"loaded":1}),
        ("invalid journal",{"journal":receipt["journal"].replace("LTBUS-R1","LTBUS-R2")}),
        ("current order as next",{"upcoming":receipt["current"]}),
    ):
        rejected(lambda: checked_receipt(original,dict(receipt,**broken)),role)
    rejected(lambda: author(original,decoded),"original source at the wrong tick")
    rejected(lambda: author(outcome,decoded),"already edited order must not be applied again")
    wrong_amount=deepcopy(restored)
    wrong_amount["pending_payments"][0]["route_profit"]=18
    rejected(lambda: gate(wrong_amount,decoded,True),"pending cash must match exactly")
    wrong_company=deepcopy(restored)
    wrong_company["pending_payments"][0]["front"]=6
    rejected(lambda: gate(wrong_company,decoded,True),"pending payment must belong to this vehicle")
    another=deepcopy(restored)
    another["shared_order_users"]=2
    rejected(lambda: gate(another,decoded,True),"shared order list")
    if third:
        for key,value in (
            ("station",receipt["upcoming"]["station"]),
            ("station",receipt["current"]["station"]),
            ("tile",receipt["current"]["tile"]),
            ("route",[receipt["current"]["tile"],receipt["third"]["tile"]]),
        ):
            altered=deepcopy(receipt)
            altered["third"][key]=value
            rejected(lambda: checked_receipt(original,altered),"false third-stop "+key)
        if reserve:
            rr=restored["reserve_full"]
            r=receipt["reserve"]
            assert proof["reserve_full_handoff_sha256"]==restored["reserve_sha256"]
            assert proof["reserve_parked_through_primary_visit"] and proof["reserve_vehicle"]==r["id"]
            assert proof["reserve_destination"]==r["order_station"]==rr["order"]["dest"]
            assert rr["order_list_id"]!=receipt["order_list_id"] and rr["order_id"]!=receipt["upcoming"]["order_id"]
            assert proof["reserve_departure_control_tick"]<proof["reserve_visit_control_tick"]
            assert proof["reserve_departure_control_tile"]!=r["depot_tile"]
            assert proof["reserve_visit_control_tile"]==decoded["_reserve_binding"]["order_tile"]
            for key,value in (
                ("id",receipt["vehicle_id"]),
                ("order_list_id",receipt["order_list_id"]),
                ("order_id",receipt["upcoming"]["order_id"]),
                ("order_station",receipt["third"]["station"]),
                ("raw_sha256","0"*64),
            ):
                wrong=deepcopy(receipt)
                wrong["reserve"][key]=value
                rejected(lambda: checked_receipt(original,wrong),"false reserve "+key)
            for key in ("tick_counter","cargo_age_counter","current_order_time","x_pos","orders"):
                wrong=deepcopy(restored)
                v=wrong["reserve_full"]["vehicle"]["roadveh"][0]["common"][0]
                v[key]+=1
                rejected(lambda: gate(wrong,decoded,True),"altered reserve "+key)
            wrong=deepcopy(receipt)
            wrong["action"]=THIRD_ACTION
            rejected(lambda: checked_receipt(original,wrong),"pretended the reserve did not exist")
            print("PASS: parked reserve full fingerprint, exact native clocks, independent service stop, 26 rejected variants.")
        else:
            print("PASS: rewrote a distinct next destination, same due order and £9 pending, actual stock visit, 15 rejected variants.")
    else:
        print("PASS: native distinct output, exact pending payment, valid next-order bit, 11 rejected export variants.")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ("source","output","receipt"):
        parser.add_argument("--"+field,type=Path,required=True)
    parser.add_argument("--native-proof",type=Path)
    a=parser.parse_args()
    verify(a.source.read_bytes(),a.output.read_bytes(),json.loads(a.receipt.read_text()),
           json.loads(a.native_proof.read_text()) if a.native_proof else None)
