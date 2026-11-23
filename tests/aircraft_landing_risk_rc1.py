#!/usr/bin/env python3
"""Pin the stock landing-risk branch and verify every edge of its RNG draw."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re
import subprocess
p=ArgumentParser(description=__doc__);p.add_argument('aircraft_cmd',type=Path);p.add_argument('--lua',default='lua5.1')
a=p.parse_args()
raw=a.aircraft_cmd.read_bytes()
assert sha256(raw).hexdigest()=='286ea285a00f2e8c3cee5cdb283703c6a47af77fc6743f9af90bd280ca1be80a'
s=raw.decode()
body=s.split('static void MaybeCrashAirplane(Aircraft *v)\n{',1)[1].split('\n}',1)[0]
assert all(part in body for part in ('Flag::ShortStrip','subtype & AIR_FAST','!_cheats.no_jetcrash.value',
    'plane_crashes == 0) return','GB(Random(), 0, 22) > prob'))
strip=int(re.search(r'prob = (\d+);',body)[1])
base,scale=re.search(r'prob = \((0x[0-9A-F]+) << _settings_game.vehicle.plane_crashes\) / (\d+);',body).groups()
assert re.search(r'Flag::Brake\) && v->cur_speed > SPEED_LIMIT_TAXI \* _settings_game.vehicle.plane_speed\) \{\s*MaybeCrashAirplane\(v\);',s)
lua=['local R=dofile("mods/luanttd_core/openttd/aircraft_landing_risk.lua")']
for short in (False,True):
  for jet in (False,True):
    for cheat in (False,True):
      for level in range(3):
        t=strip if short and jet and not cheat else (int(base,16)<<level)//int(scale) if level else None
        args=",".join(map(str,(short,jet,cheat,level))).lower()
        lua += [f'assert(R.threshold({args})=={"nil" if t is None else t})']
        if t is None:
          lua += [f'assert(not R.sample({args},function() error("Unexpected RNG draw") end))']
        else:
          for sample in (0,max(0,t-1),t,t+1,t+2**22,2**32-1):
            want=str((sample%2**22)<=t).lower()
            lua += [f'assert(R.sample({args},function() return {sample} end)=={want})']
subprocess.run([a.lua,'-'],cwd=Path(__file__).resolve().parents[1],input='\n'.join(lua),text=True,check=True)
print("PASS RC1 fast-brake hazard parameters, chance edges, low-22-bit draw and disabled RNG")
