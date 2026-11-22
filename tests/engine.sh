#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server="${1:-luantiserver}"
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/games/bayline" "$test_dir/world" "$test_dir/railworld" "$test_dir/buildworld" "$test_dir/home"
cp -r game.conf mods "$test_dir/games/bayline/"
cp tests/engine_probe.lua "$test_dir/games/bayline/mods/bayline/probe.lua"
echo 'dofile(mod.."/probe.lua")(api,ui)' >> "$test_dir/games/bayline/mods/bayline/init.lua"
printf 'gameid = bayline\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$test_dir/world/world.mt"
cp "$test_dir/world/world.mt" "$test_dir/railworld/world.mt"
cp "$test_dir/world/world.mt" "$test_dir/buildworld/world.mt"
export HOME="$test_dir/home"
export LUANTI_GAME_PATH="$test_dir/games" MINETEST_GAME_PATH="$test_dir/games"
for phase in create reload rail reload_rail world; do
  world=world
  if [[ "$phase" == *rail ]]; then world=railworld; fi
  if [[ "$phase" == world ]]; then world=buildworld; fi
  printf 'bayline_test_phase = %s\nbayline_development_tools = true\nbayline_fixture_legacy_layout = true\nport = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$phase" "${BAYLINE_TEST_PORT:-39259}" > "$test_dir/server.conf"
  if ! timeout 40 "$server" --config "$test_dir/server.conf" --world "$test_dir/$world" --gameid bayline --logfile '' > "$test_dir/$phase.log" 2>&1; then
    cat "$test_dir/$phase.log"
    exit 1
  fi
  grep "BAYLINE PASS $phase" "$test_dir/$phase.log"
  if grep -E 'ERROR\[' "$test_dir/$phase.log"; then exit 1; fi
done
