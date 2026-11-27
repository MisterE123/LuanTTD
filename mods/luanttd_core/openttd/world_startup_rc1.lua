-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 genworld.cpp _GenerateWorld, engine.cpp
-- StartupEngines/StartupOneEngine, and disaster_vehicle.cpp
-- StartupDisasters/ResetDisasterDelay. This port only implements the
-- default disabled-disasters timer, not any actual disaster content.
local S={}
local function reset_disasters(random)
  return random()%512+730
end
function S.finish(random)
  local startup_seed=random() -- per-design temporary RNGs are restored
  local delay=reset_disasters(random)
  return startup_seed,delay
end
function S.disaster_day(delay,random)
  assert(delay>=1)
  return delay==1 and reset_disasters(random) or delay-1
end
return S
