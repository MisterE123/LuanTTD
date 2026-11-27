#!/usr/bin/env bash
# Compare the normal generation pipeline, excluding checkpoint encoding.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
g="$out/games/oceanbench";m="$g/mods/luanttd_core"
mkdir -p "$g" "$out/home"
# A same-filesystem output directory avoids copying all media bytes.
if ! cp -al mods "$g/" 2>/dev/null; then
  rm -rf "$g/mods"
  cp -a mods "$g/"
fi
printf 'title = Pregame ocean test\n' > "$g/game.conf"
cp tests/pregame_open_water_perf_native.lua "$m/init.next"
mv "$m/init.next" "$m/init.lua"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for label in baseline candidate candidate2 baseline2; do
  if [[ "$label" == baseline* ]]; then
    git show "$base:mods/luanttd_core/initial_landscape_world.lua" > "$m/probe.next"
  else
    cp mods/luanttd_core/initial_landscape_world.lua "$m/probe.next"
  fi
  mv "$m/probe.next" "$m/initial_landscape_world.lua"
  w="$out/$label";mkdir "$w"
  printf 'gameid = oceanbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$w/world.mt"
  printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44360}" > "$w/conf"
  timeout 120 "$server" --world "$w" --gameid oceanbench --config "$w/conf" --logfile '' > "$w/log" 2>&1 ||
    { tail -40 "$w/log"; exit 1; }
  grep 'PREGAME PERF' "$w/log"
  if [[ "$label" != baseline ]]; then
    "${LUA:-lua5.1}" tests/pregame_open_water_compare.lua \
      <(zstd -dc "$out/baseline/state.zst") <(zstd -dc "$w/state.zst")
    rm "$w/state.zst"
  fi
done
