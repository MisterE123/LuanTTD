#!/usr/bin/env bash
# Native owned steam consist, commercial rail clock and restart recovery on Linux.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-owned-live.XXXXXX")
echo "Native owned rail logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp "${BAYLINE_NATIVE_EXACT_GAME:-.}/game.conf" "$game"
if [[ -n ${BAYLINE_NATIVE_ASSET_MOD:-} ]]; then
  # Sparse worktrees can use unchanged art without copying an entire game.
  mkdir -p "$game/mods/luanttd_core"
  cp -R "${BAYLINE_NATIVE_EXACT_GAME:-.}/mods/luanttd_core/." "$game/mods/luanttd_core/"
  for kind in models textures; do
    cp -al "$(realpath "$BAYLINE_NATIVE_ASSET_MOD/$kind")" "$game/mods/luanttd_core/$kind"
  done
else
  cp -al "${BAYLINE_NATIVE_EXACT_GAME:-.}/mods" "$game/" || cp -R "${BAYLINE_NATIVE_EXACT_GAME:-.}/mods" "$game/"
fi
cp "${BAYLINE_NATIVE_EXACT_GAME:-.}/mods/luanttd_core/init.lua" "$out/fixture-init.lua"
mv "$out/fixture-init.lua" "$game/mods/luanttd_core/init.lua"
if [[ ${LUANTTD_NATIVE_RAIL_FLOOD:-false} == true ]]; then
  cat tests/rail_flood_native.lua >> "$game/mods/luanttd_core/init.lua"
elif [[ ${LUANTTD_NATIVE_ORDER_SEQUENCE:-false} == true ]]; then
  cat tests/rail_order_list_native.lua >> "$game/mods/luanttd_core/init.lua"
elif [[ ${LUANTTD_NATIVE_MIXED_FLEET:-false} == true ]]; then
  cat tests/rail_owned_multi_native.lua >> "$game/mods/luanttd_core/init.lua"
  cp tests/rail_owned_multi_fixture.lua "$game/mods/luanttd_core/qa_rail_multi.lua"
elif [[ ${LUANTTD_NATIVE_SHARED_DEPOT:-false} == true ]]; then
  cat tests/rail_shared_depot_native.lua >> "$game/mods/luanttd_core/init.lua"
  cp tests/rail_shared_depot_fixture.lua "$game/mods/luanttd_core/qa_rail_shared_depot.lua"
elif [[ ${LUANTTD_NATIVE_COLLISION:-false} == true ]]; then
  cat tests/rail_collision_native.lua >> "$game/mods/luanttd_core/init.lua"
  cp tests/rail_collision_fixture.lua "$game/mods/luanttd_core/qa_rail_collision.lua"
else
  cat tests/rail_owned_live_native.lua >> "$game/mods/luanttd_core/init.lua"
fi
cp tests/qa_layout.lua "$game/mods/luanttd_core/qa_layout.lua"
cp tests/coastal_corridor_fixture.lua "$game/mods/luanttd_core/qa_coastal_corridor.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
use_market=false
if [[ ${LUANTTD_NATIVE_ASIASTAR:-false} == true || ${LUANTTD_NATIVE_TIM:-false} == true || ${LUANTTD_NATIVE_DASH:-false} == true || ${LUANTTD_NATIVE_DASH_COACH:-false} == true || ${BAYLINE_NATIVE_SH_8P:-false} == true || ${BAYLINE_NATIVE_MANLEY:-false} == true || ${BAYLINE_NATIVE_MANLEY_COACH:-false} == true || ${BAYLINE_NATIVE_ELECTRIC:-false} == true || ${BAYLINE_NATIVE_SH_40:-false} == true ]]; then use_market=true; fi
cat > "$out/native.conf" <<EOF_CONF
luanttd_qa_coastal_platform_rail = ${LUANTTD_NATIVE_RAIL_FLOOD_PLATFORM:-false}
luanttd_qa_coastal_signed_rail = ${LUANTTD_NATIVE_RAIL_FLOOD_SIGNALS:-false}
luanttd_qa_asiastar = ${LUANTTD_NATIVE_ASIASTAR:-false}
luanttd_qa_tim = ${LUANTTD_NATIVE_TIM:-false}
luanttd_qa_dash = ${LUANTTD_NATIVE_DASH:-false}
luanttd_qa_dash_coach = ${LUANTTD_NATIVE_DASH_COACH:-false}
luanttd_qa_live_order_edit = ${LUANTTD_NATIVE_LIVE_ORDER_EDIT:-false}
luanttd_qa_cargo_order_edit = ${LUANTTD_NATIVE_CARGO_ORDER_EDIT:-false}
luanttd_qa_two_coaches = ${LUANTTD_NATIVE_TWO_COACHES:-false}
luanttd_qa_disconnected_path_signal = ${LUANTTD_NATIVE_DISCONNECTED_PBS:-false}
luanttd_qa_depot_turnout = ${LUANTTD_NATIVE_DEPOT_TURNOUT:-false}
luanttd_qa_signal_free = ${LUANTTD_NATIVE_SIGNAL_FREE:-false}
luanttd_qa_coastal_layout = true
bayline_offline_economy = false
bayline_seconds_per_day = 15
bayline_rail_owned_preview = true
bayline_native_jubilee_probe = ${BAYLINE_NATIVE_JUBILEE:-false}
bayline_native_sh_8p_probe = ${BAYLINE_NATIVE_SH_8P:-false}
bayline_native_manley_probe = ${BAYLINE_NATIVE_MANLEY:-false}
bayline_native_manley_coach_probe = ${BAYLINE_NATIVE_MANLEY_COACH:-false}
bayline_native_electric_probe = ${BAYLINE_NATIVE_ELECTRIC:-false}
bayline_native_sh_40_probe = ${BAYLINE_NATIVE_SH_40:-false}
bayline_native_electric_bridge_probe = ${BAYLINE_NATIVE_ELECTRIC_BRIDGE:-false}
bayline_electric_bridge_preview = ${BAYLINE_NATIVE_ELECTRIC_BRIDGE:-false}
bayline_native_rail_branch_probe = ${BAYLINE_NATIVE_RAIL_BRANCH:-false}
bayline_native_platform_lookahead_probe = ${BAYLINE_NATIVE_PLATFORM_LOOKAHEAD:-false}
bayline_stock_bus_catalog = $use_market
bayline_stock_bus_start_year = ${BAYLINE_NATIVE_STEAM_START_YEAR:-1950}
bayline_preview_paid_rail = true
bayline_rail_construction_preview = true
bayline_rail_span_preview = true
port = ${BAYLINE_NATIVE_PORT:-39602}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 || {
  cat "$out/server.log"; exit 1;
}
save_mark=OWNED_RAIL_SAVE_LOADING
pass_mark=OWNED_RAIL_LIVE_NATIVE_PASS
if [[ ${LUANTTD_NATIVE_RAIL_FLOOD:-false} == true ]]; then
  save_mark=RAIL_FLOOD_NATIVE_SAVED_WRECK
  pass_mark=RAIL_FLOOD_NATIVE_PASS
elif [[ ${LUANTTD_NATIVE_ORDER_SEQUENCE:-false} == true ]]; then
  save_mark=RAIL_ORDER_LIST_NATIVE_SAVED
  pass_mark=RAIL_ORDER_LIST_NATIVE_PASS
elif [[ ${LUANTTD_NATIVE_MIXED_FLEET:-false} == true ]]; then
  save_mark=MIXED_RAIL_NATIVE_SAVED_WAIT
  pass_mark=MIXED_RAIL_NATIVE_PASS
elif [[ ${LUANTTD_NATIVE_SHARED_DEPOT:-false} == true ]]; then
  save_mark=SHARED_DEPOT_NATIVE_SAVED_ONE_WAITING
  pass_mark=SHARED_DEPOT_NATIVE_PASS
elif [[ ${LUANTTD_NATIVE_COLLISION:-false} == true ]]; then
  save_mark=COLLISION_NATIVE_SAVED_APPROACH
  pass_mark=COLLISION_NATIVE_PASS
fi
grep -q "$save_mark" "$out/server.log" || { cat "$out/server.log"; exit 1; }
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/reload.log" 2>&1 || {
  cat "$out/reload.log"; exit 1;
}
grep -q "$pass_mark" "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
if [[ ${BAYLINE_NATIVE_PLATFORM_LOOKAHEAD:-false} == true ]]; then
  grep -q OWNED_RAIL_THROUGH_NATIVE_PASS "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
fi
if [[ ${LUANTTD_NATIVE_RAIL_FLOOD:-false} == true ]]; then
  grep RAIL_FLOOD_NATIVE_PASS "$out/reload.log"
elif [[ ${LUANTTD_NATIVE_ORDER_SEQUENCE:-false} == true ]]; then
  grep RAIL_ORDER_LIST_NATIVE_PASS "$out/reload.log"
elif [[ ${LUANTTD_NATIVE_MIXED_FLEET:-false} == true ]]; then
  grep MIXED_RAIL_NATIVE_PASS "$out/reload.log"
elif [[ ${LUANTTD_NATIVE_SHARED_DEPOT:-false} == true ]]; then
  grep SHARED_DEPOT_NATIVE_PASS "$out/reload.log"
elif [[ ${LUANTTD_NATIVE_COLLISION:-false} == true ]]; then
  grep COLLISION_NATIVE_PASS "$out/reload.log"
else
  echo 'PASS: native owned rail purchase, exact mesh mounting, saved loading and paid after restart'
fi
if [[ ${LUANTTD_NATIVE_DEPOT_TURNOUT:-false} == true ]]; then
  grep OWNED_RAIL_DEPOT_TURNOUT_NATIVE_PASS "$out/reload.log"
fi
if [[ ${LUANTTD_NATIVE_TWO_COACHES:-false} == true ]]; then
  grep OWNED_RAIL_TWO_COACHES_NATIVE_PASS "$out/reload.log"
fi
if [[ ${LUANTTD_NATIVE_DISCONNECTED_PBS:-false} == true ]]; then
  grep OWNED_RAIL_UNRELATED_PBS_NATIVE_PASS "$out/reload.log"
fi
