#!/usr/bin/env bash
# Actual Luanti worker generation with no client/media dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/luantiserver NEW_OUTPUT_DIR" >&2;exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$2"
out=$(realpath "$2")
game="$out/games/generationprobe"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native Campaign Generation Probe\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
mkdir -p "$mod/models" "$mod/textures"
# The strict heavy-industry visual manifest requires every mounted layout.
cp mods/luanttd_core/models/bl_industry_{iron_mine,steel_mill,steel_mill_l1}_[0-9]_[0-9].obj "$mod/models/"
cp mods/luanttd_core/textures/bl_industry_{iron_mine,steel_mill,steel_mill_l1}_atlas.png "$mod/textures/"
rm "$mod/init.lua"
cp tests/campaign_generation_async_probe.lua "$mod/init.lua"
printf 'gameid = generationprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nbayline_generated_map_width = 128\nbayline_generated_map_depth = 64\nbayline_generated_rivers = 1\n' "${BAYLINE_NATIVE_PORT:-39673}" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 25 "$server" --config "$out/server.conf" --world "$out/world" --gameid generationprobe --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep 'PASS NATIVE GENERATION' "$out/server.log" || { cat "$out/server.log";exit 1; }
# The intentionally blocked atomic rename should be the only engine error.
grep -Eq 'ERROR\[AsyncWorker-[0-9]+\]: Failed to overwrite .*luanttd-prepared-campaign\.chk.*Is a directory' "$out/server.log"
if grep -E 'ERROR\[' "$out/server.log" |
   grep -Ev 'ERROR\[AsyncWorker-[0-9]+\]: Failed to overwrite .*luanttd-prepared-campaign\.chk.*Is a directory'; then exit 1; fi
