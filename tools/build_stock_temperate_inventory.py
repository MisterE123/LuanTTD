#!/usr/bin/env python3
"""Render an honest RC1 stock content inventory from the exact engine table.

'Playable' means the named type has a finished native asset and an ordinary
construct/order/run/earn path in at least one unmodified Temperate era. It
does not claim NewGRF support, all refits, all cargoes or every stock mechanic.
"""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re

COVERAGE = {
    "Rail": ({0,8,9,10,11,13,14,15,22,23,24,27,29,30,32}, {28}),
    "Road": (set(range(116,120)) | set(range(123,129)) | set(range(132,147)), set()),
    "Ship": ({204,205,206,207,208,211,212}, set()),
    "Aircraft": ({215,216,217,219,220,225,226,228}, set()),
}
KINDS = {"MT":"Rail","MM":"Rail","MW":"Rail","MR":"Road","MS":"Ship","MA":"Aircraft"}
LIMITS = {
    22: "Paired power heads; paid with passenger carriage. Internal Mail holds are not active.",
    28: "Native Mail Van asset and data; no rail Mail service yet.",
    29: "One mounted coal wagon service.",
    30: "One mounted oil wagon service.",
    32: "One mounted Goods van service.",
    204: "Paid oil tanker, one tanker slot.",
    205: "Paid oil tanker, one tanker slot.",
    206: "Paid passenger ferry.",
    207: "Paid passenger ferry.",
    208: "Paid passenger hovercraft.",
    211: "Paid after refit to Coal.",
    212: "Paid after refit to Coal.",
}
CITY = {217,220,225,226,228}

def escape(t):
    return t.replace("|", r"\|")

def inventory(source):
    raw=source.read_bytes()
    assert sha256(raw).hexdigest()=="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
    rows={}
    for macro,climates,stock,name in re.findall(
        r"^\s*(M[TMWRSA])\([^\n]*LandscapeTypes\(\{([^}]+)\}\)\), //\s+(\d+) (.*?)\s*$",
        raw.decode(),re.M):
        if "T" not in climates: continue
        uid=int(stock)
        assert uid not in rows
        rows[uid]=KINDS[macro],name
    assert len(rows)>50
    out=["# Temperate stock content inventory","",
         "Reference: OpenTTD 16.0-RC1 base stock, not NewGRFs or vehicles exclusive to other climates.",
         "**Playable** means at least one ordinary paid service exists with the original native model.",
         "It does not imply full simulation or mode parity. **Art only** is not a depot offer.",
         "Dated offers use the stock calendar where mounted. See [State of the Port](PORTING.md) for mechanics.","",
         "## Town buildings","",
         "31/31 Temperate root house IDs have original native 3D presentation, including the multipart hotel, stadiums and mall.",
         "See [building artwork](../art/stock_temperate_towns.md). Other climates are not counted.","",
         "| Mode | Playable stock types | Art only | Total Temperate stock types |","| --- | ---: | ---: | ---: |"]
    for kind,(played,art) in COVERAGE.items():
        active={key for key,r in rows.items() if r[0]==kind}
        assert (played|art)<=active and not played&art
        out.append(f"| {kind} | {len(played)} | {len(art)} | {len(active)} |")
    for kind,(played,art) in COVERAGE.items():
        out+=["",f"## {kind}","","| Stock ID | OpenTTD type | Status | Notes |","| ---: | --- | --- | --- |"]
        for uid,(mode,name) in sorted(rows.items()):
            if mode!=kind: continue
            status="Playable" if uid in played else "Art only" if uid in art else "Not mounted"
            note=LIMITS.get(uid, "Paid passenger service; City Airport required." if uid in CITY else "")
            out.append(f"| {uid} | {escape(name)} | {status} | {note} |")
    return "\n".join(out+[""])

if __name__=="__main__":
    p=ArgumentParser(description=__doc__)
    p.add_argument("engines",type=Path)
    p.add_argument("--write",action="store_true")
    o=p.parse_args()
    target=Path(__file__).resolve().parents[1]/"docs/stock-content-inventory.md"
    body=inventory(o.engines)
    if o.write: target.write_text(body)
    else:
        assert target.read_text()==body
        print("PASS pinned Temperate stock inventory")
