#!/usr/bin/env bash
# Intentionally kill only the server children of a new disposable test.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-$PWD}/luanttd-paid-process-crash.XXXXXX")
echo "Native acknowledged construction crash evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
mod="$game/mods/luanttd_core"
cp mods/luanttd_core/init.lua "$out/fixture-init.lua"
printf '\n' >>"$out/fixture-init.lua"
cat tests/campaign_paid_process_crash_native.lua >>"$out/fixture-init.lua"
mv "$out/fixture-init.lua" "$mod/init.lua"
printf 'return function() return {local_replay=true} end\n' >"$out/fixture-layout.lua"
mv "$out/fixture-layout.lua" "$mod/qa_layout.lua"
# Only the disposable worker is instrumented. In the abort phase it
# has already mutated authoritative memory but has not written the
# checkpoint or acknowledged the action.
sed '/r=A.command(q.player,q.command)/a\
          if r.ok and q.command.kind=="road_commit" and core.settings:get("luanttd_qa_paid_crash_phase")=="abort" then\
            core.log("action","PAID_PROCESS_CRASH_UNPUBLISHED")\
            while true do core.ipc_poll(channel..":qa-no-writer",1000) end\
          end' "$mod/campaign_authority_worker.lua" >"$out/fixture-worker.lua"
mv "$out/fixture-worker.lua" "$mod/campaign_authority_worker.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
source tests/native_processes.sh
server=
trap 'native_stop_children "$server"' EXIT
port=${BAYLINE_NATIVE_PORT:-42637}
axis=${LUANTTD_QA_CRASH_AXIS:-64}
[[ $axis == 64 || $axis == 512 ]]
for phase in abort place remove verify; do
  log="$out/$phase.log"
  cat >"$out/native.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
server_map_save_interval = 600
bayline_generated_map_width = $axis
bayline_generated_map_depth = $axis
bayline_generated_relief = 0
bayline_generated_coasts = 0
luanttd_qa_paid_crash_phase = $phase
CONF
  if [[ $phase == verify ]]; then
    expected='PAID_PROCESS_CRASH_PASS'
  elif [[ $phase == abort ]]; then
    expected=PAID_PROCESS_CRASH_UNPUBLISHED
  else
    expected="PAID_PROCESS_CRASH_ACK $phase"
  fi
  luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile '' >"$log" 2>&1 &
  server=$!
  for _ in {1..225}; do
    if grep -q "$expected" "$log"; then break; fi
    kill -0 "$server" 2>/dev/null || break
    sleep .08
  done
  grep "$expected" "$log" || { tail -60 "$log"; exit 1; }
  if [[ $phase != verify ]]; then
    kill -KILL "$server"
  else
    # It requests a graceful engine shutdown after the last verification.
    for _ in {1..75}; do kill -0 "$server" 2>/dev/null || break; sleep .08; done
    ! kill -0 "$server" 2>/dev/null || { tail -60 "$log"; exit 1; }
  fi
  code=0
  wait "$server" 2>/dev/null || code=$?
  server=
  if [[ $phase == verify ]]; then
    test "$code" = 0
  else
    test "$code" = 137
    if [[ $axis == 512 ]]; then
      # The large fixture must actually exercise the new writer,
      # not accidentally pass through the general-format fallback.
      head -n 1 "$out/world/qa-paid-process-crash.chk" | grep -qx 'LUANTTD-WIDE-CAMPAIGN-4-RASTER'
    fi
  fi
  if grep -E 'ServerError|stack traceback' "$log"; then exit 1; fi
done
