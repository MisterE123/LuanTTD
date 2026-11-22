#!/usr/bin/env bash
# The probe runs in a disposable game and sends its snapshot into an actual async VM.
set -euo pipefail
cd "$(dirname "$0")/.."
server="${1:-luantiserver}"
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
port=39265
if [[ $# -gt 1 ]]; then port="$2"; fi
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mod="$tmp/games/storageprobe/mods/storageprobe"
mkdir -p "$mod" "$tmp/world" "$tmp/home"
printf 'title = World storage async probe\n' > "$tmp/games/storageprobe/game.conf"
printf 'name = storageprobe\n' > "$mod/mod.conf"
cp mods/luanttd_core/world_storage.lua "$mod/"
cp tests/world_storage_native.lua "$mod/init.lua"
printf 'gameid = storageprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$tmp/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$tmp/server.conf"
export HOME="$tmp/home" LUANTI_GAME_PATH="$tmp/games" MINETEST_GAME_PATH="$tmp/games"
if ! timeout 25 "$server" --config "$tmp/server.conf" --world "$tmp/world" --gameid storageprobe --logfile '' > "$tmp/server.log" 2>&1; then
  cat "$tmp/server.log"
  exit 1
fi
grep 'LUANTTD WORLD STORAGE ASYNC PASS' "$tmp/server.log" || { cat "$tmp/server.log"; exit 1; }
if grep -E 'ERROR\[' "$tmp/server.log"; then exit 1; fi
