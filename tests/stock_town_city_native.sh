#!/usr/bin/env bash
# Native city artwork in a worker-owned ordinary generated game, isolated save.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-town.XXXXXX")
echo "Native city evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -a -l mods "$game/" 2>/dev/null || { mkdir -p "$game/mods"; cp -a mods/. "$game/mods/"; }
cp mods/luanttd_core/init.lua "$out/init.lua"
mv -f "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
cat tests/stock_town_city_native.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_generated_map_width = 64\nbayline_generated_map_depth = 64\nbayline_generated_relief = 0\nbayline_generated_coasts = 0\n' "${BAYLINE_NATIVE_PORT:-39895}" > "$out/default.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 34 luantiserver --world "$out/world" --config "$out/default.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1; then
  tail -60 "$out/server.log";exit 1
fi
grep STOCK_TOWN_CITY_NATIVE_OK "$out/server.log" || { tail -60 "$out/server.log"; exit 1; }
! grep 'ERROR\[' "$out/server.log"
