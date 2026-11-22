#!/usr/bin/env bash
# Typed bounded river raster proof on a real Luanti worker, then SQLite reload.
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
mod="$out/games/riverworker/mods/bayline"
mkdir -p "$mod/openttd" "$out/world" "$out/home"
printf 'title = Typed River Worker Probe\n' > "$out/games/riverworker/game.conf"
printf 'name = bayline\n' > "$mod/mod.conf"
cp mods/bayline/{world_storage,world_async,world_async_protocol,world_async_worker,terrain_word,terrain_stream}.lua "$mod/"
cp mods/bayline/openttd/{slope,terrain,terragenesis,river_worldgen}.lua "$mod/openttd/"
cp tests/terrain_river_fixture.lua "$mod/fixture.lua"
cp tests/terrain_river_stream_native.lua "$mod/init.lua"
printf 'gameid = riverworker\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39761}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for phase in SAVE RESTORE; do
  if ! timeout 30 "$server" --config "$out/server.conf" --world "$out/world" \
    --gameid riverworker --logfile '' > "$out/$phase.log" 2>&1; then
    cat "$out/$phase.log";exit 1
  fi
  grep "LUANTTD RIVER ASYNC $phase PASS" "$out/$phase.log" || { cat "$out/$phase.log";exit 1; }
  if grep -E 'ERROR\[' "$out/$phase.log"; then exit 1; fi
done
grep 'LUANTTD RIVER ASYNC STALE PASS' "$out/SAVE.log"
