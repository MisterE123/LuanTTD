#!/usr/bin/env bash
set -euo pipefail
# Paired stock routing benchmark; no user world is opened.
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2;exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
rev=$2
mkdir "$3"
out=$(realpath "$3")
m="$out/games/roadbench/mods/luanttd_core"
mkdir -p "$m" "$out/home" "$out/world"
cp -l mods/luanttd_core/*.lua "$m/" 2>/dev/null || cp mods/luanttd_core/*.lua "$m/"
cp -al mods/luanttd_core/openttd "$m/" 2>/dev/null || cp -a mods/luanttd_core/openttd "$m/"
git show "$rev:mods/luanttd_core/openttd/yapf_road_follow.lua" >"$m/old_follow.lua"
git show "$rev:mods/luanttd_core/openttd/yapf_road_cost.lua" >"$m/old_cost.lua"
git show "$rev:mods/luanttd_core/road_yapf_board.lua" >"$m/old_board.lua"
git show "$rev:mods/luanttd_core/sim.lua" >"$m/old_sim.lua"
git show "$rev:mods/luanttd_core/openttd/yapf_road_search.lua" >"$m/old_search.lua"
cp tests/road_yapf_keys_perf_native.lua "$out/init.lua"
mv "$out/init.lua" "$m/init.lua"
echo 'title = Road YAPF key benchmark' > "$out/games/roadbench/game.conf"
echo 'name = luanttd_core' > "$m/mod.conf"
printf 'gameid = roadbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
export HOME="$(realpath "$out/home")" LUANTI_GAME_PATH="$(realpath "$out/games")" MINETEST_GAME_PATH="$(realpath "$out/games")"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44419}" > "$out/conf"
timeout 100 "$server" --world "$out/world" --config "$out/conf" --gameid roadbench --logfile '' > "$out/log" 2>&1 || { tail -65 "$out/log"; exit 1; }
grep 'YAPF NATIVE' "$out/log"
