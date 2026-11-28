#!/usr/bin/env bash
# Checkpoint the live freight controller in engine-managed SQLite.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "$PWD/.native-water-XXXXXX")
trap 'rm -rf "$out"' EXIT
case "${1:-water}" in
  water) fixture=town_water_stock_route.lua; marker="PASS Water truck workers and packed reopen";;
  food) fixture=town_tropic_food_stock_route.lua; marker="PASS live Fruit";;
  *) echo "usage: $0 [water|food]" >&2; exit 64;;
esac
game="$out/games/waterqa"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
# The rule-only fixture doesn't need media. Link each code subtree in
# place; the tiny test entrypoint is the only replacement file.
for path in "$PWD"/mods/luanttd_core/*.lua "$PWD"/mods/luanttd_core/openttd; do
  [[ ${path##*/} == init.lua ]] || cp -al "$path" "$mod/"
done
cp "tests/$fixture" "$mod/route_test.lua"
printf 'title = Stock Water route QA\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cat > "$mod/init.lua" <<'LUA'
for _,name in ipairs({"mapgen_stone","mapgen_water_source","mapgen_river_water_source"}) do core.register_alias(name,"air") end
local storage=core.get_mod_storage()
core.after(0,function()
  local blob=storage:get_string("moving_water")
  assert(core.handle_async(function(snapshot)
    local root=core.get_modpath("luanttd_core").."/"
    local checkpoint,loaded
    assert(loadfile(root.."route_test.lua"))(root,
      function()
        if snapshot~="" then return core.deserialize(core.decompress(snapshot,"deflate"),true) end
      end,
      function(packed,units)
        checkpoint,loaded=core.compress(core.serialize(packed),"deflate"),units
      end)
    return checkpoint or false,loaded
  end,function(checkpoint,loaded)
    if checkpoint then
      storage:set_string("moving_water",checkpoint)
      core.log("action",("STOCK_TROPIC_ROUTE_SAVED %d units in motion"):format(loaded))
    end
    core.request_shutdown("Stock Water route QA",false,0)
  end,blob))
end)
LUA
cat > "$out/world/world.mt" <<'CONF'
gameid = waterqa
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/conf" <<CONF
port = ${BAYLINE_NATIVE_PORT:-44365}
bind_address = 127.0.0.1
server_announce = false
CONF
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
server=${LUANTI_SERVER:-luantiserver}
for phase in save reopen; do
  timeout 75 "$server" --world "$out/world" --gameid waterqa --config "$out/conf" --logfile "" > "$out/$phase.log" 2>&1 ||
    { cat "$out/$phase.log"; exit 1; }
done
grep STOCK_TROPIC_ROUTE_SAVED "$out/save.log"
grep "$marker" "$out/reopen.log"
