#!/usr/bin/env bash
# Bounded synthetic station distribution in the native Lua engine.
set -euo pipefail
[[ $# == 2 ]] || { echo "usage: $0 LUANTI_SERVER NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$2"
out=$(realpath "$2")
cd "$(dirname "$0")/.."
mod="$out/games/spatialbench/mods/luanttd_core"
mkdir -p "$mod" "$out/home" "$out/world"
echo 'title = Passenger station coverage benchmark' > "$out/games/spatialbench/game.conf"
echo 'name = luanttd_core' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/passenger_supply_spatial_bench.lua "$mod/init.lua"
echo 'gameid = spatialbench' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44108}" > "$out/conf"
export HOME="$out/home" MINETEST_GAME_PATH="$out/games" LUANTI_GAME_PATH="$out/games"
timeout 70 "$server" --world "$out/world" --config "$out/conf" --gameid spatialbench --logfile '' >"$out/log" 2>&1 ||
  { tail -50 "$out/log";exit 1; }
grep 'SPATIAL_PASSENGERS' "$out/log"
! grep 'ERROR\[' "$out/log"
