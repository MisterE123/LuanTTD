#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
game="$out/games/railtypebench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Railtype worker profile\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
printf 'gameid = railtypebench\n' > "$out/world/world.mt"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
git show "$2:mods/luanttd_core/rail_owned_service.lua" > "$mod/baseline_owned.lua"
cp tests/railtype_worker_perf_native.lua "$mod/init.lua"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44341}" > "$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 45 "$server" --world "$out/world" --config "$out/conf" --gameid railtypebench --logfile '' > "$out/log" 2>&1 ||
  { tail -45 "$out/log";exit 1; }
grep 'RAILTYPE PERF' "$out/log"
! grep -q 'ERROR\[' "$out/log"
