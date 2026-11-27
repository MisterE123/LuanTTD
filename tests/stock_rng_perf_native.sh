#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
game="$out/games/rngbench"
m="$game/mods/luanttd_core"
mkdir -p "$m" "$out/home" "$out/world"
printf 'title = Stock RNG benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = rngbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
git show "$2:mods/luanttd_core/station_rating_runtime.lua" > "$m/baseline.lua"
cp mods/luanttd_core/station_rating_runtime.lua tests/stock_rng_rc1_vectors.lua "$m/"
cp tests/stock_rng_perf_native.lua "$m/init.lua"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44348}" > "$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 40 "$server" --gameid rngbench --world "$out/world" --config "$out/conf" --logfile '' > "$out/log" 2>&1 ||
  { tail -35 "$out/log";exit 1; }
grep 'RNG PERF' "$out/log"
! grep -q 'ERROR\[' "$out/log"
