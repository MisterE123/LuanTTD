#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo "usage: $0 BASELINE_GIT_REV"; exit 64; }
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-paint-bench.XXXXXX")
printf 'Evidence: %s\n' "$out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/"
mod="$game/mods/luanttd_core"
cp tests/qa_layout.lua "$mod/"
git show "$1:mods/luanttd_core/render.lua" > "$out/baseline.lua"
python3 - "$out" "$mod" <<'PY'
from pathlib import Path
import sys
stage,mod=map(Path, sys.argv[1:])
path=mod/"render.lua"
baseline=(stage/"baseline.lua").read_text().split("  local function paint_region",1)[1].split("  core.register_on_generated",1)[0]
original=path.read_text()
target=stage/"instrumented.lua"
target.write_text(original.replace("  core.register_on_generated(function(minp,maxp)",
    "  R.qa_paint=paint_region\n  function R.qa_baseline"+baseline+
    "  core.register_on_generated(function(minp,maxp)",1))
target.replace(path)
path=mod/"init.lua"
target=stage/"fixture.lua"
target.write_text(path.read_text()+"\n"+Path("tests/campaign_paint_bench_native.lua").read_text())
target.replace(path)
PY
printf 'gameid = luanttd\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40588}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nbind_address = 127.0.0.1\nserver_announce = false\nluanttd_qa_plain_layout = true\nluanttd_qa_paint_peak = %s\n' "$port" "$port" "${BAYLINE_PAINT_PEAK:-54}" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 120 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' >"$out/server.log" 2>&1; then
  tail -80 "$out/server.log";exit 1
fi
grep -F 'NATIVE PAINT BENCH ' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
