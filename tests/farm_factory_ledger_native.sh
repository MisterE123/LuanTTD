#!/usr/bin/env bash
# Native SQLite snapshot of the pure industry adapter, not a live if-disabled delivery system.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-farm-factory-ledger.XXXXXX")
echo "Native farm/factory ledger: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -R mods "$game/"
fixture="$game/mods/luanttd_core/farm_factory_native_fixture.lua"
cp tests/farm_factory_ledger.lua "$fixture"
cat >> "$game/mods/luanttd_core/init.lua" <<'LUA'
core.after(0,function()
  local dir=core.get_modpath("luanttd_core").."/"
  local test=assert(loadfile(dir.."farm_factory_native_fixture.lua"))(dir)
  local memory=storage
  local saved=memory:get_string("farm_factory_ledger_qa")
  if saved=="" then
    local snapshot=test.save_point()
    memory:set_string("farm_factory_ledger_qa",core.serialize(snapshot))
    core.log("action","FARM_FACTORY_LEDGER_STAGED_TEST")
  else
    local grain,livestock,goods=test.finish(assert(core.deserialize(saved,true)))
    print(("FARM_FACTORY_LEDGER_SETTLED_TEST grain=$%d livestock=$%d goods=$%d"):format(grain,livestock,goods))
  end
  core.request_shutdown("Native SQLite farm/factory ledger test",false,0)
end)
LUA
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<CONF
port = ${BAYLINE_NATIVE_PORT:-39784}
bind_address = 127.0.0.1
server_announce = false
CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/stage.log" 2>&1 || {
  cat "$out/stage.log"; exit 1;
}
grep -q FARM_FACTORY_LEDGER_STAGED_TEST "$out/stage.log" || { cat "$out/stage.log"; exit 1; }
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/reload.log" 2>&1 || {
  cat "$out/reload.log"; exit 1;
}
grep FARM_FACTORY_LEDGER_SETTLED_TEST "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
