#!/usr/bin/env bash
# Native Industry::OnTick adapter workload, not an FPS or worldgen test.
set -euo pipefail
[[ $# == 3 || $# == 4 && $4 == --ordinary ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIR [--ordinary]" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
game="$out/games/industrybench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/home" "$out/world"
printf 'title = Industry clock benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
printf 'gameid = industrybench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cp -a mods/luanttd_core/openttd "$mod/"
cp mods/luanttd_core/{combined_industry_runtime,timber_industry_runtime}.lua "$mod/"
git show "$2:mods/luanttd_core/openttd/farm_factory_industry.lua" > "$mod/baseline-farm.lua"
git show "$2:mods/luanttd_core/openttd/oil_industry.lua" > "$mod/baseline-oil.lua"
git show "$2:mods/luanttd_core/combined_industry_runtime.lua" > "$mod/baseline-combined.lua"
git show "$2:mods/luanttd_core/timber_industry_runtime.lua" > "$mod/baseline-runtime.lua"
cp tests/industry_tick_perf_native.lua "$mod/init.lua"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44346}" > "$out/conf"
if [[ $# == 4 ]]; then echo 'luanttd_qa_industry_ordinary = true' >> "$out/conf"; fi
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 60 "$server" --world "$out/world" --gameid industrybench --config "$out/conf" --logfile '' > "$out/log" 2>&1 ||
  { tail -45 "$out/log";exit 1; }
grep 'INDUSTRY PERF' "$out/log"
! grep -q 'ERROR\[' "$out/log"
