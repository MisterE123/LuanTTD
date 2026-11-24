#!/usr/bin/env bash
# Graphical isolated singleplayer. Lost-window-focus pause comes from
# Luanti itself; no setting or fallback is added to the game.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-worker-focus.XXXXXX")
echo "Native graphical focus evidence: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp "$src/game.conf" "$game/"
if cp -al "$src/mods" "$game/" 2>/dev/null; then
  cp "$game/mods/luanttd_core/init.lua" "$out/fixture-init.lua"
  mv "$out/fixture-init.lua" "$game/mods/luanttd_core/init.lua"
else
  cp -R "$src/mods/." "$game/mods/"
fi
mod="$game/mods/luanttd_core"
cp tests/campaign_worker_focus_geography.lua "$mod/"
if [[ ${LUANTTD_NATIVE_TRAM_PAID:-0} == 1 ]]; then
  sed -i 's/for i=0,10 do/for i=0,11 do/; /local fields=/i\  s.tiles[Sim.id(x+4,z-1)].wood=nil'     "$mod/campaign_worker_focus_geography.lua"
fi
python3 - "$mod/init.lua" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
key='local world_options=WorldSetup.read(core,storage)'
insert='''if storage:get_string(WorldSetup.storage_key)=="" then
  storage:set_string(WorldSetup.storage_key,core.write_json(WorldSetup.defaults(core.settings)))
end
'''
assert key in s
s=s.replace(key,insert+key)
game='local api={Sim=Sim,s=S'
assert game in s
s=s.replace(game, 'if not resumed_owner then dofile(mod.."/campaign_worker_focus_geography.lua")(core,S,Sim,mod) end\n' + game,1)
p.write_text(s)
PY
printf '\n' >> "$mod/init.lua"
fixture=campaign_worker_focus_native
if [[ ${LUANTTD_NATIVE_TRAM_PAID:-0} == 1 ]]; then fixture=tram_paid_render_native; fi
cat "tests/$fixture.lua" >> "$mod/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/native.conf" <<'CONF'
screen_w = 1180
screen_h = 760
fullscreen = false
enable_sound = false
pause_on_lost_focus = true
fps_max = 30
fps_max_unfocused = 12
bayline_seed = 1751
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 6
bayline_generated_town_layout = grid2
CONF
if [[ ${BAYLINE_FOCUS_DEAD_END:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_focus_dead_end = true' >>"$out/native.conf"
elif [[ ${BAYLINE_FOCUS_DEAD_END:-0} == depot ]]; then
  printf '%s\n' 'luanttd_native_focus_terminal_depot = true' >>"$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_ROAD_MUNICIPAL:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_municipal_road = true' 'luanttd_extra_dynamite = false' >>"$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_EXPLICIT_FACILITIES:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_explicit_road_facilities = true' >>"$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_EXPLICIT_FACILITY_UI:-0} == 1 ]]; then
  printf "%s\n" "luanttd_native_explicit_road_ui = true" >>"$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_WAYPOINT:-0} == 1 ]]; then
  printf "%s\n" "luanttd_native_waypoint = true" >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_STOP_AREA:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_road_stop_area = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_STOP_JOIN:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_road_stop_join = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_STOP_MIX:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_road_stop_mix = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_STOP_AUTO:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_road_stop_auto = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TRAM_DRAG:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_tram_drag = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TRAM_FACILITY_INPUT:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_tram_facility_input = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_STOCK_ROAD_PRICE:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_stock_road_price = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TOWN_FUND:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_town_fund = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_ROAD_REBUILD:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_road_rebuild = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TRAM_ROAD_ACCESS:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_tram_road_access = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TRAM_DEDICATED:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_tram_dedicated = true' >> "$out/native.conf"
fi
if [[ ${LUANTTD_NATIVE_TRAM_FLEET:-0} == 1 ]]; then
  printf '%s
' 'luanttd_native_tram_fleet = true' >> "$out/native.conf"
fi
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
display=${BAYLINE_NATIVE_DISPLAY:-369}
export DISPLAY="127.0.0.1:$display"
# Match an ordinary returning client. Test focus/rider behavior, not two
# cold media downloads competing for the same local server's quota.
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME"
fi
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!;client=;sink=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$sink" ]] || kill "$sink" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null
await_log() {
  for ((attempt=1; attempt<=${2:-220}; attempt++)); do
    grep -q "$1" "$log" && return
    kill -0 "$client" 2>/dev/null || break
    sleep .25
  done
  tail -n 60 "$log"; return 1
}
open() {
  log="$out/$1.log"
  luanti --world "$out/world" --go --gameid luanttd --config "$out/native.conf" --logfile '' >"$log" 2>&1 &
  client=$!
  window=$(timeout 20 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
  xdotool windowfocus --sync "$window"
  await_log 'FOCUS_NATIVE_POSITION'
}
open first
if [[ ${LUANTTD_NATIVE_TRAM_PAID:-0} == 1 ]]; then
  buy_streetcar() {
    local run=$1 slot dispatch stage
    slot=$(sed -n 's/.*TRAM_PAID_NATIVE_SLOT //p' "$log" | tail -1)
    xdotool mousemove 590 380 key "$slot"; sleep .7
    xdotool mousedown 1; sleep .32; xdotool mouseup 1
    sleep .55
    xdotool mousedown 1; sleep .32; xdotool mouseup 1
    for stage in first second; do
      printf '%s
' "$stage-$run" > "$out/world/native-focus-step"
      await_log "TRAM_PAID_NATIVE_STAGE $stage-$run"
      sleep .6
      xdotool mousedown 1; sleep .32; xdotool mouseup 1
    done
    dispatch=$(sed -n 's/.*TRAM_PAID_NATIVE_DISPATCH //p' "$log" | tail -1)
    xdotool key "$dispatch"; sleep .55
    xdotool mousedown 1; sleep .32; xdotool mouseup 1
    await_log "TRAM_PAID_NATIVE_OFFER $run "
    import -window root -resize 840x541 "$out/streetcar-offer-$run.jpg"
    xdotool mousemove "${LUANTTD_NATIVE_TRAM_BUY_X:-455}" "${LUANTTD_NATIVE_TRAM_BUY_Y:-428}" click 1
    sleep 1.1; import -window root -resize 840x541 "$out/after-buy-$run.jpg"
  }
  if [[ ${LUANTTD_NATIVE_TRAM_ROAD_ACCESS:-0} == 1 ]]; then
    stop=first
    printf 'pave-%s\n' "$stop" > "$out/world/native-focus-step"
    await_log "TRAM_ROAD_NATIVE_SLOT $stop "
    slot=$(sed -n "s/.*TRAM_ROAD_NATIVE_SLOT $stop //p" "$log" | tail -1)
    xdotool mousemove 590 380 key "$slot"; sleep .6
    xdotool mousedown 1; sleep .38; xdotool mouseup 1
    printf 'check-%s\n' "$stop" > "$out/world/native-focus-step"
    await_log "TRAM_ROAD_NATIVE_PAVED $stop"
    import -window root -resize 840x541 "$out/paved-platform-$stop.jpg"
    printf '%s\n' inspect-direct > "$out/world/native-focus-step"
    await_log TRAM_ROAD_NATIVE_DIRECT
    sleep .45
    import -window root -resize 840x541 "$out/platform-on-existing-pavement.jpg"
    printf '%s\n' ready-to-buy > "$out/world/native-focus-step"
    await_log TRAM_PAID_NATIVE_SLOT
  fi
  buy_streetcar 1
  if [[ ${LUANTTD_NATIVE_TRAM_FLEET:-0} == 1 ]]; then
    printf '%s
' depot-2 > "$out/world/native-focus-step"
    await_log 'TRAM_PAID_NATIVE_STAGE depot-2'
    buy_streetcar 2
  fi
  await_log TRAM_PAID_NATIVE_FARE 480
  sleep .8
  import -window root -resize 840x541 "$out/shared-platform.jpg"
  rm -f -- "$out/world/native-focus-step"
  kill -TERM "$client";wait "$client" || true
  client=
  open reopen
  await_log TRAM_PAID_NATIVE_REOPEN
  grep TRAM_PAID_NATIVE_REOPEN "$log"
  if [[ ${LUANTTD_NATIVE_TRAM_FLEET:-0} == 1 ]]; then
    await_log TRAM_FLEET_NATIVE_REOPEN
    await_log TRAM_FLEET_NATIVE_MANAGE
    manage=$(sed -n 's/.*TRAM_FLEET_NATIVE_MANAGE //p' "$log" | tail -1)
    xdotool mousemove 590 380 key "$manage";sleep .65
    xdotool mousedown 1;sleep .25;xdotool mouseup 1
    await_log TRAM_FLEET_NATIVE_ROSTER
    sleep .5
    import -window root -resize 840x541 "$out/streetcar-roster.jpg"
    xdotool mousemove "${LUANTTD_TRAM_ROW_X:-416}" "${LUANTTD_TRAM_ROW_Y:-283}" click 1; sleep .28
    xdotool mousemove "${LUANTTD_TRAM_RETIRE_X:-763}" "${LUANTTD_TRAM_RETIRE_Y:-487}" click 1
    second=$(sed -n 's/.*TRAM_FLEET_NATIVE_REOPEN primary #[0-9]*, second #\([0-9]*\).*/\1/p' "$log" | tail -1)
    test -n "$second"
    await_log "TRAM_FLEET_NATIVE_CONFIRM.*Retire Streetcar #$second?"
    sleep .38
    import -window root -resize 840x541 "$out/streetcar-retirement.jpg"
    xdotool mousemove "${LUANTTD_TRAM_CONFIRM_X:-438}" "${LUANTTD_TRAM_CONFIRM_Y:-369}" click 1
    await_log TRAM_FLEET_NATIVE_RETIRED
    grep TRAM_FLEET_NATIVE_RETIRED "$log"
  fi
  kill -TERM "$client";wait "$client" || true
  client=
  ! grep -Ei 'ERROR\[|could not load' "$out/"*.log
  rm -rf -- "$out/games" "$out/cache"
  echo "PASS: real native Streetcar Orders, paid modal, stock fare, and reopen: $out"
  exit
fi
printf '%s\n' initial > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT initial'
import -window root "$out/before.png"
xmessage -title FocusSink -geometry 300x125+780+550 "Native test: window outside Luanti." >"$out/xmessage.log" 2>&1 &
sink=$!
target=$(timeout 7 xdotool search --onlyvisible --sync --name FocusSink | tail -n 1)
xdotool windowfocus --sync "$target"
sleep 9
xdotool windowfocus --sync "$window"
# The Luanti setting opened its normal pause menu. Escape resumes the
# engine; there is no LuanTTD restart or recovery menu to dismiss.
xdotool key Escape
sleep 1.3
printf '%s\n' focus-return > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT focus-return'
xdotool keydown d; sleep 1.1; xdotool keyup d
sleep 1
import -window root "$out/after-focus.png"
await_log 'FOCUS_NATIVE_PAID'
kill "$sink" 2>/dev/null || true
sink=
if [[ ${LUANTTD_NATIVE_ROAD_GESTURES:-0} == 1 ]]; then
  do_road() {
    printf '%s\n' "road-$1" > "$out/world/native-focus-step"
    await_log "NATIVE_ROAD_GESTURE_$2"
  }
  do_road x-start X
  slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_X slot=//p' "$log" | tail -1)
  xdotool key "$slot"; sleep .4; xdotool mousedown 1; sleep .5
  do_road x-end X_RELEASE
  sleep .65; import -window root -resize 960x600 "$out/x-preview.jpg"
  xdotool mouseup 1; sleep .85
  do_road check-x X_PASS
  if [[ ${LUANTTD_NATIVE_WAYPOINT:-0} == 1 ]]; then
    sequences=("waypoint WAYPOINT" "erase-waypoint ERASE_WAYPOINT")
    if [[ ${LUANTTD_NATIVE_WAYPOINT_REUSE:-0} == 1 ]]; then
      sequences+=("waypoint WAYPOINT" "erase-waypoint ERASE_WAYPOINT")
    fi
    for spec in "${sequences[@]}"; do
      read -r stage key <<<"$spec"
      local_seen=$(grep -Fc "NATIVE_ROAD_GESTURE_$key slot=" "$log" || true)
      do_road "$stage" "$key"
      for _ in {1..100}; do
        [[ $(grep -Fc "NATIVE_ROAD_GESTURE_$key slot=" "$log" || true) -gt $local_seen ]] && break
        sleep .1
      done
      [[ $(grep -Fc "NATIVE_ROAD_GESTURE_$key slot=" "$log" || true) -gt $local_seen ]]
      slot=$(sed -n "s/.*NATIVE_ROAD_GESTURE_$key slot=//p" "$log" | tail -1)
      xdotool key "$slot"; sleep .4
      xdotool mousedown 1; sleep .55; xdotool mouseup 1
      sleep 1.05
      import -window root -resize 960x600 "$out/$stage.jpg"
      local_seen=$(grep -Fc "NATIVE_ROAD_GESTURE_${key}_PASS" "$log" || true)
      do_road "$stage-done" "${key}_PASS"
      for _ in {1..100}; do
        [[ $(grep -Fc "NATIVE_ROAD_GESTURE_${key}_PASS" "$log" || true) -gt $local_seen ]] && break
        sleep .1
      done
      [[ $(grep -Fc "NATIVE_ROAD_GESTURE_${key}_PASS" "$log" || true) -gt $local_seen ]]
    done
    if [[ ${LUANTTD_NATIVE_WAYPOINT_REUSE:-0} == 1 ]]; then
      await_log NATIVE_ROAD_GESTURE_WAYPOINT_REBUILD_PASS
    fi
  fi
  if [[ ${LUANTTD_NATIVE_TRAM_REMOVE:-0} == 1 ]]; then
    if [[ ${LUANTTD_NATIVE_TRAM_DRAG:-0} == 1 ]]; then
      do_road tram-lay-start TRAM_LAY
      slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_TRAM_LAY slot=//p' "$log" | tail -1)
      xdotool key "$slot"; sleep .4
      xdotool mousedown 1; sleep .45
      do_road tram-lay-end TRAM_LAY_RELEASE
      sleep .65; import -window root -resize 960x600 "$out/tram-lay-preview.jpg"
      xdotool mouseup 1; sleep 1.1
    fi
    do_road tram-remove-start TRAM_REMOVE
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_TRAM_REMOVE slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .4
    xdotool mousedown 1; sleep .45
    do_road tram-remove-end TRAM_REMOVE_RELEASE
    sleep .65; import -window root -resize 960x600 "$out/tram-remove-preview.jpg"
    xdotool mouseup 1; sleep 1.1
    do_road tram-remove-done TRAM_REMOVE_PASS
  fi
  if [[ ${LUANTTD_NATIVE_TRAM_FACILITY_INPUT:-0} == 1 ]]; then
    for spec in "depot DEPOT" "platform PLATFORM"; do
      read -r tool stamp <<<"$spec"
      do_road "tram-facility-$tool" "TRAM_$stamp"
      slot=$(sed -n "s/.*NATIVE_ROAD_GESTURE_TRAM_$stamp slot=//p" "$log" | tail -1)
      xdotool key "$slot"; sleep .55; xdotool mousedown 1; sleep .45; xdotool mouseup 1; sleep 1.05
      import -window root -resize 960x600 "$out/tram-facility-$tool.jpg"
    done
    do_road tram-facility-done TRAM_FACILITY_PASS
  fi
  if [[ ${LUANTTD_NATIVE_TREE_ROAD:-0} == 1 ]]; then
    do_road tree-road TREE_ROAD
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_TREE_ROAD slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .55; xdotool mousedown 1; sleep .45; xdotool mouseup 1; sleep 1.05
    import -window root -resize 960x600 "$out/tree-road.jpg"
    do_road tree-road-done TREE_ROAD_PASS
  fi
  if [[ ${LUANTTD_NATIVE_TOWN_PANEL:-0} == 1 ]]; then
    if [[ ${LUANTTD_NATIVE_TOWN_FUND:-0} == 1 || ${LUANTTD_NATIVE_ROAD_REBUILD:-0} == 1 ]]; then
      do_road town-fund-loans TOWN_FUND_LOANS
    fi
    do_road town-authority TOWN_PANEL
    sleep .45; xdotool mousedown 3; sleep .45; xdotool mouseup 3
    await_log NATIVE_ROAD_GESTURE_TOWN_PANEL_PASS
    sleep .55; import -window root -resize 960x600 "$out/town-authority.jpg"
    if [[ ${LUANTTD_NATIVE_TOWN_FUND:-0} == 1 ]]; then
      xdotool mousemove 590 420 click 1
      sleep 1.2
      import -window root -resize 960x600 "$out/town-funding.jpg"
      do_road town-fund-done TOWN_FUND_PASS
    elif [[ ${LUANTTD_NATIVE_ROAD_REBUILD:-0} == 1 ]]; then
      xdotool mousemove 590 491 click 1
      sleep 1.05
      do_road town-rebuild-done ROAD_REBUILD_PAID
      xdotool key Escape
      do_road town-rebuild-view ROAD_REBUILD_NATIVE
      sleep .55
      import -window root -resize 960x600 "$out/road-rebuild-active.jpg"
      do_road town-rebuild-close ROAD_REBUILD_CLOSE
      sleep .65
      import -window root -resize 960x600 "$out/road-rebuild-close.jpg"
    fi
    if [[ ${LUANTTD_NATIVE_ROAD_REBUILD:-0} != 1 ]]; then xdotool key Escape; fi
  fi
  do_road remove-start REMOVE
  slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_REMOVE slot=//p' "$log" | tail -1)
  xdotool key "$slot"; sleep .4; xdotool mousedown 1; sleep .5
  do_road remove-end REMOVE_RELEASE
  sleep .65; import -window root -resize 960x600 "$out/remove-preview.jpg"
  xdotool mouseup 1; sleep .85
  do_road check-remove REMOVE_PASS
  if [[ ${LUANTTD_NATIVE_STOP_AREA:-0} == 1 ]]; then
    do_road stop-layout STOP_LAYOUT
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_STOP_LAYOUT slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .45
    xdotool click 3
    await_log NATIVE_ROAD_GESTURE_STOP_LAYOUT_OPEN
    sleep .45
    import -window root "$out/road-stop-layout.jpg"
    xdotool mousemove 403 449 click 1
    sleep .45
    xdotool mousedown 1; sleep .45
    do_road stop-end STOP_RELEASE
    sleep .85
    do_road stop-preview STOP_PREVIEW_PASS
    import -window root "$out/road-stop-preview.jpg"
    xdotool mouseup 1; sleep 1.1
    do_road stop-done STOP_ERASE
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_STOP_ERASE slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .4
    xdotool mousedown 1; sleep .4; xdotool mouseup 1
    sleep 1.05
    do_road stop-erase-done STOP_ERASE_PASS
    if [[ ${LUANTTD_NATIVE_STOP_JOIN:-0} == 1 ]]; then
      do_road stop-join STOP_JOIN
      slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_STOP_JOIN slot=//p' "$log" | tail -1)
      xdotool key "$slot"; sleep .4
      xdotool keydown e; xdotool mousedown 1; sleep .4; xdotool mouseup 1
      await_log NATIVE_ROAD_GESTURE_STOP_JOIN_OPEN
      xdotool keyup e; sleep .55
      import -window root "$out/road-stop-join-picker.jpg"
      xdotool mousemove 425 323 click 1
      xdotool mousemove 778 529 click 1
      sleep 1.1
      do_road stop-join-done STOP_JOIN_PASS
      if [[ ${LUANTTD_NATIVE_STOP_MIX:-0} == 1 ]]; then
        do_road stop-mix STOP_MIX
        slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_STOP_MIX slot=//p' "$log" | tail -1)
        xdotool key "$slot"; sleep .4
        if [[ ${LUANTTD_NATIVE_STOP_AUTO:-0} == 1 ]]; then
          xdotool mousedown 1; sleep .35; xdotool mouseup 1
        else
          xdotool click 3
          await_log NATIVE_ROAD_GESTURE_STOP_MIX_OPEN
          sleep .45; xdotool mousemove 403 449 click 1
          sleep .45; xdotool mousedown 1; sleep .4; xdotool mouseup 1
        fi
        sleep 1.35
        import -window root "$out/road-stop-joined-mix.jpg"
        do_road stop-mix-done STOP_MIX_PASS
      fi
    fi
  fi
  if [[ ${LUANTTD_NATIVE_ROAD_MUNICIPAL:-0} == 1 ]]; then
    do_road town-start TOWN
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_TOWN slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .4; xdotool mousedown 1; sleep .5
    do_road town-end TOWN_RELEASE
    sleep .65; import -window root -resize 960x600 "$out/town-preview.jpg"
    xdotool mouseup 1; sleep .85
    do_road check-town TOWN_PASS
  fi
  if [[ ${LUANTTD_NATIVE_EXPLICIT_FACILITY_UI:-0} == 1 ]]; then
    do_road layout LAYOUT
    slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_LAYOUT slot=//p' "$log" | tail -1)
    xdotool key "$slot"; sleep .45
    xdotool click 3
    await_log NATIVE_ROAD_GESTURE_LAYOUT_OPEN
    sleep .5; import -window root -resize 960x600 "$out/road-layout.jpg"
    xdotool mousemove 759 352 click 1
    sleep .5
    xdotool mousedown 1; sleep .2; xdotool mouseup 1
    sleep .85
    do_road layout-done LAYOUT_PASS
  fi
fi
if [[ ${LUANTTD_NATIVE_REJOIN:-0} == 1 ]]; then
  printf '%s\n' set-rejoin > "$out/world/native-focus-step"
  await_log 'FOCUS_NATIVE_REJOIN_SET'
fi
kill -TERM "$client"
wait "$client" || true
client=
open reopened
printf '%s\n' reopen > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT reopen'
if [[ ${LUANTTD_NATIVE_ROAD_GESTURES:-0} == 1 ]]; then
  do_road reopen REOPEN_PASS
  grep 'NATIVE_ROAD_GESTURE_.*PASS' "$out/"{first,reopened}.log
fi
if [[ ${LUANTTD_NATIVE_REJOIN:-0} == 1 ]]; then
  sleep .6
  printf '%s\n' check-rejoin > "$out/world/native-focus-step"
  await_log 'FOCUS_NATIVE_REJOIN_PASS'
  grep 'FOCUS_NATIVE_REJOIN_PASS' "$log"
fi
xdotool keydown d; sleep 1.1; xdotool keyup d
sleep 1
import -window root "$out/after-reopen.png"
python3 - "$out" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
a=(p/'first.log').read_text()
b=(p/'reopened.log').read_text()
def stamp(text,s):
    n=re.search(r'FOCUS_NATIVE_RECEIPT '+s+r' day=(\d+) cash=(\d+) bus=(\d+) delivered=(\d+) revenue=(\d+)',text)
    return tuple(map(int,n.groups()))
initial=stamp(a,'initial')
focus=stamp(a,'focus-return')
reopen=stamp(b,'reopen')
assert focus[0]>initial[0] and reopen[0]>=focus[0] and initial[2]==focus[2]==reopen[2],(initial,focus,reopen)
arrive=re.search(r'FOCUS_NATIVE_PAID bus=(\d+) delivered=(\d+) revenue=(\d+)',a)
bus,paid,revenue=map(int,arrive.groups())
assert bus==focus[2] and paid>focus[3] and reopen[3]>=paid and reopen[4]>=revenue>focus[4]
def movement(log,phase):
    span=log.split('FOCUS_NATIVE_RECEIPT '+phase,1)[1].split('FOCUS_NATIVE_REJOIN_MOVE',1)[0]
    pos=[(float(x),float(z)) for x,y,z in re.findall(r'FOCUS_NATIVE_POSITION (-?\d+.\d+) (-?\d+.\d+) (-?\d+.\d+)',span)]
    return max(abs(x-pos[0][0])+abs(z-pos[0][1]) for x,z in pos)
after_focus=movement(a,'focus-return'); after_reopen=movement(b,'reopen')
assert after_focus>.8 and after_reopen>.8,(after_focus,after_reopen)
assert 'simulation owner stopped' not in a+b
print(f'WORKER_GRAPHICAL_FOCUS_REOPEN_PASS days {initial[0]}→{focus[0]}→{reopen[0]}; movement after focus {after_focus:.2f}, after reopen {after_reopen:.2f}; same company and bus {bus}, {paid} paid passengers')
PY
