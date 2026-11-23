#!/usr/bin/env bash
# Actual Luanti runtime, production campaign and native solar engine.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
server=${BAYLINE_LUANTI_SERVER:-luantiserver}
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-daylight.XXXXXX")
echo "Native daylight evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{home,world}
cp -al mods "$game/"
cp game.conf settingtypes.txt "$game/"
mod="$game/mods/luanttd_core"
# Replace the test checkout's init with a private copy before appending.
cp "$mod/init.lua" "$mod/init.native"
mv -f "$mod/init.native" "$mod/init.lua"
cat tests/daylight_native.lua >> "$mod/init.lua"
printf 'return function() return {interval=.15} end\n' > "$mod/qa_layout.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-43992}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\nbayline_stock_bus_start_year = 2000\nbayline_generated_map_width = 64\nbayline_generated_map_depth = 64\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for stage in first reopened; do
  if ! timeout 35 "$server" --config "$out/server.conf" --world "$out/world" --gameid luanttd --logfile '' > "$out/$stage.log" 2>&1; then
    cat "$out/$stage.log"; exit 1
  fi
done
grep -F 'DAYLIGHT_WORKER after-new-year' "$out/first.log"
grep -F 'DAYLIGHT_WORKER held' "$out/first.log"
grep -F 'DAYLIGHT_WORKER reopen' "$out/reopened.log"
held=$(sed -n 's/.*DAYLIGHT_WORKER held //p' "$out/first.log")
reopen=$(sed -n 's/.*DAYLIGHT_WORKER reopen //p' "$out/reopened.log")
[[ "$held" == "$reopen" ]] || { printf '%s\n%s\n' "$held" "$reopen"; exit 1; }
if grep -E 'ERROR\[' "$out/first.log" "$out/reopened.log"; then exit 1; fi
