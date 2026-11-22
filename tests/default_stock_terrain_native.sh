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
game="$out/games/bayline"
mkdir -p "$game" "$out/home" "$out/cache"
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/" || cp -R "$src/mods/." "$game/mods/"
# Never append to a file hard-linked to the original game.
install -m 644 "$src/mods/bayline/init.lua" "$out/init"
mv "$out/init" "$game/mods/bayline/init.lua"
printf '\n' >> "$game/mods/bayline/init.lua"
cat tests/default_stock_terrain_append.lua >> "$game/mods/bayline/init.lua"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-42109}
run() {
  local world=$1 log=$2; shift 2
  mkdir -p "$out/$world"
  printf 'gameid = bayline\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/$world/world.mt"
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$out/native.conf"
  for setting in "$@"; do
    if [[ $setting == *=* ]]; then printf '%s\n' "$setting"; else printf '%s = true\n' "$setting"; fi
  done >> "$out/native.conf"
  if ! timeout 45 luantiserver --world "$out/$world" --config "$out/native.conf" --gameid bayline --logfile "" >"$out/$log.log" 2>&1; then
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
run plain launch-restore bayline_harbor_valley
run harbor harbor bayline_fixture_harbor_valley
run harbor harbor-restore
run obsolete obsolete bayline_harbor_valley "bayline_stock_generated_world = false" \
  bayline_stock_coastal_flood bayline_road_farm_preview bayline_road_oil_preview \
  bayline_ship_coal_coastal_scenario bayline_development_tools
run invalid invalid "bayline_scenario = nonsense" bayline_stock_coastal_flood
run farm farm "bayline_scenario = farm"
run oil oil "bayline_scenario = oil"
run coast coast "bayline_scenario = coastal"
run south south "bayline_scenario = south_coast"
run lab lab bayline_development_tools bayline_fixture_legacy_layout
