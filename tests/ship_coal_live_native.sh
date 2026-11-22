#!/usr/bin/env bash
# Native source Yate coastal service with a mixed road/ferry economy.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-ship-coal-live.XXXXXX")
echo "Native coal logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -al mods "$game/" || cp -R mods "$game/"
cp mods/luanttd_core/init.lua "$out/check-init.lua"
mv "$out/check-init.lua" "$game/mods/luanttd_core/init.lua"
# Use the real setup data, not a feature switch.
python3 - "$game/mods/luanttd_core/init.lua" <<'PROBE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();k=s.index("local settings=core.settings")
p.write_text(s[:k]+"""
if storage:get_string("world_setup_v1")=="" then
  local setup=dofile(mod.."/world_setup.lua")
  local choices=setup.defaults(core.settings)
  choices.scenario="south_coast"
  choices.year=tonumber(core.settings:get("luanttd_qa_ferry_year")) or 1950
  storage:set_string(setup.storage_key,core.write_json(choices))
end
"""+s[k:])
PROBE
cat tests/ship_coal_live_native.lua >> "$game/mods/luanttd_core/init.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<EOF_CONF
luanttd_qa_ferry_year = ${LUANTTD_NATIVE_FERRY_YEAR:-1950}
port = ${BAYLINE_NATIVE_PORT:-39619}
bind_address = 127.0.0.1
server_announce = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 || {
  cat "$out/server.log"; exit 1;
}
grep -q YATE_SAVE_LOADING "$out/server.log" || { cat "$out/server.log"; exit 1; }
timeout 30s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/reload.log" 2>&1 || {
  cat "$out/reload.log"; exit 1;
}
marker=YATE_NATIVE_PASS
grep "$marker" "$out/reload.log" || { cat "$out/reload.log"; exit 1; }
