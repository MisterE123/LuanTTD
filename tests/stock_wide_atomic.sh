#!/usr/bin/env bash
# Use only a newly created test world. The crash phase is intentionally killed.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$1
mkdir "$out"
out=$(realpath "$out")
game="$out/games/bayline"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp -r "${BAYLINE_NATIVE_EXACT_GAME:-.}"/game.conf "${BAYLINE_NATIVE_EXACT_GAME:-.}"/mods "$game/"
printf '\n' >> "$game/mods/bayline/init.lua"
cat tests/stock_wide_atomic_append.lua >> "$game/mods/bayline/init.lua"
printf 'gameid = bayline\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
write_config() {
  local phase=$1 new=false size=64
  if [[ $phase == baseline ]]; then new=true;size=128; fi
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nserver_map_save_interval = 600\nbayline_offline_economy = false\nbayline_native_atomic_phase = %s\nbayline_stock_generated_world = %s\nbayline_generated_map_size = %s\nbayline_generated_relief = 3\nbayline_generated_rivers = 1\nbayline_generated_mixed_freight = true\n' \
    "${BAYLINE_NATIVE_PORT:-42887}" "$phase" "$new" "$size" > "$out/server.conf"
}
args=(--config "$out/server.conf" --world "$out/world" --gameid bayline --logfile '')
write_config baseline
timeout 35 luantiserver "${args[@]}" > "$out/baseline.log" 2>&1
# Simulate starting an existing 128² preview when only its SQL data exists.
mv "$out/world/luanttd-wide-campaign.chk" "$out/first-stop-checkpoint.proof"
crash_phase() {
  local phase=$1 pid code
  local log="$out/$phase.log"
  write_config "$phase"
  luantiserver "${args[@]}" > "$log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null || true' EXIT
  for _ in {1..150}; do
    if grep -q 'STOCK_WIDE_CRASH_READY' "$log"; then break; fi
    kill -0 "$pid"
    sleep .08
  done
  grep 'STOCK_WIDE_CRASH_READY' "$log"
  kill -KILL "$pid"
  set +e
  wait "$pid"
  code=$?
  set -e
  trap - EXIT
  [[ $code == 137 ]]
  [[ -s "$out/world/luanttd-wide-campaign.chk" ]]
}
restore_phase() {
  local phase=$1 log="$out/$1.log"
  write_config "$phase"
  timeout 35 luantiserver "${args[@]}" > "$log" 2>&1 || { tail -35 "$log"; exit 1; }
  grep 'STOCK_WIDE_ATOMIC_PASS' "$log"
}
crash_phase crash
restore_phase restore
crash_phase remove_crash
restore_phase remove_restore
restore_phase reopen
# A present but damaged checkpoint is not permission for a silent rollback.
cp "$out/world/luanttd-wide-campaign.chk" "$out/recovered-checkpoint.proof"
printf 'bad test checksum\n' >> "$out/world/luanttd-wide-campaign.chk"
if timeout 10 luantiserver "${args[@]}" > "$out/checksum-reject.log" 2>&1; then
  echo 'Expected an invalid checkpoint to block loading' >&2; exit 1
fi
grep 'The wide campaign checkpoint is damaged or has an unsupported format' "$out/checksum-reject.log"
mv "$out/recovered-checkpoint.proof" "$out/world/luanttd-wide-campaign.chk"
