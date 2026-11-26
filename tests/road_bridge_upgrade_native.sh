#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-bridge-upgrade.XXXXXX")
echo "Bridge upgrade worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp tests/road_bridge_upgrade_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40067}
for phase in start reopen; do
  printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nbind_address = 127.0.0.1\nserver_announce = false\nluanttd_qa_bridge_phase = %s\n' "$port" "$port" "$phase" > "$out/server.conf"
printf 'luanttd_qa_bridge_style = %s\n' "${BAYLINE_TEST_BRIDGE_STYLE:-9}" >> "$out/server.conf"
  timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || { tail -80 "$out/$phase.log";exit 1; }
done
grep AQUEDUCT_GROUND_NATIVE_PASS "$out/start.log"
grep BRIDGE_GROUND_CLEAR_NATIVE_PASS "$out/start.log"
grep BRIDGE_BULLDOZER_NATIVE_PASS "$out/start.log"
grep BRIDGE_UPGRADE_NATIVE_SAVED "$out/start.log"
grep BRIDGE_UPGRADE_NATIVE_PASS "$out/reopen.log"
