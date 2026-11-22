#!/usr/bin/env python3
"""Generate a private real OpenTTD 14.1 three-stop fixture; only two initial orders."""
import argparse
import json
from pathlib import Path
import tempfile

import openttd_sparse as fixture
from openttd_save_bus_state import probe_bus_state
from openttd_save_inspect import SaveError

STOCK=fixture.STOCK


def prepare(private_ai):
    main=private_ai/"main.nut"
    code=main.read_text()
    anchor="        local owner=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);"
    if code.count(anchor)!=1:
        raise AssertionError("stock probe source anchor missing")
    extension='''
        // Third source facility exists from creation, but is not in the bus's orders.
        // This berth occupies the flat tile east of the depot-front spur.
        local third=a+w+2;
        Require(AIRoad.BuildRoadFull(third-2,third-1),"Connect alternate bay frontage");
        Require(AIRoad.BuildRoadStation(third,third-1,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build alternate third bay");
        Require(AIRoad.IsRoadStationTile(third) && AIRoad.AreRoadTilesConnected(third-1,third),
                "Verify existing third stop connection");
        AILog.Info("SAVE_THIRD "+third+" "+AIStation.GetStationID(third));
'''
    main.write_text(code.replace(anchor,extension+anchor))


def generate(binary,share,port,output):
    if output.exists():
        raise SaveError("Private stock fixture must have a new output path")
    with tempfile.TemporaryDirectory(prefix="luanttd-third-stock-fixture-") as name:
        source,points=STOCK.oracle(binary,share,Path(name),port,private_fixture=prepare)
        blob=source.read_bytes()
        data=STOCK.snapshot(blob)
        slots=probe_bus_state(blob)
        STOCK.compare(data,points)
        STOCK.check_in_flight(blob,data,points)
        bid,bus=next(iter(slots["road_vehicles"].items()))
        served={o["dest"] for o in bus["orders"]}
        third,=slots["stations"].keys()-served
        assert len(served)==2 and len(slots["stations"])==3 and third==2
        assert slots["stations"][third]["tile"]==44642
        with output.open("xb") as f:
            f.write(blob)
    return {"source_sha256":data["source"]["sha256"],"private_only":True,
            "start_tick":slots["game_clock"]["tick_counter"],"bus":bid,
            "initial_stations":sorted(served),"distinct_existing_station":third,
            "distinct_existing_tile":slots["stations"][third]["tile"]}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for field in ("openttd","share","output"):
        p.add_argument("--"+field,type=Path,required=True)
    p.add_argument("--port",type=int,default=39794)
    a=p.parse_args()
    print(json.dumps(generate(a.openttd.resolve(),a.share.resolve(),a.port,a.output.resolve()),sort_keys=True))
