#!/usr/bin/env bash
set -euo pipefail
# Native worker benchmark for normal fixed-axis road and bend previews.
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1; if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$3"; out=$(realpath "$3")
game="$out/games/quotebench"; mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/home" "$out/world"
cp -l mods/luanttd_core/*.lua "$mod/" 2>/dev/null || cp mods/luanttd_core/*.lua "$mod/"
cp -al mods/luanttd_core/openttd "$mod/" 2>/dev/null || cp -a mods/luanttd_core/openttd "$mod/"
cp tests/road_quote_perf_native.lua "$out/init.lua"; mv "$out/init.lua" "$mod/init.lua"
git show "$2:mods/luanttd_core/campaign_road_construction.lua" >"$mod/baseline_road_construction.lua"
printf 'title = Native road quote benchmark\n' >"$game/game.conf"
printf 'name = luanttd_core\n' >"$mod/mod.conf"
printf 'gameid = quotebench\nbackend = sqlite3\nmod_storage_backend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' >"$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44431}" >"$out/conf"
timeout 100 "$server" --world "$out/world" --config "$out/conf" --gameid quotebench --logfile '' >"$out/log" 2>&1 || {
  tail -60 "$out/log"; exit 1;
}
grep 'QUOTE BENCH' "$out/log"
! grep -F 'ERROR[' "$out/log"
