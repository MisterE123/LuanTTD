#!/usr/bin/env bash
# Exercise paid Bulldozer and natural reflooding on an isolated copy.
set -euo pipefail
[[ $# == 4 ]] || { echo "usage: $0 LUANTI_SERVER FIXTURE_WORLD CONFIG NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
src=$(realpath "$2")
conf=$(realpath "$3")
mkdir "$4"
out=$(realpath "$4")
cd "$(dirname "$0")/.."
g="$out/games/luanttd";m="$g/mods/luanttd_core"
mkdir -p "$g" "$out/home" "$out/world"
cp game.conf "$g/"
if ! cp -al mods "$g/" 2>/dev/null; then
  rm -rf "$g/mods";cp -a mods "$g/"
fi
{ cat mods/luanttd_core/init.lua; printf '\n'; cat tests/live_ocean_edit_native.lua; } > "$m/init.next"
mv "$m/init.next" "$m/init.lua"
cp "$src/luanttd-campaign-owner.chk" "$src/world.mt" "$out/world/"
sed -E '/^[[:space:]]*(port|bind_address|server_announce)[[:space:]]*=/d' "$conf" > "$out/conf"
printf '\nport = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44364}" >> "$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 90 "$server" --world "$out/world" --gameid luanttd --config "$out/conf" --logfile '' > "$out/server.log" 2>&1 ||
  { tail -40 "$out/server.log";exit 1; }
grep 'PASS LIVE OCEAN EDIT' "$out/server.log"
! grep -q 'ERROR\[' "$out/server.log"
