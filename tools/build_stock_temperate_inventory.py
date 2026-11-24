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
    "Rail": ({0,8,9,10,11,12,13,14,15,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,54,55,57,58,60,84,89,90,92}, set()),
    "Road": ({116,117,118,119,123,124,125,126,127,128,132,133,134,135,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155}, set()),
    "Ship": ({204,205,206,207,208,211,212}, set()),
    "Aircraft": ({215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,237,238,253}, set()),
}
KINDS = {"MT":"Rail","MM":"Rail","MW":"Rail","MR":"Road","MS":"Ship","MA":"Aircraft"}
LIMITS = {
    12: "Powered twin, 80 seats; 120 with a separately purchasable Passenger Carriage.",
    22: "Paired power heads with 4 Mail bags per head and one 40-seat passenger carriage. Stock loading, reversal and payment verified.",
    25: "Paired 240 km/h conventional electric heads; one separately purchasable carriage.",
    26: "Paired 264 km/h conventional electric heads; one separately purchasable carriage.",
    28: "Native 30-bag van; shared town Mail allocator with road, ordinary rail orders and paid SQLite restart proof.",
    29: "One mounted coal wagon service.",
    30: "One mounted oil wagon service.",
    31: "Livestock from a Farm to a Factory.",
    32: "One mounted Goods van service.",
    33: "Grain from a Farm to a Factory; separate empty and loaded models.",
    34: "Forest to Sawmill; separate empty and loaded models.",
    35: "Ore mine to steel mill; native empty/loaded model.",
    36: "Steel mill to factory; native empty/loaded model.",
    37: "Runs Valuables between two separate Banks.",
    54: "Mounted X2001 monorail with independent passenger, Mail or Oil service.",
    55: "Twin-ended original monorail; each powered head carries a separate 25-seat cabin.",
    57: "OpenTTD monorail passenger carriage; independent purchase and real fares.",
    58: "OpenTTD monorail Mail van; independently loaded and paid.",
    60: "Monorail 35 kL Oil Tanker; mixed fleets keep the exact gauge restriction.",
    84: "First Maglev group: original Lev1 Leviathan, matched depot, guideway and wagons.",
    89: "Maglev Passenger Carriage: original 47-seat stock.",
    90: "Maglev Mail Van: original 37-bag stock.",
    92: "Maglev 37 kL Oil Tanker; refinery delivery on true Maglev spans.",
    204: "Paid oil tanker, one tanker slot.",
    205: "Paid oil tanker, one tanker slot.",
    206: "Paid passenger ferry.",
    207: "Paid passenger ferry.",
    208: "Paid passenger hovercraft.",
    211: "Paid after refit to Coal.",
    212: "Paid after refit to Coal.",
    217: "Paid passenger service; City Airport required.",
    218: "Fast jet; City Airport; 100 passengers and 20 Mail bags.",
    220: "Paid passenger service; City Airport required.",
    221: "Country or City Airport; stock conventional class.",
    222: "Paid passenger service; City Airport required.",
    223: "Paid passenger service; City Airport required.",
    224: "Paid passenger service; City Airport required.",
    225: "Paid passenger service; City Airport required.",
    226: "Paid passenger service; City Airport required.",
    227: "Paid passenger service; City Airport required.",
    228: "Paid passenger service; City Airport required.",
    229: "Paid passenger service; City Airport required.",
    230: "Paid passenger service; City Airport required.",
    231: "Paid passenger service; City Airport required.",
    232: "240 passengers + 35 Mail. City Airport, original three-engine mesh with retracting gear.",
    233: "260 passengers + 30 Mail. City Airport, original wide-body twinjet with retracting gear.",
    234: "210 passengers + 25 Mail. City Airport, original compact wide-body twinjet.",
    235: "160 passengers + 20 Mail. City Airport, shortened Airtaxi derivative.",
    237: "80 passengers + 10 Mail. Country or City Airport, original four-engine short-runway airframe.",
    238: "85 passengers + 10 Mail. Country or City Airport, rear-engine regional twinjet.",
    253: "Country/City hangars and neutral oil-rig pad, 40 seats + 15 Mail, original rotating 3D rotors.",
}
CITY = {217,218,220,222,223,224,225,226,227,228,229,230,231,232,233}

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
         "31/31 Temperate root house IDs have original native 3D presentation, including the multipart hotel, stadiums and mall. All 27 single-tile roots also use their stock construction stages and visual slots.",
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
