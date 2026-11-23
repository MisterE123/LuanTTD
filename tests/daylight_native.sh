#!/usr/bin/env bash
# Actual Luanti runtime, production campaign and native solar engine.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
server=${BAYLINE_LUANTI_SERVER:-luantiserver}
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-daylight.XXXXXX")
echo "Native daylight evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{home,world}
cp -al mods "$game/"
cp game.conf settingtypes.txt "$game/"
mod="$game/mods/luanttd_core"
# Replace the test checkout's init with a private copy before appending.
cp "$mod/init.lua" "$mod/init.native"
mv -f "$mod/init.native" "$mod/init.lua"
cat >> "$mod/init.lua" <<'LUA'
-- Exercise the ordinary speed handler plus the numeric 2× formspec value.
S.chair="DaylightQA"
local actor={get_player_name=function()return S.chair end}
local schedule={{"normal_speed",1,720},{"pause",0,0},{"fast",4,2880},{"form2",2,1440},{"normal_speed",1,720}}
local function exercise(i)
  local row=schedule[i]
  if not row then core.request_shutdown("Game clock synchronization verified",false,0);return end
  if row[1]=="form2" then S.speed=2 else ui.speed(actor,row[1]) end
  assert(S.speed==row[2],"speed switch did not change authoritative sim rate")
  core.after(.22,function() -- next engine step reads the new recorded rate
    assert(tonumber(core.settings:get("time_speed"))==row[3],"wrong native solar speed")
    local first,real,day=core.get_timeofday(),core.get_us_time(),S.day
    core.after(1.3,function()
      local elapsed=(core.get_us_time()-real)/1000000
      local last=core.get_timeofday()
      local advance=(last-first+.5)%1-.5
      local expected=elapsed*row[3]/86400
      assert(math.abs(advance-expected)<.004,"native clock did not follow speed "..row[2])
      if row[2]==0 then assert(advance==0 and S.day==day,"pause changed native clock or date") end
      core.log("action",("DAYLIGHT_RATE sim=%d engine=%d advance=%.5f expected=%.5f economy_days=%d"):
        format(S.speed,row[3],advance,expected,S.day-day))
      exercise(i+1)
    end)
  end)
end
core.register_on_mods_loaded(function() exercise(1) end)
core.register_on_shutdown(function()
  assert(tonumber(core.settings:get("time_speed"))==72,"runtime override changed normal engine configuration")
  core.log("action","DAYLIGHT_CLOCK_PASS")
end)
LUA
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-43992}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 35 "$server" --config "$out/server.conf" --world "$out/world" --gameid luanttd --logfile '' > "$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep -F DAYLIGHT_RATE "$out/server.log"
grep -F DAYLIGHT_CLOCK_PASS "$out/server.log"
if grep -E 'ERROR\[' "$out/server.log"; then exit 1; fi
