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
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -al mods "$game/" || cp -R mods "$game/"
cp mods/luanttd_core/init.lua "$out/current-init.lua"
mv "$out/current-init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
cat tests/rail_goods_live_native.lua >> "$game/mods/luanttd_core/init.lua"
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
bayline_rail_owned_preview = true
bayline_preview_paid_rail = true
bayline_rail_construction_preview = true
luanttd_qa_coastal_layout = true
bayline_seconds_per_day = 15
luanttd_qa_freight_order_edit = ${LUANTTD_NATIVE_FREIGHT_ORDER_EDIT:-false}
luanttd_qa_passenger_and_goods = ${LUANTTD_NATIVE_PASSENGER_AND_GOODS:-false}
bayline_road_timber_preview = true
bayline_native_craighead_goods = ${LUANTTD_NATIVE_CRAIGHEAD:-false}
bayline_native_rail_goods_competition = ${BAYLINE_NATIVE_GOODS_COMPETITION:-false}
bayline_rail_goods_qa_engine = ${BAYLINE_NATIVE_GOODS_ENGINE:-0}
bayline_stock_bus_start_year = ${BAYLINE_NATIVE_GOODS_YEAR:-1950}
port = ${BAYLINE_NATIVE_PORT:-41488}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for step in server reload; do
  timeout 35s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" \
    >"$out/$step.log" 2>&1 || { cat "$out/$step.log"; exit 1; }
  if [[ $step == server ]]; then mark=RAIL_GOODS_NATIVE_SAVE_LOADING; else mark=RAIL_GOODS_LIVE_NATIVE_PASS; fi
  grep "$mark" "$out/$step.log" || { cat "$out/$step.log"; exit 1; }
done
if [[ ${LUANTTD_NATIVE_PASSENGER_AND_GOODS:-false} == true ]]; then
  grep MIXED_PASSENGER_GOODS_NATIVE_PASS "$out/reload.log"
fi
if [[ ${LUANTTD_NATIVE_FREIGHT_ORDER_EDIT:-false} == true ]]; then
  grep RAIL_FREIGHT_ORDER_EDIT_NATIVE_PASS "$out/reload.log"
fi
