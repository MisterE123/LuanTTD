#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]]
out=$1
mkdir "$out"
out=$(realpath "$out")
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp -r "${BAYLINE_NATIVE_EXACT_GAME:-.}"/game.conf "${BAYLINE_NATIVE_EXACT_GAME:-.}"/mods "$game/"
# Preserve the narrow route fixture's exact seeded occupancy and finance
# goldens without altering the ordinary catalogue. The city suite exercises
# all enabled parcels on the actual worker-owned default game.
art="$game/mods/luanttd_core/stock_town_art.lua"
if [[ -f "$art" ]]; then
  cp tests/fixed_parcel_footprint.lua "$game/mods/luanttd_core/fixed_parcel_footprint.lua"
  sed 's|^return Art$|return dofile((debug.getinfo(1,"S").source:sub(2):match("^(.+/)")).."fixed_parcel_footprint.lua")(Art)|' "$art" > "$out/fixed-stock-art"
  mv "$out/fixed-stock-art" "$art"
fi
printf '\n' >> "$game/mods/luanttd_core/init.lua"
if [[ ${BAYLINE_NATIVE_GENERATED_SCALE:-0} == 1 ]]; then
  cat tests/stock_generated_scale_append.lua >> "$game/mods/luanttd_core/init.lua"
elif [[ ${BAYLINE_NATIVE_RIVER_LANDSCAPING:-0} == 1 ]]; then
  cat tests/river_landscaping_native_append.lua >> "$game/mods/luanttd_core/init.lua"
elif [[ ${BAYLINE_NATIVE_GENERATED_RIVER:-0} == 1 ]]; then
  cat tests/stock_generated_river_append.lua >> "$game/mods/luanttd_core/init.lua"
else
  cat tests/stock_generated_native_append.lua >> "$game/mods/luanttd_core/init.lua"
fi
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
 tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
 export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
port=${BAYLINE_NATIVE_PORT:-42855}
for phase in save restore; do
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nbayline_stock_generated_world = %s\nbayline_native_generation_phase = %s\nbayline_offline_economy = false\n' "$port" "$([[ $phase = save ]] && echo true || echo false)" "$phase" > "$out/server.conf"
  if [[ ${BAYLINE_NATIVE_GENERATED_COAL_ONLY:-0} == 1 ]]; then
    printf 'bayline_native_generation_coal_only = true\n' >> "$out/server.conf"
    [[ $phase = restore ]] || printf 'bayline_generated_mixed_freight = false\n' >> "$out/server.conf"
  elif [[ $phase = restore ]]; then
    # Changing the setting after startup must not regenerate the geography.
    printf 'bayline_generated_mixed_freight = false\n' >> "$out/server.conf"
  fi
  if [[ ${BAYLINE_NATIVE_GENERATED_RIVER:-0} == 1 || ${BAYLINE_NATIVE_RIVER_LANDSCAPING:-0} == 1 ]]; then
    printf 'bayline_generated_rivers = %s\nbayline_generated_min_river_length = 2\n' "$([[ $phase = save ]] && echo 3 || echo 0)" >> "$out/server.conf"
  fi
  if [[ ${BAYLINE_NATIVE_GENERATED_SCALE:-0} == 1 ]]; then
    printf 'bayline_generated_map_size = %s\nbayline_generated_relief = 3\nbayline_generated_rivers = 1\nbayline_generated_mixed_freight = true\n' \
      "$([[ $phase = save ]] && echo 128 || echo 64)" >> "$out/server.conf"
  fi
  timeout 35 luantiserver --config "$out/server.conf" --world "$out/world" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || { tail -40 "$out/$phase.log"; exit 1; }
  grep "STOCK GENERATED NATIVE $phase" "$out/$phase.log"
  if grep -E 'ERROR\[' "$out/$phase.log"; then exit 1; fi
  [[ -s "$out/world/mod_storage.sqlite" ]]
done
