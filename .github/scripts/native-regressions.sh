#!/usr/bin/env bash
set -euo pipefail
# Independent, balanced slices of the complete native suite.
cd "$(dirname "$0")/../.."
export PATH="/usr/games:$PATH"
# Hardlink the media into disposable native worlds on the same mount.
export TMPDIR="$(mktemp -d "${GITHUB_WORKSPACE:-$PWD}/.native-ci.XXXXXX")"
trap 'rm -rf -- "$TMPDIR"' EXIT
case "${1:-}" in
  stock-dry-ships)
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/ship-stock-media"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE" --hardlink
    for cargo in goods grain livestock wood iron_ore steel valuables mail; do
      LUANTTD_QA_OTHER_SHIP=211 LUANTTD_QA_OTHER_SHIP_YEAR=1950 LUANTTD_QA_OTHER_SHIP_CARGO="$cargo" bash tests/stock_other_ship_native.sh
    done
    ;;
  startup)
    luantiserver --version
    lua5.1 tests/town_growth_stock_replay.lua
    lua5.1 tests/town_growth_rc1_coherent.lua
    lua5.1 tests/town_growth_rc1_two_buses.lua
    lua5.1 tests/world_startup_rc1.lua
    lua5.1 tests/stock_road_acceleration_live.lua
    lua5.1 tests/stock_road_day_live.lua
    lua5.1 tests/road_breakdowns.lua
    lua5.1 tests/stock_subsidy_world_replay.lua
    lua5.1 tests/stock_subsidy_host.lua
    lua5.1 tests/stock_subsidy_road_live.lua
    lua5.1 tests/subsidy_board_ui.lua
    lua5.1 tests/town_industry_month_order.lua
    lua5.1 tests/industry_openings_economy_tick.lua
    lua5.1 tests/road_stock_loading_live.lua
    lua5.1 tests/timber_industry.lua
    lua5.1 tests/town_municipal_roads.lua
    lua5.1 tests/town_growth_live.lua
    bash tests/default_stock_terrain_native.sh
    python3 tests/generated_world_dimensions_native.py "$(mktemp -d)/worlds"
    bash tests/default_tram_native.sh
    bash tests/async_state_owner_native.sh "$(command -v luantiserver)" "$(mktemp -d)/ipc"
    bash tests/campaign_generation_async_native.sh "$(command -v luantiserver)" "$(mktemp -d)/generation"
    bash tests/campaign_tick_worker_native.sh "$(command -v luantiserver)" "$(mktemp -d)/ticks"
    for mode in woodhouse farmhouse underhouse railunderhouse foreignhouse crossing companyroad mixedroad construction months; do
      LUANTTD_QA_MUNICIPAL_KIND="$mode" bash tests/town_municipal_roads_native.sh "$(command -v luantiserver)" "$(mktemp -d)/$mode"
    done
    bash tests/campaign_ordinary_worker_native.sh
    bash tests/hotbar_task_native.sh
    bash tests/campaign_worker_recovery_native.sh
    bash tests/campaign_paid_process_crash_native.sh
    LUANTTD_QA_CRASH_AXIS=512 bash tests/campaign_paid_process_crash_native.sh
    bash tests/daylight_native.sh
    LUANTTD_QA_HOUSE_AUTOSLOPE=true bash tests/stock_town_city_native.sh
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/residential-cache"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE"
    BAYLINE_NATIVE_DISPLAY=355 BAYLINE_NATIVE_PORT=43372 timeout --kill-after=10s 155 bash tests/campaign_worker_stock_residential_native.sh
    BAYLINE_NATIVE_DISPLAY=358 BAYLINE_NATIVE_PORT=43375 timeout --kill-after=10s 120 bash tests/campaign_worker_stock_construction_native.sh
    LUANTTD_QA_TOWN_LIFT=1 LUANTTD_QA_TOWN_YEAR=1985 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=359 BAYLINE_NATIVE_PORT=43376 timeout --kill-after=10s 155 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_TOWN_REBUILD=1 BAYLINE_NATIVE_DISPLAY=361 BAYLINE_NATIVE_PORT=43378 timeout --kill-after=10s 160 bash tests/campaign_worker_stock_residential_native.sh
    ;;
  native-terrain-services)
    LUANTTD_QA_NORMAL_RIVER=1 LUANTTD_QA_OIL_PUMP=1 BAYLINE_QA_OWNER=1 BAYLINE_NATIVE_DISPLAY=369 timeout --kill-after=10s 150 bash tests/world_setup_native.sh
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/terrain-service-cache"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE"
    LUANTTD_QA_AIRPORT_NOISE=1 LUANTTD_QA_TOWN_YEAR=1985 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=363 BAYLINE_NATIVE_PORT=43380 timeout --kill-after=10s 175 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_ROCKY_FERRY=1 LUANTTD_QA_TOWN_YEAR=1985 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=364 BAYLINE_NATIVE_PORT=43381 timeout --kill-after=10s 215 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_JOINED_FERRY=1 LUANTTD_QA_JOINED_DOCK_UI=1 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=370 BAYLINE_NATIVE_PORT=43383 timeout --kill-after=10s 190 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_JOINED_FERRY=1 LUANTTD_QA_JOINED_DOCK_UI=1 LUANTTD_QA_JOINED_ACTIVE_REMOVE=1 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=372 BAYLINE_NATIVE_PORT=43387 timeout --kill-after=10s 195 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_VOXEL_STORM=1 ALSOFT_DRIVERS=null BAYLINE_NATIVE_DISPLAY=376 BAYLINE_NATIVE_PORT=43389 timeout --kill-after=10s 155 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_DOCK_GROVE=1 LUANTTD_QA_TOWN_WIDTH=256 BAYLINE_NATIVE_DISPLAY=371 BAYLINE_NATIVE_PORT=43386 timeout --kill-after=10s 160 bash tests/campaign_worker_stock_residential_native.sh
    LUANTTD_QA_CANAL_DIKES=1 BAYLINE_NATIVE_DISPLAY=365 BAYLINE_NATIVE_PORT=43382 timeout --kill-after=10s 170 bash tests/campaign_worker_stock_residential_native.sh
    ;;
  stock-rail)
    BAYLINE_NATIVE_PORT=43385 BAYLINE_NATIVE_STEAM_START_YEAR=1972 BAYLINE_NATIVE_ELECTRIC=true LUANTTD_NATIVE_RAIL_PAIR_WIRE=true bash tests/rail_owned_live_native.sh
    BAYLINE_NATIVE_PORT=43384 BAYLINE_NATIVE_STEAM_START_YEAR=1972 BAYLINE_NATIVE_ELECTRIC=true LUANTTD_NATIVE_RAIL_COMPOUND_WIRE=true bash tests/rail_owned_live_native.sh
    lua5.1 tests/stock_rail_metals_roster.lua
    python3 tests/stock_rail_metals_art.py
    bash tests/stock_rail_metals_live_native.sh
    lua5.1 tests/stock_rail_valuables_roster.lua
    lua5.1 tests/stock_rail_farm_roster.lua
    lua5.1 tests/stock_rail_wood_roster.lua
    python3 tests/stock_rail_armoured_van_art.py
    python3 tests/stock_rail_farm_art.py
    python3 tests/stock_rail_wood_truck_art.py
    bash tests/stock_rail_valuables_live_native.sh
    bash tests/stock_rail_farm_live_native.sh
    bash tests/stock_rail_mail_live_native.sh
    bash tests/stock_sh125_mail_worker_native.sh
    bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_MIXED_FORM=mail-coach-mail bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_MIXED_FORM=monorail bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_MIXED_FORM=monorail-spans bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_MIXED_FORM=maglev bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_MIXED_FORM=maglev-spans bash tests/stock_mixed_town_rail_live_native.sh
    BAYLINE_OIL_GAUGE=2 bash tests/guideway_oil_worker_native.sh
    BAYLINE_OIL_GAUGE=3 bash tests/guideway_oil_worker_native.sh
    bash tests/stock_rail_multi_ore_live_native.sh
    bash tests/stock_dash_worker_native.sh
    BAYLINE_DMU_PROFILE=millennium bash tests/stock_dash_worker_native.sh
    bash tests/rail_copy_orders_worker_native.sh
    bash tests/stock_tim_worker_native.sh
    LUANTTD_NATIVE_ASIASTAR=true bash tests/stock_tim_worker_native.sh
    LUANTTD_NATIVE_TIM=true BAYLINE_NATIVE_ELECTRIC_BRIDGE=true BAYLINE_NATIVE_STEAM_START_YEAR=1988 bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_ASIASTAR=true BAYLINE_NATIVE_ELECTRIC_BRIDGE=true BAYLINE_NATIVE_STEAM_START_YEAR=1995 bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_DASH=true BAYLINE_NATIVE_STEAM_START_YEAR=1988 bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_DASH_COACH=true BAYLINE_NATIVE_STEAM_START_YEAR=1988 bash tests/rail_owned_live_native.sh
    bash tests/stock_rail_wood_live_native.sh
    BAYLINE_WOOD_MIXED=true bash tests/stock_rail_wood_live_native.sh
    ;;
  industry-air-and-water)
    lua5.1 tests/iron_steel_kernels.lua
    lua5.1 tests/campaign_worker_truck_stop_ui.lua
    for profile in early mid late; do lua5.1 tests/iron_steel_ordinary_worker.lua "$profile"; done
    python3 tests/stock_iron_ore_road_art.py
    python3 tests/stock_steel_trucks_art.py
    python3 tests/stock_metal_industry_art.py
    lua5.1 tests/temperate_bank_kernel.lua
    lua5.1 tests/temperate_bank_world.lua
    for profile in early mid late; do lua5.1 tests/temperate_bank_ordinary_worker.lua "$profile"; done
    python3 tests/stock_temperate_bank_art.py
    bash tests/temperate_bank_native.sh
    python3 tests/stock_armoured_trucks_art.py
    lua5.1 tests/oil_ship_ordinary_worker.lua 204
    lua5.1 tests/oil_ship_ordinary_worker.lua 205
    lua5.1 tests/oil_ship_ordinary_worker.lua 204 mixed
    lua5.1 tests/oil_rig_rules.lua
    lua5.1 tests/offshore_rig_world.lua
    lua5.1 tests/oil_rig_helicopter.lua
    lua5.1 tests/oil_ship_ordinary_worker.lua 204 offshore
    lua5.1 tests/oil_ship_ordinary_worker.lua 204 neutral_only
    lua5.1 tests/industry_openings_runtime.lua
    manifest="$(mktemp -d)"
    for media in models textures; do find mods/luanttd_core/"$media" -maxdepth 1 -type f -printf '%f\n' > "$manifest/$media"; done
    lua5.1 tests/offshore_generated_opening.lua "$manifest"
    lua5.1 tests/offshore_rotary_worker.lua
    lua5.1 tests/offshore_rotary_worker.lua city
    python3 tests/stock_oil_rig_art.py
    python3 tests/stock_tricario_art.py
    bash tests/stock_offshore_tanker_worker_native.sh
    LUANTTD_QA_SUBSIDY_MULTIPLIER=2 bash tests/stock_offshore_tanker_worker_native.sh
    bash tests/offshore_rotary_worker_native.sh
    LUANTTD_QA_ROTARY_FIELD=city bash tests/offshore_rotary_worker_native.sh
    LUANTTD_QA_ROTARY_MODEL=254 bash tests/offshore_rotary_worker_native.sh
    LUANTTD_QA_RIG_HELICOPTER=guru_x2 bash tests/stock_oil_rig_art_native.sh
    bash tests/stock_oil_rig_art_native.sh
    lua5.1 tests/coal_ship_ordinary_worker.lua 211
    lua5.1 tests/coal_ship_ordinary_worker.lua 212
    lua5.1 tests/rail_paid_runtime.lua 208
    python3 tests/stock_hovercraft_art.py
    python3 tests/stock_bakewell_cargo_art.py
    python3 tests/stock_oil_ships_art.py
    bash tests/generated_oil_freight_native.sh
    bash tests/mixed_freight_live_native.sh
    for engine in 216 218 232 233 237 234 238 235 236 239 247; do LUANTTD_QA_PAID_AIRFRAME="$engine" bash tests/stock_aircraft_mail_live_native.sh; done
    lua5.1 tests/airport_city_paid.lua
    lua5.1 tests/airport_city_paid.lua 217
    lua5.1 tests/airport_city_paid.lua 218
    lua5.1 tests/airport_city_paid.lua 225
    python3 tests/stock_airliners_e_art.py
    lua5.1 tests/airport_city_paid.lua 220
    lua5.1 tests/airport_city_paid.lua 228
    for engine in 227 229 230 231; do lua5.1 tests/airport_city_paid.lua "$engine"; done
    python3 tests/darwin_family_art.py
    for engine in 232 233 237 234 238 235 236 239 247; do lua5.1 tests/airport_city_paid.lua "$engine"; done
    python3 tests/guru_airtaxi_art.py
    python3 tests/guru_x2_art.py
    lua5.1 tests/darwin_city_art_trace.lua > "$TMPDIR/a34-dinger-city-poses.txt"
    python3 tests/a34_dinger_1000_clearance.py "$TMPDIR/a34-dinger-city-poses.txt"
    for engine in 221 222 223 224; do lua5.1 tests/airport_city_paid.lua "$engine"; done
    python3 tests/bakewell_luckett_art.py
    python3 tests/stock_airliners_g_art.py
    python3 tests/city_airport_art.py
    ;;
  native-airfield-art)
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/cache"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE"
    LUANTTD_QA_AIR_LAYOUT=commuter LUANTTD_QA_AIR_YEAR=1985 LUANTTD_QA_AIRFRAME=237 LUANTTD_QA_AIR_RESTART=1 timeout --kill-after=10s 165 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_AIR_LAYOUT=metropolitan LUANTTD_QA_AIR_YEAR=1985 LUANTTD_QA_AIRFRAME=222 LUANTTD_QA_AIR_RESTART=1 timeout --kill-after=10s 165 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_AIR_LAYOUT=heliport LUANTTD_QA_AIR_YEAR=1963 LUANTTD_QA_AIR_RESTART=1 timeout --kill-after=10s 165 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_AIR_LAYOUT=ground_rotary LUANTTD_QA_AIR_YEAR=1980 LUANTTD_QA_AIR_RESTART=1 timeout --kill-after=10s 265 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_AIR_LAYOUT=city LUANTTD_QA_AIR_YEAR=1985 LUANTTD_QA_AIRFRAME=222 LUANTTD_QA_AIR_AUTOSLOPE=true LUANTTD_QA_AIR_RESTART=1 BAYLINE_NATIVE_DISPLAY=352 BAYLINE_NATIVE_PORT=43369 timeout --kill-after=10s 170 bash tests/stock_city_airport_native.sh
    ;;
  native-map-art)
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/cache"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE"
    BAYLINE_NATIVE_DISPLAY=347 BAYLINE_NATIVE_PORT=43364 timeout 135 bash tests/industry_alternate_native.sh
    lua5.1 tests/roadside_crossing_ground.lua
    LUANTTD_NATIVE_GROUND_FIXTURE=crossings BAYLINE_NATIVE_DISPLAY=348 BAYLINE_NATIVE_PORT=43365 timeout 125 bash tests/industry_alternate_native.sh
    lua5.1 tests/road_autoslope.lua
    LUANTTD_NATIVE_GROUND_FIXTURE=road_autoslope BAYLINE_NATIVE_DISPLAY=349 BAYLINE_NATIVE_PORT=43366 timeout 135 bash tests/industry_alternate_native.sh
    LUANTTD_NATIVE_AUTOSLOPE_WAYPOINT=true LUANTTD_NATIVE_GROUND_FIXTURE=road_autoslope BAYLINE_NATIVE_DISPLAY=351 BAYLINE_NATIVE_PORT=43368 timeout 135 bash tests/industry_alternate_native.sh
    LUANTTD_NATIVE_NO_TURN_LOOPS=true LUANTTD_NATIVE_AUTOSLOPE_WAYPOINT=true LUANTTD_NATIVE_GROUND_FIXTURE=road_autoslope BAYLINE_NATIVE_DISPLAY=357 BAYLINE_NATIVE_PORT=43374 timeout 150 bash tests/industry_alternate_native.sh
    lua5.1 tests/typed_crossing_world.lua
    python3 tests/electric_crossing_wire_art.py
    LUANTTD_NATIVE_GROUND_FIXTURE=electric_crossing LUANTTD_NATIVE_START_YEAR=1972 BAYLINE_NATIVE_DISPLAY=350 BAYLINE_NATIVE_PORT=43367 timeout 175 bash tests/industry_alternate_native.sh
    LUANTTD_NATIVE_RAIL_STATION_AUTOSLOPE=true LUANTTD_NATIVE_GROUND_FIXTURE=electric_crossing LUANTTD_NATIVE_START_YEAR=1972 BAYLINE_NATIVE_DISPLAY=353 BAYLINE_NATIVE_PORT=43370 timeout 175 bash tests/industry_alternate_native.sh
    LUANTTD_QA_STEEL_LAYOUT=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_STEEL_LAYOUT=0 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_RAIL_GROUND=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_RAIL_GROUND=2 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_STOCK_TREES=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_PLANT_TREES=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_SHORE_TREES=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_SPLIT_RAIL=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_WET_RAIL=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_MULTICOAST_RAIL=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_ROADSIDE=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_OWNED_LAND=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_TOWN_STATUE=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_COMPANY_HQ=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_SPLIT_FENCE=1 bash tests/stock_steel_mill_layout_native.sh
    ;;
  rail-dispatch)
    python3 tests/rail_early_diesel_art.py
    for n in 13 14; do
      BAYLINE_NATIVE_GOODS_ENGINE="$n" BAYLINE_NATIVE_GOODS_YEAR=1968 bash tests/rail_goods_live_native.sh
    done
    BAYLINE_NATIVE_GOODS_ENGINE=13 BAYLINE_NATIVE_GOODS_YEAR=1976 LUANTTD_NATIVE_CRAIGHEAD=true bash tests/rail_goods_live_native.sh
    LUANTTD_NATIVE_PASSENGER_AND_GOODS=true bash tests/rail_goods_live_native.sh
    for year in 1950 1980; do LUANTTD_NATIVE_FERRY_YEAR="$year" bash tests/ship_coal_live_native.sh; done
    LUANTTD_NATIVE_COAL_ORDERS=true bash tests/ship_coal_live_native.sh
    LUANTTD_NATIVE_FREIGHT_ORDER_EDIT=true bash tests/rail_goods_live_native.sh
    LUANTTD_NATIVE_ORDER_SEQUENCE=true LUANTTD_NATIVE_CARGO_ORDER_EDIT=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_ORDER_SEQUENCE=true LUANTTD_NATIVE_LIVE_ORDER_EDIT=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_ORDER_SEQUENCE=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_SIGNAL_FREE=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_DEPOT_TURNOUT=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_MIXED_FLEET=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_TWO_COACHES=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_DISCONNECTED_PBS=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_SHARED_DEPOT=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_RAIL_FLOOD=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_RAIL_FLOOD=true LUANTTD_NATIVE_RAIL_FLOOD_SIGNALS=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_RAIL_FLOOD=true LUANTTD_NATIVE_RAIL_FLOOD_PLATFORM=true bash tests/rail_owned_live_native.sh
    LUANTTD_NATIVE_COLLISION=true bash tests/rail_owned_live_native.sh
    ;;
  *) printf 'Unknown native regression suite: %s\n' "${1:-}" >&2; exit 2 ;;
esac
