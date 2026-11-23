#!/usr/bin/env bash
# Disposable Linux check for all three industry chains on one persisted clock.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-mixed-freight.XXXXXX")
echo "Native mixed freight logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" || cp -R mods "$game/"
{ cat mods/luanttd_core/init.lua; printf '\n'; cat tests/mixed_freight_live_native.lua; } > "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cp tests/mixed_freight_live.lua "$game/mods/luanttd_core/qa_mixed_freight.lua"
cat > "$out/world/world.mt" <<'CONF'
gameid = luanttd
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
CONF
cat > "$out/native.conf" <<EOF_CONF
port = ${BAYLINE_NATIVE_PORT:-39679}
bind_address = 127.0.0.1
server_announce = false
bayline_offline_economy = false
EOF_CONF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for phase in SAVED PASS; do
  timeout 130s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" \
    >"$out/$phase.log" 2>&1 || { cat "$out/$phase.log";exit 1; }
  grep "MIXED_FREIGHT_NATIVE_$phase" "$out/$phase.log" || { cat "$out/$phase.log";exit 1; }
done
