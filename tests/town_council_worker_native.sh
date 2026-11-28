#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rc1-council.XXXXXX")
echo "Council worker evidence: $out"
game="$out/games/councilqa"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Stock town council QA\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
if ! cp -l mods/luanttd_core/*.lua "$mod/" 2>/dev/null; then cp mods/luanttd_core/*.lua "$mod/"; fi
if ! cp -al mods/luanttd_core/openttd "$mod/" 2>/dev/null; then cp -a mods/luanttd_core/openttd "$mod/"; fi
rm "$mod/init.lua"
cp tests/town_council_worker_native.lua "$mod/init.lua"
printf 'gameid = councilqa\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-43405}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$out/server.conf"
for phase in SERVICE REOPEN; do
  timeout 50 luantiserver --world "$out/world" --config "$out/server.conf" --gameid councilqa --logfile '' > "$out/$phase.log" 2>&1 || {
    tail -70 "$out/$phase.log";exit 1;
  }
  grep "PASS NATIVE COUNCIL $phase" "$out/$phase.log"
done
