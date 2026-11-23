-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 aircraft_cmd.cpp MaybeCrashAirplane (decision only).
-- AircraftController calls it during fast Brake movement after its
-- exact-position handling and before the landing speed is reduced.
local R={}
local floor=math.floor
function R.threshold(short_strip,fast,no_jet_crash,crash_level)
  if short_strip and fast and not no_jet_crash then return 3276 end
  if crash_level==0 then return nil end
  assert(type(crash_level)=="number" and crash_level>=1 and crash_level<=2 and crash_level%1==0)
  return floor(0x4000*2^crash_level/1500)
end
function R.sample(short_strip,fast,no_jet_crash,crash_level,random)
  local threshold=R.threshold(short_strip,fast,no_jet_crash,crash_level)
  if not threshold then return false end
  local value=random()
  assert(type(value)=="number" and value>=0 and value<2^32 and value%1==0)
  return value%2^22<=threshold
end
return R
