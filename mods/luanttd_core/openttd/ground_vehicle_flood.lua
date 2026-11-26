-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1: water_cmd.cpp FloodVehicleProc / FloodVehicles,
-- vehicle.cpp Vehicle::Crash, core/random_func.hpp ScaleToLimit, and
-- train_cmd.cpp Train::Crash / HandleCrashedTrain, and
-- roadveh_cmd.cpp RoadVehicle::Crash / RoadVehIsCrashed.
local M={}
function M.ground_body_available(crashed,z,water_z)
  return not crashed and z<=water_z
end
function M.visit_ground(tile,other,z,bodies,crash)
  local function visit(at)
    for _,part in ipairs(bodies(at)) do
      -- Check the live flag: an earlier body may have just crashed this
      -- consist, including a body waiting at the other bridge endpoint.
      if M.ground_body_available(part.front.crashed,part.z,z) then crash(part.front) end
    end
  end
  visit(tile)
  if other then visit(other) end
end
local function scale_to_limit(random_u32,passengers)
  return math.floor(random_u32*(passengers+1)/2^32)
end
function M.train_victims(random_u32,passengers,has_front_engine)
  return (has_front_engine and 2 or 0)+scale_to_limit(random_u32,passengers)
end
function M.road_victims(random_u32,passengers,has_front_engine)
  return (has_front_engine and 1 or 0)+scale_to_limit(random_u32,passengers)
end
function M.road_crash_age(flooded)
  return flooded and 2000 or 1
end
function M.road_wreck_tick(age,tick_counter)
  age=age+1
  return age,age>=2220 and tick_counter%32==0
end
function M.train_crash_age(flooded)
  return flooded and 4000 or 1
end
function M.train_wreck_tick(age,tick_counter)
  age=age+1
  return age,age>=4440 and tick_counter%32==0
end
return M
