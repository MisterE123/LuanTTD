#!/usr/bin/env python3
"""Extract complete dated stock rows from the pinned OpenTTD source."""
# SPDX-License-Identifier: GPL-2.0-only
from datetime import date, timedelta
from pathlib import Path
import argparse
import json
import re
import subprocess

PIN = "07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"
MODES = {"MT": "rail", "MM": "rail", "MW": "wagon", "MR": "road", "MS": "water", "MA": "air"}
LANDSCAPES = {"T": "temperate", "A": "arctic", "S": "tropic", "Y": "toyland"}


def source_rows(repo):
    pin = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
    if pin != PIN:
        raise ValueError(f"Expected OpenTTD release {PIN}, got {pin}")
    root = repo / "src" / "table"
    engines = (root / "engines.h").read_text().split("_orig_engine_info[] = {", 1)[1].split("};", 1)[0]
    date_rows=[]
    for mode, day, landscapes, i, name in re.findall(
            r"^\s*(M[MTWRSA])\(\s*(\d+),[^\n]+?LandscapeTypes\(\{([^}]*)\}\)\),\s*//\s*(\d+)\s+(.+?)\s*$",
            engines, re.M):
        raw = int(day)
        avail = (date(1920, 1, 1)+timedelta(days=raw)).isoformat()
        date_rows.append({"stock_id":int(i),"type":MODES[mode],"name":name,"base_date":avail,
                          "climates":[LANDSCAPES[k] for k in re.findall(r"[TASY]", landscapes)]})
    assert [a["stock_id"] for a in date_rows]==list(range(256)), len(date_rows)
    airports = (root / "airport_defaults.h").read_text().split("_origin_airport_specs[] = {",1)[1].split("};",1)[0]
    airport_rows = []
    for key, w, h, first, last in re.findall(
        r"^\s*AS(?:_ND)?\((\w+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+|CalendarTime::MAX_YEAR),",
            airports, re.M):
        airport_rows.append({"key":key,"width":int(w),"height":int(h),"first_year":int(first),
                             "last_year":int(last) if last.isdigit() else None})
    assert len(airport_rows)==9
    bridges = (root / "bridge_land.h").read_text().split("_orig_bridge[] = {",1)[1].split("};",1)[0]
    bridge_rows=[]
    for y, minimum, maximum, multiplier, speed, palette, title in re.findall(
            r"^\s*\{(CalendarTime::MIN_YEAR|TimerGameCalendar::Year\{\d+\}),\s*(\d+),\s*(UINT16_MAX|\d+),"
            r"\s*(\d+),\s*(\d+),\s*0x[\dA-Fa-f]+,\s*(\w+),\s*\n\s*(STR_BRIDGE_\w+),",
            bridges, re.M):
        first = re.search(r"\d+", y)
        bridge_rows.append({"stock_id":len(bridge_rows),"source_name":title,
                            "first_year":int(first[0]) if first else None,
                            "min_middle":int(minimum),"max_middle":int(maximum) if maximum.isdigit() else None,
                            "price_factor":int(multiplier),"stock_speed":int(speed),"palette":palette})
    assert len(bridge_rows)==13
    return {"version":"16.0-RC1","commit":pin,"engine_date_basis":"base rows, not a guarantee of exact public sale day",
            "vehicles":date_rows,"airports":airport_rows,"bridges":bridge_rows}


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    p=parser.parse_args()
    print(json.dumps(source_rows(p.source.resolve()),indent=2,ensure_ascii=False))
