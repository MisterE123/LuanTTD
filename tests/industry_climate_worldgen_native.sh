#!/usr/bin/env bash
# Exact climate startup in Luanti's own async Lua environment, no media.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "$PWD/.native-climate-industry-XXXXXX")
trap 'rm -rf "$out"' EXIT
game="$out/games/climateindustryqa"
mod="$game/mods/luanttd_core"
mkdir -p "$mod/fixtures" "$out/world" "$out/home"
for p in "$PWD"/mods/luanttd_core/*.lua "$PWD"/mods/luanttd_core/openttd; do
  [[ ${p##*/} == init.lua ]] || cp -al "$p" "$mod/"
done
cp tests/fixtures/{rc1-climate-town-start,rc1-native-climate-generated-industries}.lua "$mod/fixtures/"
cp tests/industry_climate_worldgen_rc1.lua "$mod/phase.lua"
printf 'title = Stock climate industry QA\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cat > "$mod/init.lua" <<'LUA'
for _,name in ipairs({"mapgen_stone","mapgen_water_source","mapgen_river_water_source"}) do core.register_alias(name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local dir=core.get_modpath("luanttd_core").."/"
    assert(loadfile(dir.."phase.lua"))(dir,dir.."fixtures/",0)
    return true
  end,function(ok)
    assert(ok)
    core.log("action","CLIMATE_INDUSTRY_WORLDGEN_NATIVE_PASS")
    core.request_shutdown("Exact climate industry QA",false,0)
  end))
end)
LUA
printf 'gameid = climateindustryqa\nbackend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44366}" > "$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 95 "${LUANTI_SERVER:-luantiserver}" --world "$out/world" --gameid climateindustryqa --config "$out/conf" --logfile "" > "$out/log" 2>&1 ||
  { cat "$out/log"; exit 1; }
[[ $(grep -c 'PASS automatic RC1' "$out/log") == 4 ]]
grep -E 'PASS automatic RC1|CLIMATE_INDUSTRY_WORLDGEN_NATIVE_PASS' "$out/log"
