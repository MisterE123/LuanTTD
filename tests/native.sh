#!/usr/bin/env bash
# UI-driven graphical smoke test. Requires Luanti client and server, Xvfb,
# xdotool, Xauth, ImageMagick, Python 3 and Pillow. Optional fallback directory
# for unpacked dependencies: BAYLINE_NATIVE_TOOLS=/tmp/bayline-run
# On hosts denying Unix sockets, set BAYLINE_NATIVE_TCP=1 (requires cc).
# To also exercise shared-corner ramp roads, set BAYLINE_NATIVE_GRADE=1.
# To play the default start with native mouse look, set BAYLINE_NATIVE_FRESH=1.
# Combine it with BAYLINE_NATIVE_TURNS=1 to exercise a visible bend.
# BAYLINE_NATIVE_STOCK_LOADING=1 explicitly opts into stock road station service.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
for exe in "${BAYLINE_LUANTI_CLIENT:-luanti}" "${BAYLINE_LUANTI_SERVER:-luantiserver}" Xvfb xdotool xauth xdpyinfo import python3; do
  command -v "$exe" >/dev/null || { echo "Missing dependency: $exe" >&2; exit 1; }
done
out=$(mktemp -d "${TMPDIR:-/tmp}/bayline-ui-test.XXXXXX")
echo "Native UI evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-93}
port=${BAYLINE_NATIVE_PORT:-39293}
check=()
cleanup() {
  for pid in "${check[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mkdir -p "$out"/{world,games/luanttd,home,cache}
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} ]]; then
  seed=$(realpath "$BAYLINE_NATIVE_CACHE_SEED")
  if [[ -d "$seed/minetest" ]]; then cp -R "$seed/minetest" "$out/cache/"; fi
fi
if [[ -n ${BAYLINE_NATIVE_EXACT_GAME:-} ]]; then
  game=$(realpath "$BAYLINE_NATIVE_EXACT_GAME")
  cp -r "$game/game.conf" "$game/mods" "$out/games/luanttd/"
else
  cp -r game.conf mods "$out/games/luanttd/"
fi
cp -r tests/native_probe.lua "$out/games/luanttd/mods/luanttd_core/"
if [[ ${BAYLINE_NATIVE_COAST:-0} == 1 ]]; then
  cp tests/native_coastal_probe.lua "$out/games/luanttd/mods/luanttd_core/"
fi
if [[ ${BAYLINE_NATIVE_RAIL_OIL:-0} == 1 ]]; then
  cp tests/{native_rail_oil_probe,rail_oil_live_layout}.lua "$out/games/luanttd/mods/luanttd_core/"
fi
if [[ ${BAYLINE_NATIVE_RAIL_PAIR:-0} == 1 ]]; then
  cp tests/rail_owned_pair_fixture.lua "$out/games/luanttd/mods/luanttd_core/"
fi
if [[ ${BAYLINE_NATIVE_JUNCTION_CLEARANCE:-0} == 1 ]]; then
  cp tests/road_junction_fixture.lua "$out/games/luanttd/mods/luanttd_core/"
fi
if [[ -n ${BAYLINE_NATIVE_OVERTAKE:-} ]]; then
  [[ ${BAYLINE_NATIVE_OVERTAKE} == stopped || ${BAYLINE_NATIVE_OVERTAKE} == moving ]]
  cp tests/road_overtake_fixture.lua "$out/games/luanttd/mods/luanttd_core/"
fi
printf '\ndofile(mod.."/native_probe.lua")(api,ui)\n' >> "$out/games/luanttd/mods/luanttd_core/init.lua"
cp tests/qa_layout.lua "$out/games/luanttd/mods/luanttd_core/qa_layout.lua"
cp tests/coastal_corridor_fixture.lua "$out/games/luanttd/mods/luanttd_core/qa_coastal_corridor.lua"
cat > "$out/world/world.mt" <<'EOF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
bayline_seconds_per_day = 0.60
bayline_seed = 1751
bayline_development_tools = $([[ ${BAYLINE_NATIVE_FRESH:-0} == 1 ]] && echo false || echo true)
bayline_road_oneway_preview = $([[ ${BAYLINE_NATIVE_ONEWAY:-0} == 1 ]] && echo true || echo false)
bayline_bridge_construction_preview = $([[ ${BAYLINE_NATIVE_LANDSCAPE_BRIDGE:-0} == 1 ]] && echo true || echo false)
bayline_rail_dispatch_preview = $([[ ${BAYLINE_NATIVE_RAIL_DISPATCH:-0} == 1 || ${BAYLINE_NATIVE_RAIL_SHUTTLE:-0} == 1 || ${BAYLINE_NATIVE_RAIL_GRADE:-0} == 1 || ${BAYLINE_NATIVE_PAID_RAIL:-0} == 1 || ${BAYLINE_NATIVE_RAIL_BUILD:-0} == 1 ]] && echo true || echo false)
luanttd_native_depot_facing = $([[ ${LUANTTD_NATIVE_DEPOT_FACING:-0} == 1 ]] && echo true || echo false)
bayline_native_shuttle = $([[ ${BAYLINE_NATIVE_RAIL_SHUTTLE:-0} == 1 ]] && echo true || echo false)
bayline_rail_construction_preview = $([[ ${BAYLINE_NATIVE_RAIL_BUILD:-0} == 1 || ${BAYLINE_NATIVE_RAIL_SPAN:-0} == 1 || ${BAYLINE_NATIVE_CROSSING:-0} == 1 ]] && echo true || echo false)
bayline_native_owned_default = $([[ ${BAYLINE_NATIVE_OWNED_DEFAULT:-0} == 1 ]] && echo true || echo false)
bayline_native_jubilee = $([[ ${BAYLINE_NATIVE_JUBILEE:-0} == 1 ]] && echo true || echo false)
bayline_native_ginzu = $([[ ${BAYLINE_NATIVE_GINZU:-0} == 1 ]] && echo true || echo false)
bayline_native_floss = $([[ ${BAYLINE_NATIVE_FLOSS:-0} == 1 ]] && echo true || echo false)
bayline_rail_owned_preview = $([[ ${BAYLINE_NATIVE_RAIL_OWNED:-0} == 1 || ${BAYLINE_NATIVE_RAIL_COAL:-0} == 1 || ${BAYLINE_NATIVE_RAIL_OIL:-0} == 1 || ${BAYLINE_NATIVE_RAIL_PAIR:-0} == 1 ]] && echo true || echo false)
bayline_rail_oil_preview = $([[ ${BAYLINE_NATIVE_RAIL_OIL:-0} == 1 ]] && echo true || echo false)
bayline_rail_pair_preview = $([[ ${BAYLINE_NATIVE_RAIL_PAIR:-0} == 1 ]] && echo true || echo false)
bayline_rail_block_preview = $([[ ${BAYLINE_NATIVE_RAIL_BLOCK:-0} == 1 ]] && echo true || echo false)
bayline_rail_coal_preview = $([[ ${BAYLINE_NATIVE_RAIL_COAL:-0} == 1 ]] && echo true || echo false)
bayline_rail_crossing_preview = $([[ ${BAYLINE_NATIVE_CROSSING:-0} == 1 ]] && echo true || echo false)
bayline_rail_span_preview = $([[ ${BAYLINE_NATIVE_RAIL_SPAN:-0} == 1 ]] && echo true || echo false)
bayline_rail_grade_preview = $([[ ${BAYLINE_NATIVE_RAIL_GRADE:-0} == 1 ]] && echo true || echo false)
bayline_ship_preview = $([[ ${BAYLINE_NATIVE_SHIP:-0} == 1 || ${BAYLINE_NATIVE_SHIP_COAL:-0} == 1 || ${BAYLINE_NATIVE_AQUEDUCT:-0} == 1 || ${BAYLINE_NATIVE_LOCK:-0} == 1 || ${BAYLINE_NATIVE_PAID_FERRY:-0} == 1 || ${BAYLINE_NATIVE_PAID_RAIL:-0} == 1 ]] && echo true || echo false)
bayline_ship_coal_preview = $([[ ${BAYLINE_NATIVE_SHIP_COAL:-0} == 1 ]] && echo true || echo false)
bayline_ship_coal_coastal_scenario = $([[ ${BAYLINE_NATIVE_SHIP_COAL:-0} == 1 ]] && echo true || echo false)
bayline_native_aqueduct = $([[ ${BAYLINE_NATIVE_AQUEDUCT:-0} == 1 ]] && echo true || echo false)
bayline_native_lock = $([[ ${BAYLINE_NATIVE_LOCK:-0} == 1 ]] && echo true || echo false)
bayline_airport_preview = $([[ ${BAYLINE_NATIVE_AIRFIELD:-0} == 1 || ${BAYLINE_NATIVE_PAID_AIR:-0} == 1 ]] && echo true || echo false)
bayline_air_fleet_preview = $([[ ${BAYLINE_NATIVE_AIR_FLEET:-0} == 1 || ${BAYLINE_NATIVE_BAKEWELL:-0} == 1 ]] && echo true || echo false)
bayline_air_owned_preview = $([[ ${BAYLINE_NATIVE_OWNED_AIR:-0} == 1 ]] && echo true || echo false)
bayline_preview_paid_rail = $([[ ${BAYLINE_NATIVE_PAID_RAIL:-0} == 1 || ${BAYLINE_NATIVE_RAIL_OWNED:-0} == 1 || ${BAYLINE_NATIVE_RAIL_PAIR:-0} == 1 ]] && echo true || echo false)
bayline_preview_paid_ferry = $([[ ${BAYLINE_NATIVE_PAID_FERRY:-0} == 1 || ${BAYLINE_NATIVE_PAID_RAIL:-0} == 1 ]] && echo true || echo false)
bayline_preview_coal_industry = $([[ ${BAYLINE_NATIVE_COAL:-0} == 1 ]] && echo true || echo false)
bayline_road_timber_preview = $([[ ${BAYLINE_NATIVE_TIMBER:-0} == 1 ]] && echo true || echo false)
bayline_native_shared_orders = $([[ ${BAYLINE_NATIVE_SHARED_ORDERS:-0} == 1 ]] && echo true || echo false)
bayline_road_farm_preview = $([[ ${BAYLINE_NATIVE_FARM:-0} == 1 ]] && echo true || echo false)
bayline_road_oil_preview = $([[ ${BAYLINE_NATIVE_OIL:-0} == 1 || ${BAYLINE_NATIVE_RAIL_OIL:-0} == 1 ]] && echo true || echo false)
bayline_stock_town_growth = $([[ ${BAYLINE_NATIVE_TOWN_GROWTH:-0} == 1 ]] && echo true || echo false)
bayline_native_town_growth = $([[ ${BAYLINE_NATIVE_TOWN_GROWTH:-0} == 1 ]] && echo true || echo false)
bayline_tram_preview = $([[ ${BAYLINE_NATIVE_TRAM:-0} == 1 ]] && echo true || echo false)
bayline_trackworks_preview = $([[ ${BAYLINE_NATIVE_TRACKWORKS:-0} == 1 ]] && echo true || echo false)
bayline_mail_preview = $([[ ${BAYLINE_NATIVE_MAIL:-0} == 1 ]] && echo true || echo false)
bayline_native_leopard = $([[ ${BAYLINE_NATIVE_LEOPARD:-0} == 1 ]] && echo true || echo false)
bayline_native_concrete = $([[ ${BAYLINE_NATIVE_CONCRETE:-0} == 1 ]] && echo true || echo false)
bayline_native_steel = $([[ ${BAYLINE_NATIVE_STEEL:-0} == 1 ]] && echo true || echo false)
bayline_native_tunnel_run = $([[ ${BAYLINE_NATIVE_TUNNEL_RUN:-0} == 1 ]] && echo true || echo false)
bayline_native_bridge_run = $([[ ${BAYLINE_NATIVE_BRIDGE_RUN:-0} == 1 ]] && echo true || echo false)
bayline_native_queue = $([[ ${BAYLINE_NATIVE_QUEUE:-0} == 1 ]] && echo true || echo false)
bayline_native_junction_clearance = $([[ ${BAYLINE_NATIVE_JUNCTION_CLEARANCE:-0} == 1 ]] && echo true || echo false)
bayline_stock_regal_preview = $([[ ${BAYLINE_NATIVE_STOCK_REGAL:-0} == 1 ]] && echo true || echo false)
bayline_stock_bus_catalog = $([[ ${BAYLINE_NATIVE_STOCK_FOSTER:-0} == 1 || ${BAYLINE_NATIVE_FLOSS:-0} == 1 ]] && echo true || echo false)
bayline_native_road_faults = $([[ ${BAYLINE_NATIVE_ROAD_FAULTS:-0} == 1 ]] && echo true || echo false)
bayline_native_road_service = $([[ ${BAYLINE_NATIVE_ROAD_SERVICE:-0} == 1 ]] && echo true || echo false)
bayline_stock_bus_breakdowns = $([[ ${BAYLINE_NATIVE_ROAD_FAULTS:-0} == 1 || ${BAYLINE_NATIVE_ROAD_SERVICE:-0} == 1 ]] && echo 2 || echo 0)
bayline_stock_bus_service_interval = $([[ ${BAYLINE_NATIVE_ROAD_SERVICE:-0} == 1 ]] && echo 150 || echo 0)
bayline_stock_bus_start_year = $(if [[ ${BAYLINE_NATIVE_FLOSS:-0} == 1 ]]; then echo 1966; elif [[ ${BAYLINE_NATIVE_STOCK_FOSTER:-0} == 1 ]]; then echo 1995; else echo 1950; fi)
bayline_native_depot_return = $([[ ${BAYLINE_NATIVE_DEPOT_RETURN:-0} == 1 ]] && echo true || echo false)
bayline_road_bay_preview = $([[ ${BAYLINE_NATIVE_ROAD_BAY:-0} == 1 ]] && echo true || echo false)
bayline_native_passing = $([[ ${BAYLINE_NATIVE_PASSING:-0} == 1 ]] && echo true || echo false)
bayline_native_overtake = ${BAYLINE_NATIVE_OVERTAKE:-off}
bayline_native_turns = $([[ ${BAYLINE_NATIVE_TURNS:-0} == 1 ]] && echo true || echo false)
bayline_stock_workbenches = false
luanttd_qa_coastal_layout = false
luanttd_qa_plain_layout = true
bayline_stock_coastal_flood = $([[ ${BAYLINE_NATIVE_COAST:-0} == 1 ]] && echo true || echo false)
debug_log_level = $([[ ${BAYLINE_NATIVE_CAMERA:-0} == 1 ]] && echo verbose || echo action)
EOF
if [[ ${BAYLINE_NATIVE_AIR_FLEET:-0} != 1 ]]; then
  printf 'bayline_preview_paid_air = %s\n' "$([[ ${BAYLINE_NATIVE_PAID_AIR:-0} == 1 ]] && echo true || echo false)" >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_ALL_WORKBENCHES:-0} == 1 ]]; then
  # Exercise the preset without the fixture's explicit optional false values.
  sed -i -E '/^(bayline_.*_preview|bayline_preview_paid_(rail|ferry|air)|bayline_preview_coal_industry|bayline_stock_workbenches) = false$/d' "$out/server.conf"
  printf 'bayline_stock_workbenches = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_COASTAL_CIRCUIT:-0} == 1 || ${BAYLINE_NATIVE_CLEAR_AREA:-0} == 1 || ${BAYLINE_NATIVE_AUTORAIL:-0} == 1 || ${BAYLINE_NATIVE_ROAD_BEND:-0} == 1 || ${BAYLINE_NATIVE_ELECTRIC_GUI:-0} == 1 ]]; then
  # These legacy fixtures use known coastal test circuit coordinates and the
  # stock feature defaults. Set the scenario explicitly.
  sed -i -E '/^bayline_/ { /^bayline_seconds_per_day = /!d; }' "$out/server.conf"
  printf 'luanttd_qa_coastal_layout = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_AUTORAIL:-0} == 1 || ${BAYLINE_NATIVE_ROAD_BEND:-0} == 1 || ${BAYLINE_NATIVE_ORDER_MODAL:-0} == 1 ]]; then
  # Compare actual construction and order debits without unrelated month-end costs.
  sed -i 's/^bayline_seconds_per_day = .*/bayline_seconds_per_day = 600/' "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_ELECTRIC_GUI:-0} == 1 ]]; then
  sed -i 's/^bayline_seconds_per_day = .*/bayline_seconds_per_day = 1.20/' "$out/server.conf"
  printf 'bayline_stock_bus_start_year = %s\nbayline_offline_economy = false\n' "${BAYLINE_NATIVE_ELECTRIC_YEAR:-1970}" >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_ROAD_BEND:-0} == 1 ]]; then
  printf 'bayline_native_road_bend = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_CROSSING_CONNECT_GUI:-0} == 1 ]]; then
  printf 'bayline_native_crossing_connect = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_GENERATED_WORLD:-0} == 1 ]]; then
  sed -i -E '/^bayline_/ { /^bayline_seconds_per_day = /!d; }' "$out/server.conf"
  if [[ ${BAYLINE_NATIVE_GENERATED_DEFAULT:-0} == 1 ]]; then
    # No profile selector or game feature settings, just accelerate days.
    [[ ${BAYLINE_NATIVE_GENERATED_MIXED:-0} != 1 && ${BAYLINE_NATIVE_GENERATED_RIVER:-0} != 1 &&
       ${BAYLINE_NATIVE_GENERATED_SCALE:-0} != 1 ]]
    ! grep '^bayline_' "$out/server.conf" | grep -v '^bayline_seconds_per_day = '
  else
    printf 'bayline_stock_generated_world = true\nbayline_offline_economy = false\n' >> "$out/server.conf"
  fi
  if [[ ${BAYLINE_NATIVE_GENERATED_MIXED:-0} == 1 ]]; then
    printf 'bayline_generated_mixed_freight = true\n' >> "$out/server.conf"
  fi
  if [[ ${BAYLINE_NATIVE_GENERATED_RIVER:-0} == 1 ]]; then
    printf 'bayline_generated_rivers = 3\nbayline_generated_min_river_length = 2\n' >> "$out/server.conf"
  fi
  if [[ ${BAYLINE_NATIVE_GENERATED_SCALE:-0} == 1 ]]; then
    printf 'bayline_generated_map_size = 128\nbayline_generated_relief = 3\nbayline_generated_rivers = 1\nbayline_generated_mixed_freight = true\n' >> "$out/server.conf"
  fi
fi
if [[ ${BAYLINE_NATIVE_CLEAR_AREA:-0} == 1 ]]; then
  printf 'bayline_native_clear_area = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_WATER_EFFECTS:-0} == 1 ]]; then
  printf 'bayline_native_water_effects = true\ntime_speed = 0\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_BUOY:-0} == 1 ]]; then
  printf 'bayline_native_buoy = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_RAIL_WAYPOINT:-0} == 1 ]]; then
  printf 'bayline_native_rail_waypoint = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_STOCK_WATER_GUI:-0} == 1 ]]; then
  printf 'bayline_native_stock_water_gui = true\n' >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_ROAD_BAY_DEFAULT:-0} == 1 ]]; then
  # Ordinary player default: leave the two-bay setting absent. The
  # test selector is only an environment variable for the driver.
  [[ ${BAYLINE_NATIVE_ROAD_BAY:-0} == 1 && ${BAYLINE_NATIVE_FRESH:-0} == 1 ]]
  [[ -z ${BAYLINE_NATIVE_STOCK_LOADING:-} && -z ${BAYLINE_NATIVE_STOCK_CLOCK:-} ]]
  sed -i '/^bayline_road_bay_preview =/d' "$out/server.conf"
fi
if [[ -n ${BAYLINE_NATIVE_STOCK_CLOCK:-} ]]; then
  printf 'bayline_preview_stock_bus_clock = %s\n' "$([[ $BAYLINE_NATIVE_STOCK_CLOCK == 1 ]] && echo true || echo false)" >> "$out/server.conf"
fi
if [[ -n ${BAYLINE_NATIVE_STOCK_LOADING:-} ]]; then
  printf 'bayline_preview_stock_road_loading = %s\n' "$([[ $BAYLINE_NATIVE_STOCK_LOADING == 1 ]] && echo true || echo false)" >> "$out/server.conf"
fi
if [[ -n ${BAYLINE_NATIVE_3D_GUARD:-} ]]; then
  printf 'bayline_road_3d_junction_clearance = %s\n' "$([[ $BAYLINE_NATIVE_3D_GUARD == 1 ]] && echo true || echo false)" >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_JUNCTION_CLEARANCE:-0} == 1 ]]; then
  printf 'bayline_preview_stock_road_loading = true\n' >> "$out/server.conf"
fi
if [[ -n ${BAYLINE_NATIVE_STOCK_HOUSES:-} ]]; then
  printf 'bayline_preview_stock_house_supply = %s\n' "$([[ $BAYLINE_NATIVE_STOCK_HOUSES == 1 ]] && echo true || echo false)" >> "$out/server.conf"
fi
if [[ ${BAYLINE_NATIVE_GRADE:-0} == 1 ]]; then
  dir="$out/games/luanttd/mods/luanttd_core"
  mv "$dir/terrain_preview.lua" "$dir/terrain_preview_original.lua"
  cp tests/native_grade_preset.lua "$dir/"
  cat > "$dir/terrain_preview.lua" <<'LUA'
local folder=core.get_modpath("luanttd_core")
return dofile(folder.."/native_grade_preset.lua")(dofile(folder.."/terrain_preview_original.lua"))
LUA
  sed -i "s/bayline_seconds_per_day = .*/bayline_seconds_per_day = 1.12/" "$out/server.conf"
  cat >> "$out/server.conf" <<'EOF'
bayline_preview_terrain = true
bayline_native_grade = true
EOF
fi
cat > "$out/client.conf" <<'EOF'
screen_w = 1500
screen_h = 925
enable_sound = false
fullscreen = false
viewing_range = 100
fps_max = 30
gui_scaling = 1.0
EOF
if [[ ${BAYLINE_NATIVE_WATER_EFFECTS:-0} == 1 ]]; then
  cat >> "$out/client.conf" <<'WATERFX'
enable_shaders = true
enable_waving_water = true
enable_dynamic_shadows = true
enable_water_reflections = true
shadow_map_resolution = 512
water_wave_height = 0.16
water_wave_length = 14
water_wave_speed = 2.4
WATERFX
fi
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
opts=(-nolisten tcp)
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC "$repo/tests/native_loopback.c" -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$disp"
  opts=(-listen tcp -nolisten unix -nolisten local)
  lib=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
else
  lib=()
fi
touch "$XAUTHORITY"
cookie=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$cookie"
"${lib[@]}" Xvfb ":$disp" -screen 0 1500x925x24 "${opts[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
check+=("$!")
for _ in {1..40}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .25; done
if ! xdpyinfo >/dev/null 2>&1; then cat "$out/xvfb.log"; exit 1; fi
python3 tests/native_ui.py "$out" "$port" "${BAYLINE_LUANTI_SERVER:-luantiserver}" "${BAYLINE_LUANTI_CLIENT:-luanti}"
