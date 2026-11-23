#!/usr/bin/env python3
"""Boot, advance, save and reopen real ordinary Linux Luanti servers.

Usage: BAYLINE_NATIVE_TOOLS=/path/to/tool-extraction python3 tests/generated_world_dimensions_native.py NEW_OUTPUT_DIR
Without BAYLINE_NATIVE_TOOLS, use luantiserver, lua5.1 and zstd from PATH.
No game files are copied or modified, and existing worlds are not opened.
"""
import argparse
import hashlib
import os
import re
import signal
import socket
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIZES = ((512, 512), (1024, 1024), (4096, 64), (64, 4096))
CHECK = r"""
local Codec=dofile("mods/luanttd_core/packed_campaign.lua")
local s=Codec.decode(io.read("*a"))
local p=assert(s.stock_generated_profile)
local w,h=tonumber(os.getenv("TEST_WIDTH")),tonumber(os.getenv("TEST_DEPTH"))
assert(p.width==w and p.depth==h)
assert(s.corner_grid.width==w and s.corner_grid.depth==h)
assert(#s.tiles==w*h and #s.corner_grid.levels==(w+1)*(h+1))
local clock=assert(s.passenger_house_clock)
assert(2^clock.log_x==w and 2^clock.log_y==h and clock.head>=1 and clock.head<w*h)
assert(p.industry_stats and p.industries and #p.industries>0 and #s.sites>=2,
  "ordinary generated economy missing industries or towns")
assert(s.day>0 and clock.counter==s.day*74)
assert(s.tiles[w*h].stock_void)
print(s.day, clock.counter, clock.head, #p.industries, #s.sites)
"""


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def read_max_rss(pid, prior):
    try:
        status = Path(f"/proc/{pid}/status").read_text()
    except (FileNotFoundError, ProcessLookupError):
        return prior
    match = re.search(r"VmHWM:\s*(\d+)", status)
    return max(prior, int(match[1])) if match else prior


def native_session(world, config, out, env):
    command = ("luantiserver", "--world", str(world), "--config", str(config),
               "--gameid", "luanttd", "--logfile", "")
    max_rss = 0
    began = time.monotonic()
    with out.open("wb") as log:
        p = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            while time.monotonic() - began < 75 and p.poll() is None:
                max_rss = read_max_rss(p.pid, max_rss)
                if b"listening on" in out.read_bytes():
                    break
                time.sleep(.10)
            else:
                raise RuntimeError("Server did not start: " + out.read_text()[-4000:])
            startup = time.monotonic() - began
            time.sleep(3.5)  # more than two stock campaign days
            stopping = time.monotonic()
            p.send_signal(signal.SIGINT)
            while time.monotonic() - stopping < 25 and p.poll() is None:
                max_rss = read_max_rss(p.pid, max_rss)
                time.sleep(.10)
            assert p.poll() == 0, out.read_text()[-4000:]
            return startup, time.monotonic() - stopping, max_rss
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()


def checkpoint(world, env, w, h):
    path = world / "luanttd-wide-campaign.chk"
    signature, digest, payload = path.read_bytes().split(b"\n", 2)
    assert signature == b"LUANTTD-WIDE-CAMPAIGN-3-STATE"
    assert hashlib.sha256(payload).hexdigest().encode() == digest
    data = subprocess.run(("zstd", "-dc"), input=payload, capture_output=True, check=True).stdout
    result = subprocess.run(("lua5.1", "-e", CHECK), cwd=ROOT, input=data, capture_output=True,
                            env={**env, "TEST_WIDTH": str(w), "TEST_DEPTH": str(h)})
    if result.returncode:
        raise RuntimeError(result.stderr.decode())
    return (*map(int, result.stdout.split()), path.stat().st_size)


def verify(out, exact, w, h):
    local = out / f"{w}x{h}"
    games, home, world = (local / s for s in ("games", "home", "world"))
    for entry in (games, home, world):
        entry.mkdir(parents=True)
    (games / "luanttd").symlink_to(exact, target_is_directory=True)
    (world / "world.mt").write_text(
        "gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\n"
        "auth_backend = sqlite3\nmod_storage_backend = sqlite3\n"
    )
    env = {**os.environ, "HOME": str(home), "XDG_CACHE_HOME": str(local / "cache"),
           "LUANTI_GAME_PATH": str(games), "MINETEST_GAME_PATH": str(games)}
    tools = env.get("BAYLINE_NATIVE_TOOLS")
    if tools:
        tools = Path(tools).resolve()
        env["PATH"] = f"{tools}/run/bin:{tools}/usr/bin:{env['PATH']}"
        env["LD_LIBRARY_PATH"] = f"{tools}/usr/lib/x86_64-linux-gnu:{env.get('LD_LIBRARY_PATH', '')}"
    config = local / "server.conf"

    def configure(width, depth):
        config.write_text(
            f"port = {port()}\nserver_announce = false\nbind_address = 127.0.0.1\n"
            f"bayline_generated_map_width = {width}\nbayline_generated_map_depth = {depth}\n"
        )

    configure(w, h)
    initial = native_session(world, config, local / "initial.log", env)
    first = checkpoint(world, env, w, h)
    configure(64, 64)  # saved dimensions must win over new settings
    reopen = native_session(world, config, local / "reopen.log", env)
    second = checkpoint(world, env, w, h)
    assert second[0] > first[0] and second[1] > first[1]
    assert second[3] == first[3] and second[4] == first[4], (first, second)
    print(f"PASS {w}×{h}: listener {initial[0]:.2f}s / reopened {reopen[0]:.2f}s; "
          f"shutdown {initial[1]:.2f}s / {reopen[1]:.2f}s; peak {max(initial[2], reopen[2])/1024:.0f} MiB; "
          f"{second[3]} industries, {second[4]} sites, day {first[0]}→{second[0]}, "
          f"{second[5]:,} checkpoint bytes", flush=True)


if __name__ == "__main__":
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("output", type=Path)
    args.add_argument("--game", type=Path, default=ROOT)
    args.add_argument("--case", choices=[f"{w}x{h}" for w, h in SIZES])
    opt = args.parse_args()
    output = opt.output.resolve()
    output.mkdir()
    for width, depth in SIZES:
        if not opt.case or opt.case == f"{width}x{depth}":
            verify(output, opt.game.resolve(), width, depth)
