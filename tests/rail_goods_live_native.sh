#!/usr/bin/env bash
# Two dedicated native processes, shared isolated SQLite campaign.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-goods-live.XXXXXX")
echo "Native Goods rail logs: $out"
game="$out/games/bayline"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -R mods "$game/"
cat tests/rail_goods_live_native.lua >> "$game/mods/bayline/init.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = bayline
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<EOF_CONF
bayline_rail_owned_preview = true
bayline_preview_paid_rail = true
bayline_rail_construction_preview = true
bayline_fixture_harbor_valley = true
bayline_road_timber_preview = true
bayline_native_rail_goods_competition = ${BAYLINE_NATIVE_GOODS_COMPETITION:-false}
port = ${BAYLINE_NATIVE_PORT:-41488}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for step in server reload; do
  timeout 35s luantiserver --world "$out/world" --config "$out/native.conf" --gameid bayline --logfile "" \
    >"$out/$step.log" 2>&1 || { cat "$out/$step.log"; exit 1; }
  if [[ $step == server ]]; then mark=RAIL_GOODS_NATIVE_SAVE_LOADING; else mark=RAIL_GOODS_LIVE_NATIVE_PASS; fi
  grep "$mark" "$out/$step.log" || { cat "$out/$step.log"; exit 1; }
done
