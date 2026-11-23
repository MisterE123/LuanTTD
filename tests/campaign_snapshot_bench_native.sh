#!/usr/bin/env bash
# Benchmark the exact endpoint inside a native Luanti asynchronous Lua VM.
# us measured inside the job, excluding launch, IPC and rendering.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2;exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
baseline=$2
mkdir "$3"
out=$(realpath "$3")
game="$out/games/snapshotbench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native campaign snapshot benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/campaign_snapshot_bench_native.lua "$mod/init.lua"
cp tests/campaign_snapshot_bench.lua "$mod/"
git show "$baseline:mods/luanttd_core/campaign_authority_endpoint.lua" > "$mod/baseline_endpoint.lua"
git show "$baseline:mods/luanttd_core/campaign_terrain_projection.lua" > "$mod/baseline_projection.lua"
printf 'gameid = snapshotbench\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-43041}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 55 "$server" --config "$out/server.conf" --world "$out/world" --gameid snapshotbench --logfile '' >"$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep "NATIVE SNAPSHOT BENCH" "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
