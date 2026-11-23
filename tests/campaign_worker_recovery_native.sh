#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-worker-recovery.XXXXXX")
echo "Native worker recovery evidence: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp "$src/game.conf" "$game/"
cp -R "$src/mods" "$game/"
mod="$game/mods/luanttd_core"
printf 'return function() return {local_replay=true} end\n' > "$mod/qa_layout.lua"
printf '\n' >> "$mod/init.lua"
cat tests/campaign_worker_recovery_native.lua >> "$mod/init.lua"
crash=${LUANTTD_QA_SIMULATE_CRASH:-true}
if [[ "$crash" == true ]]; then
  # The disposable fixture injects a genuine Lua failure into the live
  # worker only. Never add a debug crash command to the distributed game.
  sed -i '/elseif q.kind=="checkpoint" then/i\        elseif q.kind=="qa_crash" then error("QA_WORKER_CRASH")' "$mod/campaign_authority_worker.lua"
fi
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42628}
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nprometheus_listener_address = 127.0.0.1:%s\nqa_worker_crash = %s\n' "$port" "$port" "$crash" > "$out/native.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 32 luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep WORKER_QUIET_HOST_PASS "$out/server.log" || { cat "$out/server.log";exit 1; }
if [[ "$crash" == true ]]; then grep WORKER_IN_PLACE_RECOVERY_PASS "$out/server.log" || { cat "$out/server.log";exit 1; };fi
! grep -E 'ServerError|stack traceback' "$out/server.log"
