#!/usr/bin/env bash
# Read a copy of the fixture from campaign_pose_gap_native.sh, never a live world.
set -euo pipefail
[[ $# == 4 || $# == 5 && $5 == --equivalent ]] || {
  echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV FIXTURE_CHECKPOINT NEW_OUTPUT_DIRECTORY [--equivalent]" >&2; exit 64;
}
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
source_cp=$(realpath "$3")
mkdir "$4"
out=$(realpath "$4")
cd "$(dirname "$0")/.."
game="$out/games/checkpointbench"
mod="$game/mods/bench"
mkdir -p "$mod" "$out/home" "$out/world"
echo 'title = Checkpoint benchmark' > "$game/game.conf"
echo 'name = bench' > "$mod/mod.conf"
echo 'gameid = checkpointbench' > "$out/world/world.mt"
git show "$2:mods/luanttd_core/packed_campaign.lua" > "$mod/baseline.lua"
cp mods/luanttd_core/{packed_campaign,campaign_checkpoint}.lua "$mod/"
cp tests/campaign_checkpoint_perf_native.lua "$mod/init.lua"
cp "$source_cp" "$out/world/luanttd-wide-campaign.chk"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-43979}" > "$out/conf"
if [[ $# == 5 ]]; then echo 'checkpoint_bench_equivalent = true' >> "$out/conf"; fi
timeout 100 "$server" --world "$out/world" --config "$out/conf" --gameid checkpointbench --logfile '' > "$out/server.log" 2>&1 ||
  { tail -60 "$out/server.log"; exit 1; }
grep "CHECKPOINT BENCH" "$out/server.log"
