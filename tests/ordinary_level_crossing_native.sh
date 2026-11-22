#!/usr/bin/env bash
# Real Luanti Road toolbar callback / crossing mesh test. Only Lua sources
# are copied. Shared immutable asset files are hard-linked, not replicated.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
assets=$(realpath "${BAYLINE_NATIVE_ASSET_MOD:-mods/luanttd_core}")
out=$(mktemp -d "${TMPDIR:-$PWD}/luanttd-ordinary-crossing.XXXXXX")
game="$out/games/luanttd"
mkdir -p "$game/mods/luanttd_core" "$out"/{world,home,cache}
cp game.conf "$game/"
for f in mods/luanttd_core/*; do
  case ${f##*/} in models|textures|sounds|init.lua) ;; *) cp -r "$f" "$game/mods/luanttd_core/";; esac
done
for name in models textures sounds; do
  if [[ -d "$assets/$name" ]]; then cp -al "$assets/$name" "$game/mods/luanttd_core/"; fi
done
cat mods/luanttd_core/init.lua tests/ordinary_level_crossing_native.lua > "$game/mods/luanttd_core/init.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
port=${BAYLINE_NATIVE_PORT:-44873}
cat > "$out/server.conf" <<CONF
port = $port
prometheus_listener_address = 127.0.0.1:$port
bind_address = 127.0.0.1
server_announce = false
bayline_rail_crossing_preview = true
bayline_offline_economy = false
CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
echo "Native ordinary crossing proof: $out"
timeout 25s "${BAYLINE_LUANTI_SERVER:-luantiserver}" --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/log" 2>&1 || { cat "$out/log"; exit 1; }
grep ORDINARY_LEVEL_CROSSING_UI_PASS "$out/log"
