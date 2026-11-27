#!/usr/bin/env bash
# Native viewport comparison with 960 paid buses and narrow sector requests.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_REV NEW_OUTPUT_DIR" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
p=$(realpath "$3")
cd "$(dirname "$0")/.."
g="$p/games/interests";m="$g/mods/luanttd_core"
mkdir -p "$m" "$p/home" "$p/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
git show "$base:mods/luanttd_core/campaign_authority_endpoint.lua" > "$m/baseline_endpoint.lua"
git show "$base:mods/luanttd_core/campaign_actor_projection.lua" > "$m/baseline_projection.lua"
cp tests/campaign_actor_interest_native.lua "$m/init.lua"
cp tests/road_fleet_perf.lua "$m/"
printf 'title = Actor interest test\n' > "$g/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = interests\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$p/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-43037}" > "$p/conf"
HOME="$p/home" LUANTI_GAME_PATH="$p/games" MINETEST_GAME_PATH="$p/games" timeout 120 "$server" --world "$p/world" --config "$p/conf" --gameid interests --logfile '' > "$p/log" 2>&1 ||
 { tail -45 "$p/log";exit 1; }
test "$(grep -c 'ACTOR INTEREST' "$p/log")" = 8
grep 'ACTOR INTEREST' "$p/log"
! grep -q 'ERROR\[' "$p/log"
