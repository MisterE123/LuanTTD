#!/usr/bin/env python3
"""Check the service adapter's passenger acceptance against pinned house records."""
import argparse
from hashlib import sha256
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
DIGEST="a6925280753e551f4426a92d76a8c57f49171a519c860d855b3cd29946c817d7"
LUA="""
local M=dofile("mods/bayline/road_station_service.lua")()
for id=0,109 do print(M.house_passenger_acceptance(id)) end
"""

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("--lua",default="lua5.1")
    a=p.parse_args()
    src=a.source/"town_land.h"
    if not src.exists():
        src=a.source/"src"/"table"/"town_land.h"
    raw=src.read_bytes()
    assert sha256(raw).hexdigest()==DIGEST,"Expected pinned OpenTTD 14.1 town_land.h"
    data=raw.decode().split("static const HouseSpec _original_house_specs[] = {",1)[1]
    expected=[]
    for args,ident in re.findall(r"MS\(([^)]*)\), // ([0-9A-F]{2})",data,re.S):
        fields=[s.strip() for s in args.split(",")]
        assert len(fields)==15 and fields[12]=="CT_PASSENGERS"
        assert len(expected)==int(ident,16)
        expected.append(fields[7])
    assert len(expected)==110
    with tempfile.TemporaryDirectory() as tmp:
        lua=Path(tmp)/"ref.lua"
        lua.write_text(LUA)
        got=subprocess.check_output([a.lua,str(lua)],cwd=ROOT,text=True).splitlines()
    assert got==expected
    print("PASS: every vanilla house's passenger acceptance in eighths")

if __name__=="__main__":
    main()
