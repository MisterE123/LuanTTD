#!/usr/bin/env bash
# Native owned steam consist, commercial rail clock and restart recovery on Linux.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-owned-pair.XXXXXX")
echo "Native paired rail logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -R mods "$game/"
cp tests/rail_owned_pair_fixture.lua "$game/mods/luanttd_core/"
cat tests/rail_owned_pair_native.lua >> "$game/mods/luanttd_core/init.lua"
cp tests/qa_layout.lua "$game/mods/luanttd_core/qa_layout.lua"
cp tests/coastal_corridor_fixture.lua "$game/mods/luanttd_core/qa_coastal_corridor.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<EOF_CONF
luanttd_qa_coastal_layout = true
bayline_rail_owned_preview = true
bayline_rail_pair_preview = true
bayline_preview_paid_rail = true
bayline_rail_construction_preview = true
bayline_rail_span_preview = true
port = ${BAYLINE_NATIVE_PORT:-39633}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 || {
  cat "$out/server.log"; exit 1;
}
grep -q OWNED_PAIR_NATIVE_SAVED_TAIL "$out/server.log" || { cat "$out/server.log"; exit 1; }
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/reload.log" 2>&1 || {
  cat "$out/reload.log"; exit 1;
}
grep -q OWNED_PAIR_NATIVE_PASS "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
echo 'PASS: native paid twin steam purchase, separate poses, saved PBS contention and terminal ownership'
