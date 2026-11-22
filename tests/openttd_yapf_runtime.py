#!/usr/bin/env python3
"""Run the two stock road-fork cases in official OpenTTD 14.1.

Pass the executable and its share directory (containing lang/baseset).
An installed compatible graphics set is required even on dedicated mode.
Use a disposable HOME and a loopback-only game port. No engine patching.
"""
import argparse
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

args = argparse.ArgumentParser(description=__doc__)
args.add_argument("binary", type=Path)
args.add_argument("share", type=Path)
args.add_argument("--port", type=int, default=39711)
args.add_argument("--graphics", default="OpenGFX")
opts = args.parse_args()
binary = opts.binary.resolve()
share = opts.share.resolve()
probe = Path(__file__).with_name("openttd_yapf_ai")
with tempfile.TemporaryDirectory(prefix="openttd-yapf-") as temp:
    home = Path(temp)
    personal = home / ".openttd"
    (personal / "ai").mkdir(parents=True)
    for dirname in ("lang", "baseset", "game"):
        (personal / dirname).symlink_to(share / dirname, target_is_directory=True)
    # Preserve 14.1 API compatibility files without making the AI folder
    # itself a symlink: the test must not modify the stock install.
    for f in (share / "ai").glob("*.nut"):
        (personal / "ai" / f.name).symlink_to(f)
    shutil.copytree(probe, personal / "ai" / "YAPFProbe")
    cfg = home / "openttd.cfg"
    cfg.write_text("[network]\nserver_game_type = local\n")
    environment = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home/"config"),
                   "XDG_DATA_HOME": str(home/"share")}
    cmd = [binary, "-s", "null", "-m", "null", "-I", opts.graphics,
           "-D", f"127.0.0.1:{opts.port}", "-G", "1751", "-d", "script=5", "-c", cfg]
    with subprocess.Popen(cmd, cwd=share, env=environment, text=True,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, bufsize=1) as game:
        lines = queue.Queue()
        def read():
            for line in game.stdout:
                lines.put(line)
            lines.put(None)
        threading.Thread(target=read, daemon=True).start()
        deadline = time.monotonic() + 140
        results = []
        version_ok = False
        try:
            while time.monotonic() < deadline:
                try:
                    line = lines.get(timeout=1)
                except queue.Empty:
                    continue
                if line is None:
                    break
                print(line, end="", flush=True)
                if "Network revision name: 14.1" in line:
                    version_ok = True
                if "Map generated, starting game" in line:
                    assert version_ok, "The oracle must be stock OpenTTD 14.1."
                    game.stdin.write("start_ai YAPFProbe\nunpause\n")
                    game.stdin.flush()
                if "] YAPF_RESULT " in line:
                    results.append(line.split("YAPF_RESULT ",1)[1].split())
                if "] YAPF_DONE" in line or "The script died unexpectedly" in line:
                    break
            assert [r[:2] for r in results] == [["plain","straight"],["stop","detour"]], results
            print("PASS: stock OpenTTD 14.1 chose straight, then detour with an unordered stop.")
        finally:
            game.terminate()
            try:
                game.wait(5)
            except subprocess.TimeoutExpired:
                game.kill()
