#!/usr/bin/env python3
"""Read opening inventories from an isolated, unmodified OpenTTD 16.0-RC1."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import argparse
import json
import os
import re
import selectors
import shutil
import subprocess
import tempfile
import time

SOURCE_AI = Path(__file__).resolve().with_name("openttd_timeline_ai")
QUEUES = ("ENGINE", "CARGO", "INDUSTRY", "INITIAL_SITE", "RAILTYPE", "ROADTYPE", "BRIDGE", "AIRPORT")


def snapshot(bin_, port, seed, year, climate):
    with tempfile.TemporaryDirectory(prefix="luanttd-timeline-stock-") as name:
        home = Path(name)
        cfg = home / "openttd.cfg"
        cfg.write_text(
            "[game_creation]\n"
            f"landscape = {climate}\n"
            f"starting_year = {year}\n"
            "map_x = 7\nmap_y = 7\n"
            "[network]\nserver_game_type = local\nmin_active_clients = 0\n"
            "[difficulty]\nmax_no_competitors = 0\n"
        )
        (home / "ai").mkdir()
        shutil.copytree(SOURCE_AI, home / "ai" / "TimelineProbe")
        env = dict(os.environ, HOME=name, XDG_CONFIG_HOME=name, XDG_DATA_HOME=name, LC_ALL="C")
        p = subprocess.Popen(
            [bin_, "-D", f"127.0.0.1:{port}", "-d", "script=5", "-x", "-c", cfg,
             "-I", "OpenGFX", "-G", str(seed), "-t", str(year), "-g"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, cwd=home, env=env,
        )
        assert p.stdin and p.stdout
        log = bytearray()
        queue = {key.lower(): [] for key in QUEUES}
        opened = None
        with selectors.DefaultSelector() as sel:
            sel.register(p.stdout, selectors.EVENT_READ)
            deadline = time.monotonic()+28
            sent = False
            try:
                while time.monotonic()<deadline and p.poll() is None:
                    for key, _ in sel.select(.12):
                        fragment = os.read(key.fd, 65536)
                        log.extend(fragment)
                    if not sent and (b"Game started" in log or time.monotonic()+25>deadline):
                        p.stdin.write(b"start_ai TimelineProbe\nunpause\n")
                        p.stdin.flush()
                        sent=True
                    if b"TIMELINE_DONE" in log:
                        break
            finally:
                if p.poll() is None:
                    p.terminate()
                    p.communicate(timeout=7)
        for line in log.decode("utf-8","replace").splitlines():
            match = re.search(r"\bTIMELINE_([A-Z_]+)\s*(.*)$", line)
            if not match:
                continue
            kind, value=match.groups()
            if kind=="YEAR":
                opened=int(value.strip())
            elif kind in QUEUES:
                queue[kind.lower()].append(value.strip())
        if re.search(rb"TIMELINE_DONE", log) is None or opened!=year or not queue["engine"]:
            raise RuntimeError(f"OpenTTD probe did not reach the opening snapshot: {log[-9000:].decode('utf-8','replace')}")
        for k in queue:
            queue[k].sort(key=lambda line: tuple(int(w) for w in line.split()[:1]))
        return {"version":"16.0-RC1","year":opened,"climate":climate,"seed":seed,**queue}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("openttd",type=Path)
    parser.add_argument("--year",type=int,default=1950)
    parser.add_argument("--seed",type=int,default=1751)
    parser.add_argument("--climate",default="temperate",choices=["temperate","arctic","tropic","toyland"])
    parser.add_argument("--port",type=int,default=40401)
    a=parser.parse_args()
    executable=a.openttd.resolve()
    helptext=subprocess.check_output([executable,"-h"],text=True)
    if not helptext.startswith("OpenTTD 16.0-RC1\n"):
        parser.error("expected the exact OpenTTD 16.0-RC1 binary")
    print(json.dumps(snapshot(executable,a.port,a.seed,a.year,a.climate),ensure_ascii=False,indent=2))


if __name__=="__main__":
    main()
