#!/usr/bin/env bash
# Native async river presentation A/B: both worlds use actual RC1 floods.
set -euo pipefail
[[ $# == 2 ]] || { echo "usage: $0 LUANTI_SERVER NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server");fi
mkdir "$2"
o=$(realpath "$2")
cd "$(dirname "$0")/.."
g="$o/games/riverprobe"
m="$g/mods/luanttd_core"
mkdir -p "$m" "$o/home" "$o/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
cp tests/river_tide_perf_native.lua "$m/init.lua"
printf 'title = Native stock river direction replay\n' >"$g/game.conf"
printf 'name = luanttd_core\n' >"$m/mod.conf"
printf 'gameid = riverprobe\nbackend = sqlite3\n' > "$o/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44390}" > "$o/conf"
export HOME="$o/home" LUANTI_GAME_PATH="$o/games" MINETEST_GAME_PATH="$o/games"
timeout 60 "$server" --world "$o/world" --config "$o/conf" --gameid riverprobe --logfile '' >"$o/log" 2>&1 || { tail -40 "$o/log";exit 1; }
test "$(grep -c 'NATIVE RIVER 73 REAL TIDES' "$o/log")" = 4
grep 'NATIVE RIVER 73 REAL TIDES' "$o/log"
! grep -q 'ERROR\[' "$o/log"
