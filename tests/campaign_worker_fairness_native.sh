#!/usr/bin/env bash
# Opt-in performance replay. The passed checkpoint is read only.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 4 ]]; then
  echo "usage: $0 LUANTI_SERVER BASELINE_REV GENERATED_CHECKPOINT NEW_OUTPUT_DIRECTORY" >&2
  exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
checkpoint=$(realpath "$3")
test -f "$checkpoint"
mkdir "$4"
d=$(realpath "$4")
g="$d/games/luanttd"; m="$g/mods/luanttd_core"
mkdir -p "$g" "$d/home"
cp game.conf "$g/"
cp -al mods "$g/" 2>/dev/null || { mkdir -p "$g/mods"; cp -a mods/. "$g/mods/"; }
{ cat mods/luanttd_core/init.lua; printf '\n'; cat tests/campaign_worker_fairness_native.lua; } > "$m/init.next"
mv "$m/init.next" "$m/init.lua"
export HOME="$d/home" LUANTI_GAME_PATH="$d/games" MINETEST_GAME_PATH="$d/games"
for side in baseline candidate baseline2 candidate2; do
  for file in campaign_authority_worker campaign_step; do
    if [[ $side == baseline* ]]; then git show "$base:mods/luanttd_core/$file.lua" > "$m/$file.next"
    else cp "mods/luanttd_core/$file.lua" "$m/$file.next"; fi
    mv "$m/$file.next" "$m/$file.lua"
  done
  sed '/local s=assert(storage.read()/a\  s.speed=4' "$m/campaign_authority_worker.lua" > "$m/worker.next"
  mv "$m/worker.next" "$m/campaign_authority_worker.lua"
  w="$d/$side"
  mkdir "$w"
  cp "$checkpoint" "$w/luanttd-campaign-owner.chk"
  printf 'gameid = luanttd\nbackend = sqlite3\nmod_storage_backend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' > "$w/world.mt"
  printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\ndedicated_server_step = 0.025\nqa_fairness_seconds = %s\n' \
    "${BAYLINE_NATIVE_PORT:-44141}" "${LUANTTD_BENCH_SECONDS:-32}" > "$w/conf"
  timeout "${LUANTTD_BENCH_TIMEOUT:-160}" "$server" --world "$w" --gameid luanttd --config "$w/conf" --logfile '' >"$w/log" 2>&1 ||
    { tail -40 "$w/log";exit 1; }
  python3 - "$w/log" "$side" <<'PY'
from pathlib import Path
from statistics import median
from math import ceil
import re, sys

log = Path(sys.argv[1]).read_text()
data = sorted(float(x) for x in re.findall(r'FAIRNESS SAMPLE ms=(\d+[.]\d+)', log))
assert data and 'FAIRNESS FINISH' in log and 'FAIRNESS DURABLE' in log, log[-4000:]
print(sys.argv[2], len(data), 'p50', median(data), 'p95', data[ceil(len(data)*.95)-1], 'max', data[-1])
print('\n'.join(line for line in log.splitlines() if 'FAIRNESS FINISH' in line or 'FAIRNESS DURABLE' in line))
PY
done
