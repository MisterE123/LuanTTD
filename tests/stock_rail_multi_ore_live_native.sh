#!/usr/bin/env bash
# Real worker, fresh SQLite world, actual industrial rail and town simulation.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-multi-ore-worker.XXXXXX")
echo "Two-hopper ore worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp tests/stock_rail_multi_ore_live_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40021}
for phase in start reload finish confirm; do
  printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
  printf '%s\n' "$phase" > "$out/world/qa-multi-ore-phase.txt"
  timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -80 "$out/$phase.log";exit 1;
  }
  case "$phase" in
    start) expected="RAIL_MULTI_ORE_SAVED " ;;
    reload) expected=RAIL_MULTI_ORE_PENDING ;;
    finish) expected=RAIL_MULTI_ORE_PASS ;;
    confirm) expected=RAIL_MULTI_ORE_CONFIRMED ;;
  esac
  grep "$expected" "$out/$phase.log"
done
