#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server=${1:-luantiserver}
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-scene-wire.XXXXXX")
echo "Native scene transfer evidence: $out"
game="$out/games/wire";m="$game/mods/luanttd_core"
mkdir -p "$m" "$out/world" "$out/home"
cp mods/luanttd_core/*.lua "$m/"
cp -r mods/luanttd_core/openttd "$m/"
cp tests/campaign_scene_wire_native.lua "$m/init.lua"
cp tests/campaign_scene_wire_fixture.lua "$m/wire_fixture.lua"
printf 'title = Scene wire QA\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = wire\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-43074}" >"$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 65 "$server" --world "$out/world" --config "$out/conf" --gameid wire --logfile '' >"$out/log" 2>&1; then
 cat "$out/log";exit 1
fi
grep 'NATIVE SCENE WIRE' "$out/log"
! grep -q 'ERROR\[' "$out/log"
