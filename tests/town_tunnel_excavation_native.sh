#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-town-tunnel.XXXXXX")
game="$w/games/luanttd"
mkdir -p "$game" "$w/home" "$w/world"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
# Replace only the disposable test game's init, never the checkout.
cp tests/town_tunnel_excavation.lua "$w/init.lua"
mv "$w/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$w/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40068}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$w/server.conf"
export HOME="$w/home" LUANTI_GAME_PATH="$w/games" MINETEST_GAME_PATH="$w/games"
timeout 90 luantiserver --world "$w/world" --config "$w/server.conf" --gameid luanttd --logfile '' >"$w/native.log" 2>&1 || {
  tail -80 "$w/native.log"
  exit 1
}
grep 'TOWN_TUNNEL_EXCAVATION_NATIVE_PASS' "$w/native.log"
