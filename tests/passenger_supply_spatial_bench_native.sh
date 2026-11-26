#!/usr/bin/env bash
# Bounded synthetic station distributions in the native Lua engine.
set -euo pipefail
[[ $# == 2 || $# == 4 && ( $3 == --road-only || $3 == --shared-mail ) ]] ||
  { echo "usage: $0 LUANTI_SERVER NEW_OUTPUT_DIRECTORY [--road-only|--shared-mail BASELINE_REV]" >&2; exit 64; }
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
pattern=SPATIAL_PASSENGERS
if [[ $# == 4 && $3 == --shared-mail ]]; then
  git show "$4:mods/luanttd_core/road_mail_runtime.lua" > "$mod/baseline_mail.lua"
  cp tests/shared_mail_spatial_bench.lua "$mod/init.lua"
  pattern=MAIL_INDEX
elif [[ $# == 4 ]]; then
  git show "$4:mods/luanttd_core/town_passenger_runtime.lua" > "$mod/baseline_town.lua"
  cp tests/road_house_catchment_bench.lua "$mod/init.lua"
  pattern=ROAD_HOUSE_BENCH
else
  cp tests/passenger_supply_spatial_bench.lua "$mod/init.lua"
fi
echo 'gameid = spatialbench' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44108}" > "$out/conf"
export HOME="$out/home" MINETEST_GAME_PATH="$out/games" LUANTI_GAME_PATH="$out/games"
timeout 70 "$server" --world "$out/world" --config "$out/conf" --gameid spatialbench --logfile '' >"$out/log" 2>&1 ||
  { tail -50 "$out/log";exit 1; }
grep "$pattern" "$out/log"
! grep 'ERROR\[' "$out/log"
