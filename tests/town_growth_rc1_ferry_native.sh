#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rc1-ferry-worker.XXXXXX")
echo "Ferry worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods "$game/"
cp tests/town_growth_rc1_ferry_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-43386}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
if [[ ${1:-} == mixed ]]; then
  printf 'luanttd_qa_join_bus_dock = true\n' >> "$out/server.conf"
fi
if [[ ${1:-} == hub ]]; then
  printf 'luanttd_qa_coastal_hub = true\n' >> "$out/server.conf"
fi
for phase in SERVICE REOPEN; do
  timeout 120 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -80 "$out/$phase.log";exit 1;
  }
  grep "NATIVE RC1 FERRY $phase" "$out/$phase.log"
done
