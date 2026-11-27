#!/usr/bin/env bash
# Compare stock ferry movement across real coastal updates.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server");fi
base=$2
mkdir "$3"
o=$(realpath "$3")
cd "$(dirname "$0")/.."
g="$o/games/shiptide";m="$g/mods/luanttd_core"
mkdir -p "$m" "$o/home" "$o/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
cp tests/ship_checked_leg_perf_native.lua "$m/init.lua"
git show "$base:mods/luanttd_core/ship_preview_run.lua" > "$m/ship_preview_baseline.lua"
printf 'title = Native ship regions tide probe\n' > "$g/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = shiptide\nbackend = sqlite3\n' > "$o/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44413}" > "$o/conf"
export HOME="$o/home" LUANTI_GAME_PATH="$o/games" MINETEST_GAME_PATH="$o/games"
timeout 120 "$server" --world "$o/world" --config "$o/conf" --gameid shiptide --logfile '' > "$o/log" 2>&1 || { tail -40 "$o/log";exit 1; }
test "$(grep -c 'NATIVE LIVE SHIP LEGS' "$o/log")" = 4
grep 'NATIVE LIVE SHIP LEGS' "$o/log"
! grep -q 'ERROR\[' "$o/log"
