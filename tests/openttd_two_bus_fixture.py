#!/usr/bin/env python3
"""Build a real private stock fleet: loaded service bus plus an ordered depot reserve."""
import argparse
import json
from pathlib import Path
import tempfile

from openttd_third_stop_fixture import prepare as third, STOCK
from openttd_save_bus_state import probe_bus_state


def prepare(private_ai):
    third(private_ai)
    app=private_ai/"main.nut"
    code=app.read_text()
    anchor='        Require(AIVehicle.StartStopVehicle(v),"Dispatch stock bus");'
    assert code.count(anchor)==1
    extra='''
        local reserve=AIVehicle.BuildVehicle(d,engine);
        Require(AIVehicle.IsValidVehicle(reserve) && reserve!=v,"Build reserve stock bus");
        Require(AIOrder.AppendOrder(reserve,s,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order reserve to through stop");
        Require(AIVehicle.GetState(reserve)==AIVehicle.VS_IN_DEPOT,"Reserve remains in depot");
        AILog.Info("SAVE_RESERVE "+reserve+" "+d+" "+AIStation.GetStationID(s));
'''
    app.write_text(code.replace(anchor,extra+anchor))


def generate(binary,share,port,output):
    assert not output.exists(),"Reserve fixture output must be new"
    with tempfile.TemporaryDirectory(prefix="stock-two-bus-fixture-") as name:
        stock,points=STOCK.oracle(binary,share,Path(name),port,private_fixture=prepare)
        blob=stock.read_bytes()
        data=STOCK.snapshot(blob)
        records=probe_bus_state(blob)
        STOCK.compare(data,points)
        STOCK.check_in_flight(blob,data,points)
        fleet=records["road_vehicles"]
        assert len(fleet)==2
        (primary,)=tuple(i for i,v in fleet.items() if v["onboard"]>0)
        (reserve,)=tuple(i for i in fleet if i!=primary)
        assert fleet[reserve]["motion"]["state"]==254 and fleet[reserve]["order_list_id"]!=fleet[primary]["order_list_id"]
        assert len(records["stations"])==3
        with output.open("xb") as f:
            f.write(blob)
    return {"source_sha256":data["source"]["sha256"],"primary":primary,"reserve":reserve,
            "second_order_list":fleet[reserve]["order_list_id"],"private_only":True}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for f in ("openttd","share","output"):
        p.add_argument("--"+f,type=Path,required=True)
    p.add_argument("--port",type=int,default=39821)
    a=p.parse_args()
    print(json.dumps(generate(a.openttd.resolve(),a.share.resolve(),a.port,a.output.resolve()),sort_keys=True))
