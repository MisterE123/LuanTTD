#!/usr/bin/env bash
# Real road/town market, clocks, finance and growth on dedicated Luanti workers.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/luantiserver NEW_OUTPUT_DIR" >&2;exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$2"
out=$(realpath "$2")
game="$out/games/tickprobe"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native Campaign Tick Ownership Probe\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
rm "$mod/init.lua"
cp tests/campaign_tick_worker_probe.lua "$mod/init.lua"
cp tests/town_growth_live_fixture.lua "$mod/"
cp tests/rail_paid_runtime.lua "$mod/rail_paid_runtime_fixture.lua"
printf 'gameid = tickprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-39674}" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 25 "$server" --config "$out/server.conf" --world "$out/world" --gameid tickprobe --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep 'PASS NATIVE WORKER CAMPAIGN' "$out/server.log" || { cat "$out/server.log";exit 1; }
grep 'PASS NATIVE FOUR-MODE ECONOMY' "$out/server.log" || { cat "$out/server.log";exit 1; }
grep 'PASS NATIVE OWNER MAILBOX' "$out/server.log" || { cat "$out/server.log";exit 1; }
if grep -E 'ERROR\[' "$out/server.log"; then exit 1; fi
