#!/usr/bin/env bash
# Opt-in native comparison of stock ship route work, not a frame-rate test.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1; if [[ $server == */* ]]; then server=$(realpath "$server");fi
base=$2
mkdir "$3"
d=$(realpath "$3")
g="$d/games/followbench";m="$g/mods/luanttd_core"
mkdir -p "$m" "$d/home" "$d/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
git show "$base:mods/luanttd_core/openttd/ship_follow.lua" >"$m/old_follow.lua"
git show "$base:mods/luanttd_core/openttd/ship_yapf.lua" >"$m/old_yapf.lua"
git show "$base:mods/luanttd_core/openttd/yapf_road_search.lua" >"$m/old_search.lua"
cp tests/ship_yapf_perf_native.lua "$m/init.lua"
printf 'gameid = followbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$d/world/world.mt"
printf 'name = luanttd_core\n' >"$m/mod.conf"
printf 'title = Native stock ship path profile\n' >"$g/game.conf"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44405}" >"$d/conf"
export HOME="$d/home" LUANTI_GAME_PATH="$d/games" MINETEST_GAME_PATH="$d/games"
if ! timeout "${LUANTTD_BENCH_TIMEOUT:-90}" "$server" --world "$d/world" --gameid followbench --config "$d/conf" --logfile '' >"$d/log" 2>&1; then
  tail -40 "$d/log";exit 1
fi
grep 'WATER FOLLOW' "$d/log"
! grep -E 'ERROR\[' "$d/log"
