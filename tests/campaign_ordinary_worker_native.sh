#!/usr/bin/env bash
# Regular generated campaign hands off authority in a disposable native test.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-ordinary-owner.XXXXXX")
echo "Native ordinary owner evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -a -l mods "$game/" 2>/dev/null || { mkdir -p "$game/mods"; cp -a mods/. "$game/mods/"; }
if [[ -n ${BAYLINE_NATIVE_ASSET_MOD:-} ]]; then
  # Child worktree can be sparse. Preserve its new icons and link the
  # unchanged game assets; never write into a linked file.
  for folder in models textures; do
    mkdir -p "$game/mods/luanttd_core/$folder"
    for file in "$BAYLINE_NATIVE_ASSET_MOD/$folder/"*; do
      if [[ ! -e "$game/mods/luanttd_core/$folder/${file##*/}" ]]; then
        cp -al "$file" "$game/mods/luanttd_core/$folder/" 2>/dev/null || cp -a "$file" "$game/mods/luanttd_core/$folder/"
      fi
    done
  done
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv -f "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
cat tests/campaign_ordinary_worker_native.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_generated_map_width = 64\nbayline_generated_map_depth = 64\nbayline_generated_relief = 0\nbayline_generated_coasts = 0\n' "${BAYLINE_NATIVE_PORT:-39890}" > "$out/default.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"

if ! timeout 35 luantiserver --world "$out/world" --config "$out/default.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep 'PASS NATIVE ORDINARY HANDOFF' "$out/server.log" || { cat "$out/server.log"; exit 1; }
grep 'PASS NATIVE ORDINARY WORKER BUILD' "$out/server.log"
grep 'PASS NATIVE DEFAULT MIXED RAIL CAPABILITY' "$out/server.log"
grep 'PASS NATIVE PROJECTED PAINTER' "$out/server.log"
grep 'PASS NATIVE PROJECTED ROLLING STOCK' "$out/server.log"
grep 'PASS NATIVE PROJECTED TRAIN FORM' "$out/server.log"
grep 'PASS NATIVE PROJECTED HOTBAR BUILD' "$out/server.log"
grep 'PASS NATIVE WORKER DURABILITY' "$out/server.log"
grep 'PASS NATIVE WORKER NEWSPAPER' "$out/server.log"
! grep 'ERROR\[' "$out/server.log"
