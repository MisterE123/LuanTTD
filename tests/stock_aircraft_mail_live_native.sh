#!/usr/bin/env bash
# Real worker, fresh SQLite world, actual airfield and town simulation.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-aircraft-mail-worker.XXXXXX")
echo "Aircraft Mail worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp tests/stock_aircraft_mail_live_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40021}
for phase in start reload final confirm; do
  printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
  printf '%s\n' "$phase" > "$out/world/qa-airmail-phase.txt"
  timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -80 "$out/$phase.log";exit 1;
  }
  case "$phase" in
    start) expected="AIR_MAIL_NATIVE_SAVED " ;;
    reload) expected=AIR_MAIL_NATIVE_PENDING ;;
    final) expected=AIR_MAIL_NATIVE_PASS ;;
    confirm) expected=AIR_MAIL_NATIVE_CONFIRMED ;;
  esac
  grep "$expected" "$out/$phase.log"
done
