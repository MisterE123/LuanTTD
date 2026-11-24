#!/usr/bin/env bash
set -euo pipefail
# Independent, balanced slices of the complete native suite.
cd "$(dirname "$0")/../.."
export PATH="/usr/games:$PATH"
# Hardlink the media into disposable native worlds on the same mount.
export TMPDIR="$(mktemp -d "${GITHUB_WORKSPACE:-$PWD}/.native-ci.XXXXXX")"
trap 'rm -rf -- "$TMPDIR"' EXIT
case "${1:-}" in
  startup)
    luantiserver --version
    bash tests/default_stock_terrain_native.sh
    python3 tests/generated_world_dimensions_native.py "$(mktemp -d)/worlds"
    bash tests/default_tram_native.sh
    bash tests/async_state_owner_native.sh "$(command -v luantiserver)" "$(mktemp -d)/ipc"
    bash tests/campaign_generation_async_native.sh "$(command -v luantiserver)" "$(mktemp -d)/generation"
    bash tests/campaign_tick_worker_native.sh "$(command -v luantiserver)" "$(mktemp -d)/ticks"
    bash tests/campaign_ordinary_worker_native.sh
    bash tests/campaign_worker_recovery_native.sh
    bash tests/daylight_native.sh
    bash tests/stock_town_city_native.sh
    ;;
  stock-rail)
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
  native-map-art)
    export LUANTTD_NATIVE_MEDIA_CACHE="$TMPDIR/cache"
    python3 tests/cache_luanti_game_media.py . "$LUANTTD_NATIVE_MEDIA_CACHE"
    LUANTTD_QA_AIR_LAYOUT=heliport LUANTTD_QA_AIR_YEAR=1963 LUANTTD_QA_AIR_RESTART=1 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_AIR_LAYOUT=ground_rotary LUANTTD_QA_AIR_YEAR=1980 LUANTTD_QA_AIR_RESTART=1 bash tests/stock_city_airport_native.sh
    LUANTTD_QA_STEEL_LAYOUT=1 bash tests/stock_steel_mill_layout_native.sh
    LUANTTD_QA_STEEL_LAYOUT=0 bash tests/stock_steel_mill_layout_native.sh
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
    LUANTTD_NATIVE_COLLISION=true bash tests/rail_owned_live_native.sh
    ;;
  *) printf 'Unknown native regression suite: %s\n' "${1:-}" >&2; exit 2 ;;
esac
