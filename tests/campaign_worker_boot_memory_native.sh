#!/usr/bin/env bash
# Compare resident memory around the normal host-to-worker checkpoint handoff.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 5 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_REV FIXTURE_WORLD FIXTURE_CONF NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
seed=$(realpath "$3")
config=$(realpath "$4")
mkdir "$5"
out=$(realpath "$5")
game="$out/games/luanttd"; m="$game/mods/luanttd_core"
mkdir -p "$game" "$out/home"
cp game.conf "$game/"
if ! cp -al mods "$game/" 2>/dev/null; then
  rm -rf "$game/mods"
  cp -a mods "$game/"
fi
python3 - "$m/init.lua" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
match="  authority.start(cap,Sim.W,Sim.H)\nend"
assert source.count(match)==1
source=source.replace(match,'''  local start=core.get_us_time()
  authority.start(cap,Sim.W,Sim.H)
  core.log("action",("OWNER_BOOT starting %dx%d host_heap=%.2f dense=%d"):format(
    Sim.W,Sim.H,collectgarbage("count")/1024,#S.tiles))
  local function report()
    if authority.status()~="owned" then core.after(.05,report);return end
    core.log("action",("OWNER_BOOT ready ms=%.2f host_heap=%.2f dense=%d"):format(
      (core.get_us_time()-start)/1000,collectgarbage("count")/1024,#S.tiles))
    core.after(.4,function() core.request_shutdown("Opening profile complete",false,0) end)
  end
  core.after(.05,report)
end''')
new=p.with_suffix(".next");new.write_text(source);new.replace(p)
PY
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for side in old1 new1 new2 old2; do
  path=mods/luanttd_core/campaign_worker_session.lua
  if [[ "$side" == old* ]]; then git show "$base:$path" > "$m/session.next"; else cp "$path" "$m/session.next"; fi
  mv "$m/session.next" "$m/campaign_worker_session.lua"
  w="$out/$side";mkdir "$w"
  cp "$seed/luanttd-campaign-owner.chk" "$seed/world.mt" "$w/"
  sed -E '/^[[:space:]]*(port|bind_address|server_announce)[[:space:]]*=/d' "$config" > "$w/conf"
  printf '\nport = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44555}" >> "$w/conf"
  "$server" --world "$w" --gameid luanttd --config "$w/conf" --logfile '' > "$w/log" 2>&1 &
  pid=$!
  trap 'kill -INT "$pid" 2>/dev/null || true' EXIT
  for _ in {1..600}; do
    if grep -q 'OWNER_BOOT ready' "$w/log"; then
      grep -E 'VmHWM|VmRSS' "/proc/$pid/status" > "$w/rss"
      break
    fi
    kill -0 "$pid" 2>/dev/null || { tail -50 "$w/log";exit 1; }
    sleep .07
  done
  test -s "$w/rss" || { tail -50 "$w/log";exit 1; }
  wait "$pid";trap - EXIT
  echo "== $side =="
  grep 'OWNER_BOOT' "$w/log"
  if [[ "$side" == new* ]];then grep -q 'OWNER_BOOT starting .* dense=0' "$w/log";fi
  ! grep -q 'ERROR\[' "$w/log"
  cat "$w/rss"
done
