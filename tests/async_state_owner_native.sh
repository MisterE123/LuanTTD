#!/usr/bin/env bash
# Real Luanti IPC affinity/actor probe, never opens an existing world.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/luantiserver NEW_OUTPUT_DIR" >&2;exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$2"
out=$(realpath "$2")
game="$out/games/ownerprobe"
mod="$game/mods/owner_probe"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Async State Owner Probe\n' > "$game/game.conf"
printf 'name = owner_probe\n' > "$mod/mod.conf"
cp mods/luanttd_core/world_storage.lua "$mod/"
cp tests/async_state_owner_probe.lua "$mod/init.lua"
printf 'gameid = ownerprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-39672}" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 15 "$server" --config "$out/server.conf" --world "$out/world" --gameid ownerprobe --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep 'PASS NATIVE ASYNC OWNER' "$out/server.log" || { cat "$out/server.log";exit 1; }
if grep -E 'ERROR\[' "$out/server.log"; then exit 1; fi
