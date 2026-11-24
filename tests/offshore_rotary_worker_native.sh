#!/usr/bin/env bash
# Real worker, fresh SQLite world and offshore Tricario.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-offshore-rotary-worker.XXXXXX")
echo "Tricario offshore worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp tests/offshore_rotary_worker_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40004}
for phase in start reload; do
  printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\nluanttd_qa_rotary_field = %s\n' "$port" "$port" "${LUANTTD_QA_ROTARY_FIELD:-country}" > "$out/server.conf"
  printf 'luanttd_qa_rotary_model = %s\n' "${LUANTTD_QA_ROTARY_MODEL:-253}" >> "$out/server.conf"
  timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -80 "$out/$phase.log";exit 1;
  }
  if [[ $phase == start ]]; then expected=OFFSHORE_ROTARY_NATIVE_SAVED; else expected=OFFSHORE_ROTARY_NATIVE_PASS; fi
  grep "$expected" "$out/$phase.log"
done
