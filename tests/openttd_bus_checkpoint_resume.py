#!/usr/bin/env python3
"""Resume the private OpenTTD reference only; LuanTTD stays unresumed."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import zlib
import lzma

import openttd_sparse as fixture
from openttd_save_bus_checkpoint import checkpoint, SaveError
from openttd_save_tables import decode_tables


def sample(blob, company, bus):
    pools=decode_tables(blob,{b"DATE",b"PLYR",b"VEHS",b"CAPA"})
    v=pools[b"VEHS"][bus]["roadveh"][0]["common"][0]
    road=pools[b"VEHS"][bus]["roadveh"][0]
    firm=pools[b"PLYR"][company]
    c=firm["cur_economy"][0]
    clock=next(iter(pools[b"DATE"].values()))
    packets={i-1:pools[b"CAPA"][i-1] for i in v["cargo.packets"] if i}
    return {"tick":clock["tick_counter"],"pause":clock["pause_mode"],"income":c["income"],
            "delivered":c["delivered_cargo"][0],"tile":v["tile"],"dest":v["dest_tile"],
            "packets":packets,"profit":v["profit_this_year"],
            "motion":[v[k] for k in ("x_pos","y_pos","z_pos","direction","cur_speed","subspeed","progress","cargo_age_counter")]
                     +[road["state"],road["frame"],v["current_order.type"],v["load_unload_ticks"]],
            "units":sum(p["count"] for p in packets.values()),"cash_fixed":firm["money"]*256+firm["money_fraction"]}


def forecast(packets,dest,width):
    """Independent pinned GetDistance + temperate passenger fare (not playback)."""
    amount=0
    for p in packets.values():
        age=p["periods_in_transit"]
        x,z=dest%width,dest//width
        leg=abs(p["travelled.x"]-x)+abs(p["travelled.y"]-z)
        origin=p["source_xy"]
        d=min(leg,abs(origin%width-x)+abs(origin//width-z))
        if age>136:   # outside this forecast's early-age acceptance case
            raise AssertionError("unexpected mature packet in short stock reference")
        factor=max(31,255-age-max(0,age-24))
        amount += p["count"]*d*factor*3185//2**21
    return amount


def resume(binary,share,save,port,depot_reserve=False):
    blob=save.read_bytes()
    start=checkpoint(blob,depot_reserve)
    company=next(iter(start["bus_state"]["company_balances"]))
    bid,b=next(iter(start["bus_state"]["road_vehicles"].items()))
    original=sample(blob,company,bid)
    stock_dest=b["dest_tile"]
    assert original["pause"]==1 and original["delivered"]==0
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-resume-") as d:
        root=Path(d)
        private=root/".openttd"
        (private/"ai").mkdir(parents=True)
        for name in ("lang","baseset","game"):
            (private/name).symlink_to(share/name,target_is_directory=True)
        for item in (share/"ai").glob("*.nut"):
            (private/"ai"/item.name).symlink_to(item)
        # Keep the AI identity but replace its start method with an observer
        # that issues no command. The saved bus continues under the stock
        # vehicle controller; no controller/clock/stock executable patch.
        observer=private/"ai"/"SaveProbe"
        observer.mkdir()
        shutil.copyfile(fixture.TESTS/"openttd_save_ai"/"info.nut",observer/"info.nut")
        (observer/"main.nut").write_text(
            "class SaveProbe extends AIController { function Start() { while (true) this.Sleep(1000); } }\n")
        config=root/"server.cfg"
        config.write_text("[network]\nserver_game_type = local\n")
        env={**os.environ,"HOME":str(root),"XDG_CONFIG_HOME":str(root/"config"),"XDG_DATA_HOME":str(root/"share")}
        args=[binary,"-s","null","-m","null","-I","OpenGFX","-D",f"127.0.0.1:{port}",
              "-c",config,"-g",save]
        with (root/"stock.log").open("w+") as log, subprocess.Popen(args,cwd=share,env=env,
                stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True) as proc:
            def send(*lines):
                proc.stdin.write("\n".join(lines)+"\n")
                proc.stdin.flush()

            def saved(label):
                send("save "+label)
                paths=[root/"save"/(label+".sav"), private/"save"/(label+".sav")]
                deadline=time.monotonic()+6
                while time.monotonic()<deadline:
                    for p in paths:
                        if p.is_file():
                            try: return sample(p.read_bytes(),company,bid)
                            except (SaveError,OSError,zlib.error,lzma.LZMAError): pass
                    time.sleep(.05)
                raise AssertionError(f"no readable stock checkpoint {label}")

            def print_log():
                return (root/"stock.log").read_text(errors="replace")

            try:
                until=time.monotonic()+15
                loaded=None
                while time.monotonic()<until:
                    logtext=print_log()
                    assert proc.poll() is None, logtext
                    if "Network revision name: 14.1" in logtext:
                        loaded=saved("paused_control")
                        break
                    time.sleep(.05)
                if loaded is None:
                    loaded=saved("paused_control")
                assert loaded==original, (original,loaded,print_log())
                reference=settled=after=None
                before_delivery=before_settlement=None
                last=loaded
                samples=[original]
                for i in range(60):
                    send("unpause")
                    time.sleep(.32)
                    pause_count=print_log().count("Game paused (manual)")
                    send("pause")
                    deadline=time.monotonic()+4
                    while print_log().count("Game paused (manual)")==pause_count and time.monotonic()<deadline:
                        time.sleep(.025)
                    assert print_log().count("Game paused (manual)")>pause_count
                    nxt=saved(f"private_tick_{i}")
                    samples.append(nxt)
                    assert nxt["pause"]==1 and nxt["tick"]>last["tick"], (nxt,last,print_log())
                    if reference is None and nxt["delivered"]:
                        before_delivery,reference=last,nxt
                    if settled is None and nxt["income"]>original["income"]:
                        before_settlement,settled=last,nxt
                    elif settled is not None:
                        after=nxt
                        break
                    last=nxt
                assert reference and settled and after, (reference,settled,after)
                assert before_delivery["tile"]==stock_dest==reference["tile"], (before_delivery,reference)
                assert reference["delivered"]==b["onboard"] and not (original["packets"].keys() & reference["packets"].keys())
                # Stock posts the accumulated fare at CargoPayment destruction,
                # which need not be in the tick when passenger delivery is counted.
                assert before_delivery["tick"]<reference["tick"]<=settled["tick"]<after["tick"]
                assert reference["tick"]-before_delivery["tick"]<15
                predicted=forecast(before_delivery["packets"], stock_dest, start["map"]["width"])
                delta=settled["income"]-original["income"]
                assert delta==predicted>0, (delta,predicted,before_delivery,reference,settled)
                profit_delta=settled["profit"]-before_settlement["profit"]
                if depot_reserve:
                    # A primary daily fractional running-cost debit can be
                    # in this sampled window. The parked bus has no running
                    # ticks. Check the same exact raw cash+fraction movement.
                    cost=delta*256-profit_delta
                    assert 0<=cost<1500 and settled["cash_fixed"]-before_settlement["cash_fixed"]==profit_delta
                else:
                    assert profit_delta==delta*256
                assert after["income"]==settled["income"] and after["delivered"]==reference["delivered"]
                assert sha256(save.read_bytes()).hexdigest()==start["map"]["source"]["sha256"]
                return {"source":"unmodified OpenTTD 14.1 native reference",
                        "source_sha_unchanged":True,"source_sha256":start["map"]["source"]["sha256"],
                        "starting_tick":original["tick"],
                        "last_pre_delivery_tick":before_delivery["tick"],"delivery_observed_by_tick":reference["tick"],
                        "fare_observed_by_tick":settled["tick"], "settlement_recheck_tick":after["tick"],
                        "destination_source_tile":stock_dest,"delivered":reference["delivered"],
                        "fare":delta,"pre_delivery_age":next(iter(before_delivery["packets"].values()))["periods_in_transit"],
                        "luanttd_resumed":False,
                        "samples":[[s["tick"],s["tile"],s["motion"],s["units"],s["delivered"],s["income"]]
                                   for s in samples]}
            except Exception as exc:
                raise AssertionError(str(exc)+"\n"+print_log()[-8000:]) from exc
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(5)


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--openttd",type=Path,required=True)
    p.add_argument("--share",type=Path,required=True)
    p.add_argument("--save",type=Path,required=True)
    p.add_argument("--port",type=int,default=39786)
    p.add_argument("--with-depot-reserve",action="store_true")
    a=p.parse_args()
    print(json.dumps(resume(a.openttd.resolve(),a.share.resolve(),a.save.resolve(),a.port,a.with_depot_reserve),sort_keys=True))
