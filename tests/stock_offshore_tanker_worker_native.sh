#!/usr/bin/env bash
# Real worker, fresh SQLite world and offshore crude oil.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-offshore-tanker-worker.XXXXXX")
echo "Offshore tanker worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp tests/stock_offshore_tanker_worker_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40004}
for phase in start reload audit; do
  printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
  if [[ -n ${LUANTTD_QA_SUBSIDY_MULTIPLIER:-} ]]; then
    printf 'luanttd_qa_subsidy_multiplier = %s\n' "$LUANTTD_QA_SUBSIDY_MULTIPLIER" >> "$out/server.conf"
  fi
  timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -80 "$out/$phase.log";exit 1;
  }
  case "$phase" in
    start) expected=OFFSHORE_TANKER_NATIVE_SAVED ;;
    reload) expected=OFFSHORE_TANKER_NATIVE_PASS ;;
    audit) expected=OFFSHORE_TANKER_NATIVE_CONFIRMED ;;
  esac
  grep "$expected" "$out/$phase.log"
  if [[ $phase == reload && -n ${LUANTTD_QA_SUBSIDY_MULTIPLIER:-} ]]; then
    grep OFFSHORE_SUBSIDY_PAYOUT "$out/$phase.log"
  fi
done
