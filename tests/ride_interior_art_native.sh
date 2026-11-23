#!/usr/bin/env bash
# Native first-person mesh media smoke in a disposable, loopback-only scene.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-native-interior-art.XXXXXX")
echo "$out"
mod="$out/games/interiortest/mods/interiortest"
mkdir -p "$mod"/{models,textures} "$out/world" "$out/home" "$out/cache"
cp mods/luanttd_core/models/bl_ride_*.obj "$mod/models/"
cp mods/luanttd_core/textures/bl_ride_*.png "$mod/textures/"
printf 'name = interiortest\n' > "$mod/mod.conf"
printf 'title = Interior QA\nallowed_mapgens = singlenode\n' > "$out/games/interiortest/game.conf"
printf 'gameid = interiortest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$mod/init.lua" <<'LUA'
local tex="bl_ride_bus_interior.png"
local function block(name,tint)
 core.register_node("interiortest:"..name,{description=name,tiles={tex.."^[resize:1x1^[colorize:"..tint..":240"}, groups={crumbly=1}})
end
block("meadow","#6F994C")
block("ballast","#858378")
block("wall","#B99773")
block("roof","#843C2E")
block("leaf","#4A743D")
block("wood","#6B4A32")
local models={
 bus={"bl_ride_bus_interior",-.020,.117,-.042},
 coach={"bl_ride_train_interior",-.091,.207,-.080},
 cab={"bl_ride_train_cab",.075,.228,-.228},
}
for name,s in pairs(models) do
 core.register_entity("interiortest:"..name,{initial_properties={
  physical=false, pointable=false, static_save=false, visual="mesh",mesh=s[1]..".obj",
  textures={s[1]..".png"},visual_size={x=1,y=1,z=1},backface_culling=true,shaded=false,
 }})
end
local actor,ready
local function node(x,y,z,name) core.set_node({x=x,y=y,z=z},{name="interiortest:"..name}) end
local function make_map()
 for x=-12,12 do for z=-12,12 do node(x,-1,z,math.abs(x)<1 and "ballast" or "meadow") end end
 for _,pos in ipairs({{4,4},{-5,6},{-6,-5},{6,-3},{2,9}}) do
  local x,z=pos[1],pos[2]
  for y=0,3 do node(x,y,z,"wood") end
  for dx=-1,1 do for dz=-1,1 do for y=2,4 do if math.abs(dx)+math.abs(dz)<2 then node(x+dx,y,z+dz,"leaf") end end end end
 end
 for x=3,8 do for z=5,8 do
   node(x,0,z,"wall");node(x,1,z,"wall");node(x,2,z,"roof")
   if z==6 or z==7 then node(x,3,z,"roof") end
 end end
 core.set_timeofday(.36)
end
local function seat(p,name,angle)
 if actor then actor:remove() end
 local s=models[name]
 actor=assert(core.add_entity({x=0,y=.16,z=0},"interiortest:"..name))
 p:set_properties({eye_height=0,visual_size={x=0,y=0,z=0}})
 p:set_physics_override({gravity=0,speed=0,jump=0})
 p:set_pos({x=s[2],y=.16+s[3],z=s[4]})
 p:set_look_horizontal(angle)
 p:set_look_vertical(0.08)
 for _,element in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","basic_debug","chat"}) do
  p:hud_set_flags({[element]=false})
 end
 core.log("action","INTERIOR_VIEW_"..name.."_"..tostring(angle==0 and "front" or "side"))
end
core.register_chatcommand("interior_art",{func=function(name,args)
 local which,angle=args:match("^(%w+) (%w+)$")
 if ready and models[which] then
  seat(core.get_player_by_name(name),which,angle=="front" and 0 or (which=="cab" and -1.27 or 1.27))
 end
end})
core.register_on_joinplayer(function(p)
 core.emerge_area({x=-16,y=-8,z=-16},{x=16,y=8,z=16},function(_,_,n)
  if n~=0 or ready then return end
  core.after(0,function()
   make_map();ready=true
   if p:is_player() then seat(p,"bus",0) end
  end)
 end)
end)
LUA
port=${BAYLINE_NATIVE_PORT:-39230}
display=${BAYLINE_NATIVE_DISPLAY:-377}
cat > "$out/server.conf" <<EOF_SERVER
server_announce = false
bind_address = 127.0.0.1
port = $port
mg_name = singlenode
enable_damage = false
EOF_SERVER
cat > "$out/client.conf" <<'EOF_CLIENT'
screen_w = 1120
screen_h = 700
fullscreen = false
enable_sound = false
fov = 87
viewing_range = 48
enable_shaders = false
EOF_CLIENT
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1120x700x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server="" client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true;fi; if [[ -n "$server" ]];then kill "$server" 2>/dev/null || true;fi;kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
luantiserver --world "$out/world" --gameid interiortest --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..160}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; cat "$out/server.log" "$out/client.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name InteriorTester --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark INTERIOR_VIEW_bus_front
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
sleep 1.2
import -window root "$out/bus-front.png"
for pair in 'bus side' 'coach front' 'coach side' 'cab front' 'cab side'; do
 xdotool key t
 sleep .14
 xdotool type --delay 10 "/interior_art $pair"
 xdotool key Return
 name=${pair/ /_}
 mark "INTERIOR_VIEW_$name"
 sleep .9
 import -window root "$out/${pair/ /-}.png"
done
for path in "$out"/*.png; do [[ -s "$path" ]]; done
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
echo 'PASS NATIVE VEHICLE INTERIOR MEDIA'
