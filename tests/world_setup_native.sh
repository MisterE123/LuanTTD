#!/usr/bin/env bash
# Native Linux singleplayer setup: one click starts real generation,
# one reopen loads the prepared state, and a transient placement failure retries.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-world-setup-native.XXXXXX")
echo "$out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
if [[ -n ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  cp -al "$LUANTTD_NATIVE_MEDIA_CACHE/." "$out/cache/"
fi
cp game.conf "$game/"
cp -al mods "$game/"
if [[ ${BAYLINE_QA_OWNER:-0} == 1 ]]; then
  printf 'return function() return {authoritative_boot=true,interval=.23} end
' >"$game/mods/luanttd_core/qa_layout.lua"
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cat > "$out/probe.lua" <<'LUA'
local previous_show=core.show_formspec
local progress_channel={}
core.show_formspec=function(name,form,body)
  if form=="luanttd_core:generating_world" or form=="luanttd_core:placing_terrain" then
    local pct=body:match(";(%d+)%%%]")
    local stage=body:match("label%[%s*%.55,1.20;([^%]]+)%]")
    if pct and (progress_channel[form]~=pct or (stage or ""):find("Retrying",1,true)) then
      progress_channel[form]=pct
      core.log("action","WORLD_CREATION_PROGRESS "..form.." "..pct.." "..(stage or ""))
    end
  elseif form=="luanttd_core:world_setup" then
    core.log("action","WORLD_CREATION_OPTIONS")
    local seed=body:match("setup_seed;World seed;(%d+)")
    local rivers=body:match("setup_rivers;None,Few,Normal,Many;(%d+)")
    if seed and rivers then core.log("action","WORLD_CREATION_DRAFT "..seed.." "..rivers) end
  end
  return previous_show(name,form,body)
end
LUA
cat "$game/mods/luanttd_core/init.lua" >> "$out/probe.lua"
cat >> "$out/probe.lua" <<'LUA'
assert(placement and Sim.W==128 and Sim.H==128 and S.stock_generated_profile.industries)
assert(core.get_mod_storage():get_string("campaign")=="")
local terrain_witness,river_corner,mine_tile
if core.settings:get_bool("luanttd_qa_normal_river",false) then
  local count=0
  local chosen,score
  for id,t in ipairs(S.tiles) do
    if t.water_class=="river" then
      count=count+1
      local x,z=Sim.xy(id)
      if x>=12 and x<=Sim.W-12 and z>=12 and z<=Sim.H-12 then
        local runs=0
        for dz=-7,7 do for dx=-7,7 do
          local n=S.tiles[Sim.id(x+dx,z+dz)]
          if n.water_class=="river" then runs=runs+1 end
        end end
        if not score or runs>score then chosen,score=id,runs end
      end
    end
  end
  if core.settings:get_bool("luanttd_qa_river_guard",false) then
    assert(chosen)
    local cx,cz=Sim.xy(chosen)
    for dz=-3,3 do for dx=-3,3 do
      local id=Sim.id(cx+dx,cz+dz)
      if not river_corner and S.tiles[id].water_class=="river" then
        local ok,why=Sim.landscape(S,"River Probe","raise",cx+dx,cz+dz,nil,nil,nil,true)
        if not ok and why:find("remove the river",1,true) then river_corner=id end
      end
    end end
    assert(river_corner,"No usable river corner in the viewport")
    S.companies["River Probe"]=nil
  end
  if core.settings:get_bool("luanttd_qa_initial_frontage",false) then
    local done=assert(S.stock_generated_profile.frontage)
    local trace=assert(S.stock_generated_profile.initial_landscape)
    assert(trace.ticks==1280 and trace.houses>0 and trace.passenger>0 and trace.mail>0 and trace.tree_changes>0)
    assert(S.passenger_house_clock.counter==1280 and S.passenger_house_clock.head==trace.next_head)
    assert(trace.start_head==S.stock_generated_profile.river_rng_cursor and S.day==0)
    core.log("action",("WORLD_CREATION_INITIAL_LANDSCAPE ticks=%d trees=%d tides=%d housing=%d passengers=%d mail=%d"):
      format(trace.ticks,trace.tree_changes,trace.tide_changes,trace.houses,trace.passenger,trace.mail))
    assert(done.road>0 and done.decorated>0 and done.fields>0 and done.grown>0)
    local paved,lamp
    for id,t in ipairs(S.tiles) do
      if t.build=="road" and t.road_town and t.roadside=="street_lights" and not lamp then lamp=id end
      if t.build=="road" and t.road_town and t.roadside=="paved" and not paved then paved=id end
    end
    chosen=assert(lamp or paved,"Expected source frontage on an actual generated town street")
    core.log("action",("WORLD_CREATION_INITIAL_FRONTAGE streets=%d decorated=%d fields=%d growth=%d"):
      format(done.road,done.decorated,done.fields,done.grown))
  end
  if core.settings:get_bool("luanttd_qa_industry_machinery",false) then
    local stat=assert(S.stock_generated_profile.initial_landscape)
    assert(stat.industry_machinery>0,"Real pregame ran no industry machinery transitions")
    local keys={}
    for id in pairs(S.stock_coal_industries or {}) do keys[#keys+1]=id end
    table.sort(keys)
    for _,id in ipairs(keys) do
      local mine=S.stock_coal_industries[id]
      if mine.kind=="coal_mine" then
        for _,t in ipairs(mine.tiles) do
          if t.gfx==0 or t.gfx==1 then mine_tile=Sim.id(t.x+1,t.z+1);break end
        end
        if mine_tile then break end
      end
    end
    chosen=assert(mine_tile,"The test world has no working mine model")
    core.log("action","WORLD_CREATION_INDUSTRY_PREGAME transitions="..stat.industry_machinery)
  end
  local x,z=Sim.xy(assert(chosen))
  local _,_,top=api.terrain.tile(chosen)
  local near=mine_tile or core.settings:get_bool("luanttd_qa_initial_frontage",false)
  local offset=mine_tile and 4 or near and 6 or 12
  terrain_witness={x=x*2+offset,y=top+(mine_tile and 5.1 or near and 6 or 11),z=z*2+offset}
  assert(S.seed==1 and count>=10,"Explicit seed should reach the real standard river generator")
  core.log("action","WORLD_CREATION_NATIVE_RIVERS "..count)
end
local raw_place=render.place_world
local once
render.place_world=function(done,notify)
  if not once then
    once=true
    core.log("action","WORLD_CREATION_TEST_EDGES simulating one transient emergence failure")
    return core.after(.15,done,false,"disposable test failure")
  end
  return raw_place(done,notify)
end
local complete,movement_origin,moved,stopped,turned
core.register_globalstep(function()
  local p=core.get_player_by_name("singleplayer")
  if p and not complete and not placement and #api.world.hotbar_layout(p)>0 then
    assert(worker_boot)
    if worker_boot then
      assert(authority.status()=="owned" and api.authority_handoff and not S.companies["singleplayer"])
      local disk=assert(OwnerCheckpoint.read())
      assert(disk.companies["singleplayer"] and disk.stock_generated_profile.width==128)
      core.log("action","WORLD_CREATION_WORKER_READY")
      if river_corner then
        assert(authority.query({kind="terrain_quote",player="singleplayer",
          request={operation="raise",first=river_corner}},function(q)
          assert(q and not q.ok and q.why:find("remove the river",1,true))
          assert(authority.query({kind="terrain_quote",player="singleplayer",
            request={operation="bulldoze",first=river_corner}},function(clear)
            assert(clear and clear.ok and clear.value.cost==10000)
            core.log("action","WORLD_CREATION_RIVER_GUARD protected raise; deliberate Bulldozer available")
          end))
        end))
      end
      if core.settings:get_bool("luanttd_qa_initial_frontage",false) then
        local function check_live(retries)
          assert(retries>0,"Worker did not advance past the pregame clock")
          if not authority.query({kind="clock"},function(q)
            if not q or not q.ok or q.day<1 then return core.after(.12,check_live,retries-1) end
            assert(q.tick==1280+74*q.day,"First gameplay day restarted or repeated pregame ticks")
            core.log("action",("WORLD_CREATION_PREGAME_RESUMED day=%d clock=%d"):format(q.day,q.tick))
          end) then core.after(.12,check_live,retries-1) end
        end
        core.after(.4,check_live,50)
      end
    end
    complete=true
    core.log("action","WORLD_CREATION_PLAYABLE "..S.stock_generated_profile.width)
  end
  if not p or not complete then return end
  if mine_tile and moved and not turned then
    local ref,angle,phase=api.coal_view.witness(mine_tile)
    if ref and phase and angle then
      if not stopped and phase.dir==0 then stopped=angle
      elseif stopped and phase.dir~=0 and math.abs(angle-stopped)>.008 then
        turned=true
        assert(phase.gfx==1 and phase.active)
        core.log("action",("WORLD_CREATION_MINE_MOVING gfx=%d angle=%.3f dir=%d absolute=%d")
          :format(phase.gfx,angle,phase.dir,phase.tick))
      end
    end
  end
  local pos=p:get_pos()
  if not movement_origin and p:get_player_control().right then
    movement_origin=pos
    core.log("action","WORLD_CREATION_STRAFE_INPUT")
  elseif movement_origin and not moved then
    local dx,dz=pos.x-movement_origin.x,pos.z-movement_origin.z
    if dx*dx+dz*dz>=1 then
      moved=true
      core.log("action",string.format("WORLD_CREATION_STRAFE_PASS %.2f",math.sqrt(dx*dx+dz*dz)))
      if terrain_witness then
        core.after(.25,function()
          local user=core.get_player_by_name("singleplayer")
          if not user then return end
          user:set_pos(terrain_witness)
          if mine_tile and not api.lighting.is_always_day() then assert(api.lighting.toggle(user)) end
          user:set_look_horizontal(mine_tile and .71*math.pi or 3*math.pi/4)
          user:set_look_vertical(mine_tile and .85 or .58)
          core.log("action","WORLD_CREATION_RIVER_VIEW")
        end)
      end
    end
  end
end)
LUA
mv "$out/probe.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
cat > "$out/local.conf" <<'CONF'
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
bayline_seconds_per_day = 8
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
CONF
if [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]; then
  printf 'luanttd_qa_normal_river = true\nbayline_generated_relief = 2\n' >> "$out/local.conf"
fi
if [[ ${LUANTTD_QA_INITIAL_FRONTAGE:-0} == 1 ]]; then
  [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]
  printf 'luanttd_qa_initial_frontage = true\n' >> "$out/local.conf"
fi
if [[ ${LUANTTD_QA_RIVER_GUARD:-0} == 1 ]]; then
  [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]
  printf 'luanttd_qa_river_guard = true\n' >> "$out/local.conf"
fi
if [[ ${LUANTTD_QA_INDUSTRY_MACHINERY:-0} == 1 ]]; then
  [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]
  printf '%s\n' 'luanttd_qa_industry_machinery = true' 'bayline_generated_relief = 1' 'bayline_generated_industries = 5' >> "$out/local.conf"
fi
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
disp=${BAYLINE_NATIVE_DISPLAY:-190}
export DISPLAY="127.0.0.1:$disp" HOME="$out/home" XDG_CACHE_HOME="$out/cache" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!
client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true; fi; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
"${BAYLINE_LUANTI_CLIENT:-luanti}" --go --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
waitmark(){ for _ in {1..300}; do grep -q "$1" "$out/client.log" && return; kill -0 "$client" || return 1; sleep .25; done; tail -40 "$out/client.log"; return 1; }
snap(){ import -window root -resize 720x450 -quality 85 "$out/$1.jpg"; }
waitmark WORLD_CREATION_OPTIONS
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
sleep .75
snap options
if [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]; then
  fresh=$(grep 'WORLD_CREATION_DRAFT ' "$out/client.log" | tail -1 | awk '{print $(NF-1)}')
  grep -q "WORLD_CREATION_DRAFT $fresh 3" "$out/client.log"
  [[ $fresh != 1751 ]]
  xdotool mousemove 713 302 click 1
  for _ in {1..40}; do [[ $(grep -c 'WORLD_CREATION_DRAFT ' "$out/client.log") -ge 2 ]] && break; sleep .2; done
  rerolled=$(grep 'WORLD_CREATION_DRAFT ' "$out/client.log" | tail -1 | awk '{print $(NF-1)}')
  [[ $rerolled != "$fresh" ]]
  xdotool mousemove 489 686 click 1
  for _ in {1..40}; do [[ $(grep -c 'WORLD_CREATION_DRAFT ' "$out/client.log") -ge 3 ]] && break; sleep .2; done
  grep 'WORLD_CREATION_DRAFT ' "$out/client.log" | tail -1 | grep -q "WORLD_CREATION_DRAFT $rerolled 3"
  xdotool mousemove 530 301 click 1 key ctrl+a type --clearmodifiers '1'
  sleep .4
  snap normal-river-options
fi
xdotool mousemove 916 686 click 1
for _ in {1..160}; do
  if grep -q 'generating_world 90' "$out/client.log"; then break; fi
  if grep -q 'generating_world 5 ' "$out/client.log" && [[ ! -f "$out/progress.jpg" ]]; then snap progress; fi
  kill -0 "$client"; sleep .18
done
grep -E 'generating_world (0|5|62|87|90) ' "$out/client.log"
sleep 1.5
test -s "$out/world/luanttd-prepared-campaign.chk"
# Direct --go mode can return to the main menu rather than reconnecting.
# Start the already-prepared world once, never rerun the generator there.
if ! grep -q 'WORLD_CREATION_PLAYABLE' "$out/client.log"; then
  kill "$client" 2>/dev/null || true
  wait "$client" || true
  mv "$out/client.log" "$out/first.log"
  "${BAYLINE_LUANTI_CLIENT:-luanti}" --go --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/client.log" 2>&1 &
  client=$!
fi
waitmark WORLD_CREATION_PLAYABLE
sleep .45
snap playable
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
xdotool keydown d
sleep 1.6
xdotool keyup d
grep -q WORLD_CREATION_STRAFE_INPUT "$out/client.log"
grep -q WORLD_CREATION_STRAFE_PASS "$out/client.log"
grep -E 'WORLD_CREATION_(PROGRESS|PLAYABLE|STRAFE_PASS)' "$out/client.log"
grep -q 'placing_terrain 100' "$out/client.log"
grep -q WORLD_CREATION_WORKER_READY "$out/client.log"
if [[ ${LUANTTD_QA_NORMAL_RIVER:-0} == 1 ]]; then
  grep WORLD_CREATION_NATIVE_RIVERS "$out/client.log"
  waitmark WORLD_CREATION_RIVER_VIEW
  sleep 5
  xdotool key F1
  sleep 1
  if [[ ${LUANTTD_QA_INITIAL_FRONTAGE:-0} == 1 ]]; then
    grep WORLD_CREATION_INITIAL_FRONTAGE "$out/client.log"
    grep WORLD_CREATION_INITIAL_LANDSCAPE "$out/client.log"
    waitmark WORLD_CREATION_PREGAME_RESUMED
    grep WORLD_CREATION_PREGAME_RESUMED "$out/client.log"
    import -window root -quality 91 "$out/initial-settled-street.jpg"
  elif [[ ${LUANTTD_QA_INDUSTRY_MACHINERY:-0} == 1 ]]; then
    grep WORLD_CREATION_INDUSTRY_PREGAME "$out/client.log"
    waitmark WORLD_CREATION_MINE_MOVING
    grep WORLD_CREATION_MINE_MOVING "$out/client.log"
    import -window root -quality 91 "$out/stock-mine-machinery.jpg"
  elif [[ ${LUANTTD_QA_RIVER_GUARD:-0} == 1 ]]; then
    waitmark WORLD_CREATION_RIVER_GUARD
    grep WORLD_CREATION_RIVER_GUARD "$out/client.log"
    sleep 2
    import -window root -quality 91 "$out/river-guard.jpg"
  else import -window root -quality 91 "$out/normal-river-landscape.jpg"; fi
fi
grep -q 'disposable test failure' "$out/client.log"
! grep -E 'ERROR\[' "$out/client.log"
