#!/usr/bin/env python3
"""Verify the isolated first bus trip in three native disposable Luanti boots."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import openttd_sparse as fixture
from openttd_save_bus_resume import resume_input

TESTS,REPO=fixture.TESTS,fixture.REPO


def configure(home,save,reference,visual=False,third_station=False,depot_reserve=False):
    games=home/"games"
    game=games/"triptest"
    mod=game/"mods"/"triptest"
    mod.mkdir(parents=True)
    (mod/"mod.conf").write_text("name = triptest\n")
    (game/"game.conf").write_text("title = Isolated stock bus first delivery\n")
    shutil.copyfile(TESTS/"openttd_bus_first_delivery_native.lua",mod/"init.lua")
    modules=REPO/"mods"/"bayline"
    for file in ("world_storage.lua","import/openttd_map.lua","import/openttd_sparse.lua",
                 "import/openttd_bus_checkpoint.lua","import/openttd_bus_first_delivery.lua",
                 "road_loading_runtime.lua","import/openttd_bus_order_intent.lua",
                 *("openttd/"+x+".lua" for x in ("slope","road_slope","road_motion","road_motion_data",
                                            "yapf_road_follow","yapf_road_cost","yapf_road_search",
                                            "road_speed","income","loading_timing","passengers"))):
        shutil.copyfile(modules/file,mod/Path(file).name)
    (mod/"input.json").write_text(json.dumps(resume_input(save.read_bytes(),third_station,depot_reserve),sort_keys=True))
    shutil.copyfile(reference,mod/"reference.json")
    if visual:
        from PIL import Image, ImageDraw
        shutil.copyfile(TESTS/"openttd_bus_first_delivery_visual.lua",mod/"visual.lua")
        (mod/"models").mkdir()
        (mod/"textures").mkdir()
        for pattern in ("bl_land_*.obj","bl_town_flyer.obj","bl_bus_shelter_corner.obj"):
            for asset in (modules/"models").glob(pattern):
                shutil.copy(asset,mod/"models")
        for pattern in ("bl_grass*.png","bl_road_surface_*.png","bl_vehicle_palette.png","bl_road_architecture.png"):
            for asset in (modules/"textures").glob(pattern):
                shutil.copy(asset,mod/"textures")
        for bits in (1,2,4,8):
            pavement=Image.open(mod/"textures"/f"bl_road_surface_{bits}.png").convert("RGB")
            draw=ImageDraw.Draw(pavement)
            # Original bay presentation, not a stock sprite. The existing
            # connected approach meets a painted off-line turnaround pad.
            draw.rounded_rectangle((3,3,29,29),radius=6,fill=(123,111,100))
            draw.rounded_rectangle((4,4,28,28),radius=5,fill=(65,69,76))
            draw.line([(9,20),(9,25),(23,25),(23,20)],fill=(214,201,165),width=1)
            pavement.save(mod/"textures"/f"stock_trip_bay_{bits}.png")
    return games


def verify(server,save,reference,port,receipt=None,third_station=False,depot_reserve=False):
    digest=sha256(save.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="luanttd-bus-resume-test-") as name:
        home=Path(name)
        games=configure(home,save,reference,third_station=third_station,depot_reserve=depot_reserve)
        config=home/"luanti.conf"
        env={**os.environ,"HOME":str(home),"LUANTI_GAME_PATH":str(games),"MINETEST_GAME_PATH":str(games)}
        expected={"verify":"LUANTTD STOCK TRIP CURSOR MATCH",
                  "record":"LUANTTD STOCK TRIP NATIVE BEFORE RESTART",
                  "restore":"LUANTTD STOCK TRIP NATIVE AFTER RESTART"}
        if receipt: expected["intent"]="LUANTTD PLAYED STOCK ORDER INTENT READY"
        for stage,key in expected.items():
            config.write_text(f"port = {port}\nbind_address = 127.0.0.1\nserver_announce = false\nbus_first_delivery_mode = {stage}\n")
            cmd=[server,"--gameid","triptest","--world",home/"world","--config",config,"--logfile",""]
            proc=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=35)
            log=proc.stdout+proc.stderr
            assert proc.returncode==0 and key in log and "ERROR[" not in log,log
            for line in log.splitlines():
                if "LUANTTD STOCK TRIP " in line or key in line: print(line)
        if receipt:
            with receipt.open("xb") as new:
                new.write((home/"world"/"stock-order-intent.json").read_bytes())
    assert sha256(save.read_bytes()).hexdigest()==digest


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--luanti",type=Path)
    p.add_argument("--visual-dir",type=Path,help="stage a GUI fixture instead of starting the headless tester")
    p.add_argument("--save",type=Path,required=True)
    p.add_argument("--reference",type=Path,required=True)
    p.add_argument("--emit-order-intent",type=Path,help="separate new receipt from the played native trip")
    p.add_argument("--with-existing-third-station",action="store_true")
    p.add_argument("--with-depot-reserve",action="store_true")
    p.add_argument("--port",type=int,default=39791)
    a=p.parse_args()
    if a.visual_dir:
        a.visual_dir.mkdir(parents=True,exist_ok=False)
        configure(a.visual_dir.resolve(),a.save.resolve(),a.reference.resolve(),visual=True,third_station=a.with_existing_third_station,depot_reserve=a.with_depot_reserve)
    elif a.luanti:
        verify(a.luanti.resolve(),a.save.resolve(),a.reference.resolve(),a.port,a.emit_order_intent,a.with_existing_third_station,a.with_depot_reserve)
    else:
        p.error("--luanti or --visual-dir required")
