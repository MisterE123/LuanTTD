#!/usr/bin/env bash
# Native stock rail Oil to road Goods freight over one save.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-oil-live.XXXXXX")
echo "Native oil rail logs: $out"
game="$out/games/bayline"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -R mods "$game/"
cp tests/rail_oil_live_layout.lua "$game/mods/bayline/"
cat tests/rail_oil_live_native.lua >> "$game/mods/bayline/init.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = bayline
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<EOF_CONF
bayline_seed = 1751
bayline_scenario = oil
bayline_rail_owned_preview = true
bayline_rail_oil_preview = true
port = ${BAYLINE_NATIVE_PORT:-42836}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 50s luantiserver --world "$out/world" --config "$out/native.conf" --gameid bayline --logfile "" >"$out/server.log" 2>&1 || {
  cat "$out/server.log"; exit 1;
}
grep -q RAIL_OIL_SAVE_LOADING "$out/server.log" || { cat "$out/server.log"; exit 1; }
timeout 50s luantiserver --world "$out/world" --config "$out/native.conf" --gameid bayline --logfile "" >"$out/reload.log" 2>&1 || {
  cat "$out/reload.log"; exit 1;
}
grep RAIL_OIL_LIVE_NATIVE_PASS "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
