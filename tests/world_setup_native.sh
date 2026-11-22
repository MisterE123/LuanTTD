#!/usr/bin/env bash
# Singleplayer stock creation, actual keyboard and dropdown input, blank
# campaign before commit, and the selected world opens in the same save.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${BAYLINE_NATIVE_TOOLS:-}" ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-world-setup-native.XXXXXX")
echo "Native world setup evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-331}
game="$out/games/bayline"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
exact=${BAYLINE_NATIVE_EXACT_GAME:-.}
cp "$exact/game.conf" "$game/"
cp -al "$exact/mods" "$game/" || cp -R "$exact/mods" "$game/"
cat > "$out/instrumented.lua" <<'LUA'
local setup_probe_storage=core.get_mod_storage()
local setup_probe_positions={{x=24,y=-1,z=24},{x=98,y=-1,z=70},{x=192,y=-1,z=152}}
core.register_on_joinplayer(function()
  if setup_probe_storage:get_string("world_setup_v1")~="" then return end
  core.emerge_area({x=16,y=-1,z=16},{x=193,y=0,z=153},function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      for _,pos in ipairs(setup_probe_positions) do assert(core.get_node(pos).name=="air",core.pos_to_string(pos)) end
      core.log("action","STOCK SETUP PREGENERATED AIR in three future landscape chunks")
    end)
  end)
end)
LUA
cat "$game/mods/bayline/init.lua" >> "$out/instrumented.lua"
cat >> "$out/instrumented.lua" <<'LUA'

if api.generated_world then
  local p=S.stock_generated_profile
  assert(S.seed==817516 and p.width==128 and p.depth==128)
  assert(p.settings.terrain_type==1 and p.settings.amount_of_rivers==0 and p.settings.water_borders==0)
  core.log("action","STOCK SETUP GENERATED 128x128 seed "..S.seed)
  local function placed()
    if setup_probe_storage:get_string("world_setup_terrain_placed_v1")~="placed" then core.after(.15,placed);return end
    for _,pos in ipairs(setup_probe_positions) do
      core.load_area(pos)
      local name=core.get_node(pos).name
      local tile=S.tiles[Sim.id(math.floor(pos.x/2),math.floor(pos.z/2))]
      assert(name=="bayline:bedrock",core.pos_to_string(pos).." was "..name..
        " / "..tostring(tile and tile.terrain).." / void="..tostring(tile and tile.stock_void))
      local top={x=pos.x,y=0,z=pos.z}
      assert(core.get_node(top).name~="air",core.pos_to_string(top).." stayed air")
    end
    core.log("action","STOCK SETUP PLACED non-air terrain into all three pregenerated chunks")
  end
  core.after(0,placed)
end
LUA
mv "$out/instrumented.lua" "$game/mods/bayline/init.lua"
cat > "$out/world/world.mt" <<'WORLD'
gameid = bayline
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
WORLD
cat > "$out/local.conf" <<'CONF'
screen_w = 1480
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
CONF
export DISPLAY="127.0.0.1:$disp" HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" LIBGL_ALWAYS_SOFTWARE=1
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1500x925x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 & xv=$!
client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true; fi; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
local_game() {
  "${BAYLINE_LUANTI_CLIENT:-luanti}" --go --world "$out/world" --gameid bayline --config "$out/local.conf" --logfile "" > "$out/$1.log" 2>&1 &
  client=$!
  for _ in {1..180}; do
    kill -0 "$client" 2>/dev/null || { cat "$out/$1.log"; exit 1; }
    grep -q 'singleplayer.*joins game' "$out/$1.log" && break
    sleep .2
  done
  win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
  xdotool windowfocus --sync "$win"
  sleep 2
}
rows() {
  python3 - "$out/world/mod_storage.sqlite" "$1" <<'PY'
import json, sqlite3, sys
with sqlite3.connect(sys.argv[1]) as conn:
    rows=dict(conn.execute("SELECT CAST(key AS TEXT), CAST(value AS TEXT) FROM entries WHERE modname='bayline'"))
if sys.argv[2]=="draft":
    assert not rows, sorted(rows)
else:
    val=json.loads(rows["world_setup_v1"])
    assert val["size"]==128 and val["seed"]==817516 and val["coast"]==0, val
    print(json.dumps(val,indent=2))
PY
}
local_game first
for _ in {1..120}; do grep -q 'STOCK SETUP PREGENERATED AIR' "$out/first.log" && break; sleep .25; done
grep 'STOCK SETUP PREGENERATED AIR' "$out/first.log"
rows draft
import -window root "$out/options.png"
xdotool mousemove 510 332 click 1 key ctrl+a type '12.5'
xdotool mousemove 940 657 click 1
sleep .45
rows draft
import -window root "$out/invalid-option.png"
xdotool mousemove 515 332 click 1 key ctrl+a type '817516'
xdotool mousemove 712 390 click 1
sleep .25
xdotool key Down Return
sleep .3
import -window root "$out/selected-size.png"
xdotool mousemove 962 332 click 1
sleep .35
xdotool mousemove 1039 390 click 1
sleep .25
xdotool key Down Return
sleep .35
import -window root "$out/landscape-options.png"
xdotool mousemove 940 657 click 1
for _ in {1..50}; do
  if rows committed >"$out/options.json" 2>/dev/null; then break; fi
  sleep .2
done
test -s "$out/options.json" || { cat "$out/first.log"; import -window root "$out/fail.png"; exit 1; }
sleep .8
import -window root "$out/options-saved.png"
# Starting the same local world again must honor stored options without
# showing the wizard or changing the global game configuration.
kill "$client" 2>/dev/null || true
wait "$client" || true
client=""
local_game reopened
grep 'STOCK SETUP GENERATED 128x128 seed 817516' "$out/reopened.log"
for _ in {1..240}; do
  kill -0 "$client" 2>/dev/null || { cat "$out/reopened.log"; exit 1; }
  grep -q 'STOCK SETUP PLACED' "$out/reopened.log" && break
  sleep .25
done
grep 'STOCK SETUP PLACED non-air' "$out/reopened.log"
sleep 1
import -window root "$out/generated.png"
echo "PASS: real first-run options before terrain, invalid seed rejected, exact selected 128x128, seed and coastline loaded on reopen"
