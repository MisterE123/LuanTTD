#!/usr/bin/env bash
# Actual native campaign with the separate raised coastal seed and command UI.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/luantiserver /private/new-evidence-directory" >&2
  exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
out=$2
mkdir "$out"
out=$(realpath "$out")
game="$out/games/luanttd"
mkdir -p "$game/mods" "$out/world" "$out/home"
cp game.conf settingtypes.txt "$game/"
cp -r mods/luanttd_core "$game/mods/"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
cat tests/water_flood_native_append.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-39708}
for phase in SAVE RESTORE; do
  printf 'port = %d\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%d\nbayline_seed = 1751\nbayline_scenario = coastal\nbayline_water_flood_native_phase = %s\n' "$port" "$port" "$phase" > "$out/server.conf"
  if ! timeout 35 "$server" --config "$out/server.conf" --world "$out/world" --gameid luanttd --logfile '' >"$out/$phase.log" 2>&1; then
    cat "$out/$phase.log";exit 1
  fi
  grep "COASTAL LANDSCAPING NATIVE $phase" "$out/$phase.log" || { cat "$out/$phase.log";exit 1; }
  if grep -E 'ERROR\[' "$out/$phase.log"; then exit 1; fi
  [[ -s "$out/world/mod_storage.sqlite" ]]
done
