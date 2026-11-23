#!/usr/bin/env bash
# Native default world with no game settings, actual coastal physics, and
# explicit scenario/restart precedence on disposable SQLite worlds.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-default-terrain.XXXXXX")
echo "Native default terrain logs: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache"
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/" || cp -R "$src/mods/." "$game/mods/"
# Never append to a file hard-linked to the original game.
install -m 644 "$src/mods/luanttd_core/init.lua" "$out/init"
mv "$out/init" "$game/mods/luanttd_core/init.lua"
# Exercise the actual setup schema, not feature/config flags.
python3 - "$game/mods/luanttd_core/init.lua" <<'PROBE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();k=s.index("local settings=core.settings")
p.write_text(s[:k]+"""
local probe_scenario=({farm="farm",oil="oil",coast="coastal",south="south_coast"})[core.get_worldpath():match("[^/]+$")]
if probe_scenario then
  local setup=dofile(mod.."/world_setup.lua")
  local choices=setup.defaults(core.settings)
  choices.scenario=probe_scenario
  storage:set_string(setup.storage_key,core.write_json(choices))
end
"""+s[k:])
PROBE
printf '\n' >> "$game/mods/luanttd_core/init.lua"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
cat tests/default_stock_terrain_append.lua >> "$game/mods/luanttd_core/init.lua"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-42109}
run() {
  local world=$1 log=$2; shift 2
  mkdir -p "$out/$world"
  printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/$world/world.mt"
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$out/native.conf"
  for setting in "$@"; do
    if [[ $setting == *=* ]]; then printf '%s\n' "$setting"; else printf '%s = true\n' "$setting"; fi
  done >> "$out/native.conf"
  if ! timeout 45 luantiserver --world "$out/$world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/$log.log" 2>&1; then
    cat "$out/$log.log";exit 1
  fi
  grep "DEFAULT STOCK TERRAIN $world" "$out/$log.log"
  ! grep -E 'ERROR\[' "$out/$log.log"
}
if [[ ${BAYLINE_NATIVE_ONLY_ARCHIPELAGO:-0} == 1 ]]; then
  run archipelago archipelago 'bayline_seed = 23' 'bayline_generated_sea = 3'
  exit
fi
run plain launch
run plain launch-restore "bayline_scenario = coastal"
run obsolete obsolete luanttd_qa_coastal_layout luanttd_qa_plain_layout "bayline_stock_generated_world = false" \
  bayline_stock_coastal_flood bayline_road_farm_preview bayline_road_oil_preview \
  bayline_ship_coal_coastal_scenario bayline_development_tools
run invalid invalid "bayline_scenario = nonsense" bayline_stock_coastal_flood
run all_on all_on \
  'bayline_stock_workbenches = false' \
  'bayline_bridge_construction_preview = false' \
  'bayline_rail_owned_preview = false' \
  'bayline_rail_block_preview = false' \
  'bayline_electric_rail_preview = false' \
  'bayline_rail_span_preview = false' \
  'bayline_rail_crossing_preview = false' \
  'bayline_road_oneway_preview = false' \
  'bayline_ship_preview = false' \
  'bayline_tram_preview = false' \
  'bayline_airport_preview = false' \
  'bayline_preview_paid_ferry = false' \
  'bayline_preview_paid_rail = false' \
  'bayline_preview_paid_air = false' \
  'bayline_stock_bus_catalog = false' \
  'bayline_road_bay_preview = false' \
  'bayline_road_timber_preview = false' \
  'bayline_road_farm_preview = false' \
  'bayline_road_oil_preview = false' \
  'bayline_rail_oil_preview = false' \
  'bayline_preview_coal_industry = false' \
  'bayline_mail_preview = false' \
  'bayline_generated_mixed_freight = false' \
  'bayline_stock_town_growth = false' \
  'bayline_offline_economy = false' \
  'bayline_ship_coal_preview = false' 'bayline_scenario = oil'
run farm farm
run oil oil
run coast coast
run south south
