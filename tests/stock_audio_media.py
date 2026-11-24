#!/usr/bin/env python3
"""Verify every shipped reverse-mapped sample and full soundtrack decodes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--root",type=Path,default=ROOT)
args=parser.parse_args()
mod=args.root/"mods"/"luanttd_core"
sounds=mod/"sounds"
source=ROOT/"third_party"/"openmsx"
titles=[x.split(";")[0].strip() for x in (source/"themes.list").read_text().splitlines() if x and x[0]!="#"]
assert len(titles)==31 and sum(x=="theme" for x in titles)==1
catalog=(mod/"stock_audio_music.lua").read_text()
assert re.findall(r'slot="([^"]+)"',catalog)==titles
lengths=list(map(float,re.findall(r'duration=(\d+\.\d+)',catalog)))
assert len(lengths)==len(titles)

def check(data):
    path,rate,channels,duration=data
    val=json.loads(subprocess.check_output(["ffprobe","-v","error","-show_entries",
        "stream=codec_name,channels,sample_rate,duration:stream_tags=license","-of","json",str(path)]))["streams"]
    assert len(val)==1
    st=val[0]
    assert st["codec_name"]=="vorbis" and st["channels"]==channels and int(st["sample_rate"])==rate,path
    tags=st["tags"]
    assert tags["license"]==("CC BY-SA 3.0" if channels==1 else "GPL-2.0-only"),path
    if duration is not None:
        assert abs(duration-float(st["duration"]))<.01 and float(st["duration"])>30,path
    else: assert float(st["duration"])>0,path
    subprocess.run(["ffmpeg","-nostdin","-v","error","-xerror","-i",str(path),"-f","null","-"],check=True)

jobs=[(sounds/f"stock_sfx_{i:02x}.ogg",22050,1,None) for i in range(73)]
jobs.extend((args.root/"menu"/"theme.ogg" if slot=="theme" else sounds/f"openmsx_{i:02}.ogg",
    32000 if slot=="theme" else 22050,2,lengths[i]) for i,slot in enumerate(titles))
with ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(check,jobs))
print("PASS: All 73 OpenSFX clips plus OpenMSX title and 30 full gameplay tracks decoded, with expected channels, durations and licenses.")
