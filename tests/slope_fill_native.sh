#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-slope-fill.XXXXXX")
echo "Native slope fill logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp "$src/game.conf" "$game/"
if [[ "$(stat -c %d "$src")" == "$(stat -c %d "$out")" ]]; then
  cp -al "$src/mods" "$game/"
else
  cp -R "$src/mods" "$game/"
fi
cat "$src/mods/luanttd_core/init.lua" tests/slope_fill_native_append.lua >"$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
printf 'gameid = luanttd\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-42962}" >"$out/native.conf"
timeout 30 luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 ||
  { cat "$out/server.log"; exit 1; }
grep SLOPE_FILL_NATIVE_PASS "$out/server.log"
