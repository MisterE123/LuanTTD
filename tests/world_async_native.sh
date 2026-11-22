#!/usr/bin/env bash
# Isolate all native worker evidence in a new private directory.
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
mod="$out/games/worldasync/mods/bayline"
mkdir -p "$mod/openttd" "$out/world" "$out/home"
printf 'title = Authoritative World Worker Probe\n' > "$out/games/worldasync/game.conf"
printf 'name = bayline\n' > "$mod/mod.conf"
cp mods/bayline/{world_storage,world_async,world_async_protocol,world_async_worker,terrain_word}.lua "$mod/"
cp mods/bayline/openttd/{slope,terrain}.lua "$mod/openttd/"
cp tests/world_async_native.lua "$mod/init.lua"
printf 'gameid = worldasync\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39671}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 30 "$server" --config "$out/server.conf" --world "$out/world" --gameid worldasync --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep 'LUANTTD WORLD ASYNC TERRAIN PASS' "$out/server.log" || { cat "$out/server.log";exit 1; }
if grep -E 'ERROR\[' "$out/server.log"; then exit 1; fi
