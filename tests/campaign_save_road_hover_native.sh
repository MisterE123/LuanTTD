#!/usr/bin/env bash
set -euo pipefail
# Compare ordinary Road quotes during autosave and while paused. Provide an unused
# output directory and a prepared generated campaign (prefer 1024x1024).
if [[ $# != 5 ]]; then
  echo "usage: $0 LUANTI_SERVER BASELINE_REV FIXTURE_WORLD CONFIG NEW_OUTPUT_DIR" >&2
  exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server");fi
base=$2
seed=$(realpath "$3")
config=$(realpath "$4")
mkdir "$5"
d=$(realpath "$5")
cd "$(dirname "$0")/.."
mkdir -p "$d"/{games/luanttd,home}
g="$d/games/luanttd";m="$g/mods/luanttd_core"
cp game.conf "$g/"
if ! cp -al mods "$g/" 2>/dev/null; then
  rm -rf "$g/mods"
  cp -a mods "$g/"
fi
{ cat mods/luanttd_core/init.lua; printf '\n'; cat tests/campaign_save_road_hover_native.lua; } > "$m/init.next"
mv "$m/init.next" "$m/init.lua"
export HOME="$d/home" LUANTI_GAME_PATH="$d/games" MINETEST_GAME_PATH="$d/games"
for side in baseline candidate candidate2 baseline2; do
 for name in campaign_step campaign_authority_worker; do
   file="mods/luanttd_core/$name.lua"
   if [[ "$side" == baseline* ]]; then git show "$base:$file" > "$m/worker.next";else cp "$file" "$m/worker.next";fi
   mv "$m/worker.next" "$m/$name.lua"
 done
 python3 - "$m/campaign_authority_worker.lua" "$side" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
line='    storage.write_state(s,pulse)'
assert line in s
s=s.replace(line,'''    local a,cpu=core.get_us_time(),os.clock()
    core.log("action",("PROBE_SAVE_BEGIN %d us=%d fraction=%s"):format(s.day,a,tostring(fraction)))
'''+line+'''
    core.log("action",("PROBE_SAVE_END %d us=%d wall=%.2f cpu=%.2f"):format(s.day,core.get_us_time(),
      (core.get_us_time()-a)/1000,(os.clock()-cpu)*1000))''',1)
if '      if road_hover then r=A.road_quote' in s:
    s=s.replace('      if road_hover then r=A.road_quote',
      '      if road_hover then core.log("action",("PROBE_ENCODE_HOVER %d us=%d day=%d"):format(seq,now,s.day));r=A.road_quote',1)
p.with_suffix('.next').write_text(s);p.with_suffix('.next').replace(p)
PY
 w="$d/$side";mkdir "$w"
 cp "$seed/luanttd-campaign-owner.chk" "$seed/world.mt" "$w/"
 sed -E '/^[[:space:]]*(port|bind_address|dedicated_server_step|server_announce)[[:space:]]*=/d' "$config" > "$w/conf"
 printf '\nport = %s\nbind_address = 127.0.0.1\nserver_announce = false\ndedicated_server_step = .025\n' "${BAYLINE_NATIVE_PORT:-44339}" >> "$w/conf"
 timeout 80 "$server" --world "$w" --gameid luanttd --config "$w/conf" --logfile '' > "$w/log" 2>&1 || { tail -35 "$w/log";exit 1; }
 grep -E 'PROBE_SAVE|PROBE_HOVER_PAUSED|PROBE_HOVER_FINISH' "$w/log"
 grep -q 'PROBE_HOVER_FINISH' "$w/log"
 rm "$w/luanttd-campaign-owner.chk"
done
