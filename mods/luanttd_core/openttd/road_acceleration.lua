-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, src/ground_vehicle.cpp (PowerChanged,
-- CargoChanged, GetAcceleration), src/ground_vehicle.hpp
-- (UpdateZPositionAndInclination), src/roadveh.h and roadveh_cmd.cpp
-- (GetWeight, GetRollingFriction, GetCurrentMaxSpeed and UpdateSpeed).
-- One-body original road vehicles; not NewGRF articulated consists.
local A={}
local floor,min,max=math.floor,math.min,math.max
local mass_weight={passenger=1,coal=16,mail=4,oil=16,livestock=3,goods=8,
  grain=16,wood=16,iron_ore=16,steel=16,valuables=2,food=16,water=16,fruit=16,maize=16,wheat=16}

function A.vehicle(spec)
  local maximum=floor((spec.source_speed or spec.speed)/2)
  local drag=spec.air_drag or 0
  if drag==0 then drag=maximum<=10 and 192 or max(floor(2048/maximum),1)
  elseif drag==1 then drag=0 end
  return {tare=floor(spec.weight_quarters/4),power=spec.power_tens_hp*7460,
    traction=spec.tractive_effort or 76,drag=drag+floor(3*drag/20)}
end

function A.inclination(edge,centre)
  return centre>edge and 1 or centre<edge and -1 or 0
end

function A.force(spec,internal_speed,cargo,units,slope,steepness,brake)
  local speed=floor(internal_speed/2)
  local weight=spec.tare+floor((mass_weight[cargo] or 0)*units/16)
  local mass=max(weight,1)
  local slope_force=weight*(steepness or 7)*100*(slope or 0)
  local resistance=10*weight+mass*floor(75*(128+speed)/128)
    +floor(6*spec.drag*speed*speed/1000)+slope_force
  local tractive=floor(9800*weight*spec.traction/256)
  local force
  if speed>0 then
    force=floor(spec.power*18/(speed*5))
    if not brake then force=min(force,tractive) end
  else
    force=max(brake and spec.power or min(tractive,spec.power),mass*8+resistance)
  end
  if brake then return math.ceil(min(-force-resistance,-10000)/mass) end
  if force==resistance then return 0 end
  local net=(force-resistance)/(mass*4)
  return force<resistance and min(-1,math.ceil(net)) or max(1,floor(net))
end

local reverse={[6]=true,[7]=true,[14]=true,[15]=true}
function A.limit(maximum,heading,state,bridge_max,order_max)
  if reverse[state] then maximum=floor(maximum/2)
  elseif heading%2==0 then maximum=floor(maximum*3/4) end
  return min(maximum,bridge_max or math.huge,order_max or math.huge)
end
return A
