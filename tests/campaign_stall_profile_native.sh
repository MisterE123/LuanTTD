#!/usr/bin/env bash
set -euo pipefail
# Instrument a scratch copy of the actual worker; don't change the game
# build or source save. A generated, running worker-owned 1024 map is useful.
if [[ $# != 4 ]]; then
  echo "usage: $0 LUANTI_SERVER FIXTURE_WORLD CONFIG NEW_OUTPUT_DIR" >&2
  exit 64
fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
seed=$(realpath "$2")
config=$(realpath "$3")
mkdir "$4"
d=$(realpath "$4")
cd "$(dirname "$0")/.."
g="$d/games/luanttd";m="$g/mods/luanttd_core";w="$d/world"
mkdir -p "$g" "$d/home" "$w"
cp game.conf "$g/"
if ! cp -al mods "$g/" 2>/dev/null; then
  rm -rf "$g/mods"
  cp -a mods "$g/"
fi
{ cat mods/luanttd_core/init.lua; printf '\n'; cat tests/campaign_autosave_view_native.lua; } > "$m/init.next"
mv "$m/init.next" "$m/init.lua"
python3 - "$m" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
def modify(f, changes):
 p=root/f
 s=p.read_text()
 for a,b in changes:
  assert s.count(a)==1,a
  s=s.replace(a,b)
 q=p.with_suffix('.next')
 q.write_text(s)
 q.replace(p)
modify('town_passenger_runtime.lua',[
 ('    local traverse=hooks and hooks.traverse','''    local traverse=hooks and hooks.traverse
    local peak_tile,peak_after,all_tile,all_after=0,0,0,0
    local big_count=0
    local us=core.get_us_time'''),
 ('''          H.advance_houses(clock,1,house,settings,random,emit,animate,landscape_tile,traverse)
          after_tick(clock.counter,update_rating)''','''          local a=us()
          H.advance_houses(clock,1,house,settings,random,emit,animate,landscape_tile,traverse)
          local b=us()
          after_tick(clock.counter,update_rating)
          local c=us()
          local tile,other=b-a,c-b
          peak_tile,peak_after=math.max(peak_tile,tile),math.max(peak_after,other)
          all_tile,all_after=all_tile+tile,all_after+other
          if tile>16000 then big_count=big_count+1 end'''),
 ('''    end
  end
  return M''','''    end
    if growth and after_tick then core.log("action",("TILE_PHASE %d us=%d landscape=%d tick=%d peak_landscape=%d peak_tick=%d big=%d"):format(
      s.day,us(),all_tile,all_after,peak_tile,peak_after,big_count)) end
  end
  return M''')])
runtime_source=(root/'campaign_authority_runtime.lua').read_text()
daily='Sim.daily(s,nil,tick_pulse)' if 'Sim.daily(s,nil,tick_pulse)' in runtime_source else 'Sim.daily(s)'
modify('campaign_authority_runtime.lua',[
 ('    '+daily+'\n    if Clock','''    local a,c=core.get_us_time(),os.clock()
    '''+daily+'''
    core.log("action",("DAY_CORE %d began=%d ended=%d cpu_ms=%.2f heap_kb=%.1f"):format(
      s.day,a,core.get_us_time(),(os.clock()-c)*1000,collectgarbage("count")))
    if Clock'''),
 ('    N.news.day()\n  end','''    N.news.day()
    core.log("action",("DAY_COMPLETE %d us=%d"):format(s.day,core.get_us_time()))
  end''')])
worker_source=(root/'campaign_authority_worker.lua').read_text()
if 'local tick_mode=' in worker_source:
 modify('campaign_authority_worker.lua',[
  ('    fraction,days,overdue=auto.step(dt,true,true)','''    local a=core.get_us_time()
    fraction,days,overdue=auto.step(dt,true,true)
    local b=core.get_us_time()
    if b-a>=500 then core.log("action",("SIM_BATCH begin=%d end=%d"):format(a,b)) end'''),
  ('          if auto.flush() then dirty=true end','''          local a=core.get_us_time()
          if auto.flush() then dirty=true end
          local b=core.get_us_time()
          if b-a>=500 then core.log("action",("SIM_BATCH begin=%d end=%d"):format(a,b)) end''')])
modify('campaign_checkpoint.lua',[
 ('''    return write(state_prefix,core.compress(assert(codec).encode(state,pulse),"zstd",3))''','''    local a=core.get_us_time()
    local bytes=assert(codec).encode(state,pulse)
    local b=core.get_us_time()
    local payload=core.compress(bytes,"zstd",3)
    local c=core.get_us_time()
    write(state_prefix,payload)
    core.log("action",("SAVE_PHASE %d begin=%d encode=%d packed=%d finish=%d chars=%d bytes=%d"):format(
      state.day,a,b,c,core.get_us_time(),#bytes,#payload))''')])
PY
export HOME="$d/home" LUANTI_GAME_PATH="$d/games" MINETEST_GAME_PATH="$d/games"
cp "$seed/luanttd-campaign-owner.chk" "$seed/world.mt" "$w/"
sed -E '/^[[:space:]]*(port|bind_address|dedicated_server_step|server_announce)[[:space:]]*=/d' "$config" > "$w/conf"
printf '\nport = %s\nbind_address = 127.0.0.1\nserver_announce = false\ndedicated_server_step = .025\n'   "${BAYLINE_NATIVE_PORT:-44574}" >> "$w/conf"
if ! timeout 80 "$server" --world "$w" --gameid luanttd --config "$w/conf" --logfile '' >"$w/log" 2>&1; then
  tail -60 "$w/log"; exit 1
fi
grep -q 'PROBE_FINISH' "$w/log"
if grep -E 'ERROR\[' "$w/log"; then exit 1; fi
python3 tests/campaign_stall_report.py "$w/log"
