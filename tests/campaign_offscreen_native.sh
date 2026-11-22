#!/usr/bin/env bash
# Dedicated Luanti engine proof with no client and real SQLite reopens.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
server=${BAYLINE_LUANTI_SERVER:-luantiserver}
command -v "$server" >/dev/null
q=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-campaign-offscreen.XXXXXX")
echo "Native headless evidence: $q"
mod="$q/games/bayline/mods/bayline"
mkdir -p "$q/world" "$q/games/bayline" "$q/home"
cp -r game.conf mods "$q/games/bayline/"
cp tests/campaign_offscreen_probe.lua "$mod/"
printf '\ndofile(mod.."/campaign_offscreen_probe.lua")(api)\n' >> "$mod/init.lua"
cat > "$q/world/world.mt" <<'EOF_WORLD'
gameid = bayline
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF_WORLD
export HOME="$q/home" LUANTI_GAME_PATH="$q/games" MINETEST_GAME_PATH="$q/games"
port=${BAYLINE_NATIVE_PORT:-42801}
for i in 1 2 3; do
  enabled=true
  if [[ $i == 3 ]]; then enabled=false;fi
  cat > "$q/server-$i.conf" <<EOF_CONF
port = $port
bind_address = 127.0.0.1
server_announce = false
bayline_offline_economy = $enabled
bayline_seconds_per_day = 0.2
bayline_seed = 1751
bayline_fixture_harbor_valley = true
bayline_stock_regal_preview = true
bayline_road_oil_preview = $([[ ${BAYLINE_NATIVE_OFFSCREEN_OIL:-0} == 1 ]] && echo true || echo false)
bayline_offline_fixture_stage = $i
bayline_offline_fixture_result = $q/world/stage-$i.json
EOF_CONF
  timeout 65s "$server" --world "$q/world" --gameid bayline --config "$q/server-$i.conf" > "$q/stage-$i.log" 2>&1 ||
    { cat "$q/stage-$i.log";exit 1; }
  grep -F "NATIVE OFFSCREEN ECONOMY PASS stage=$i" "$q/stage-$i.log"
done
python3 - "$q" <<'PY'
from pathlib import Path
import json,sys
q=Path(sys.argv[1])
a,b,c=(json.loads((q/f"world/stage-{i}.json").read_text()) for i in (1,2,3))
assert all(x["viewport_clients"]==0 for x in (a,b,c))
assert 0<a["paid"]<b["paid"]==c["paid"] and a["dollars"]<b["dollars"]==c["dollars"]
assert 0<a["day"]<b["day"]==c["day"] and 0<a["clock"]<b["clock"]==c["clock"]
assert b["from"]["paid"]==a["paid"] and b["from"]["day"]==a["day"]
if a["kind"]=="oil":
    assert b["kind"]==c["kind"]=="oil"
    assert 0<a["by_vehicle"][0]<b["by_vehicle"][0]==c["by_vehicle"][0]
    assert 0<a["by_vehicle"][1]<b["by_vehicle"][1]==c["by_vehicle"][1]
    assert all(x["received_oil"]==x["by_vehicle"][0] for x in (a,b,c))
(q/"native-offline-economy.json").write_text(json.dumps({"first":a,"reopened":b,"opt_out":c},indent=2)+"\n")
print("PASS: authoritative economy without any client, same SQLite continuation, proper subsequent opt-out.")
PY
