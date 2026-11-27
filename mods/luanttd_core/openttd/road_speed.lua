-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, source pin 14.1. RoadVehController, UpdateSpeed
-- (AM_ORIGINAL), RoadZPosAffectSpeed, GroundVehicle::DoUpdateSpeed and the
-- direction-independent progress in vehicle_base.h. No acceleration applied
-- while loading or parked: those vehicle states are owned by the caller.
local R={}
local floor,min,max=math.floor,math.min,math.max
function R.advance_distance(heading)
  return heading%2==1 and 192 or 256
end
function R.update(v,acceleration,minimum,limit)
  local spd=v.subspeed+acceleration
  v.subspeed=spd%256
  local cap=limit
  if v.speed>limit then cap=max(v.speed-floor(v.speed/10)-1,limit) end
  v.speed=max(min(v.speed+floor(spd/256),cap),minimum)
  local distance=floor(v.speed*3/4)+v.progress
  v.progress=0
  return distance
end
function R.turn(v)
  v.speed=v.speed-floor(v.speed/4)
end
function R.grade(v,old_z,new_z,track_limit)
  if old_z<new_z then
    v.speed=floor(v.speed*232/256)
  elseif old_z>new_z and v.speed+2<=track_limit then
    v.speed=v.speed+2
  end
end
-- Original acceleration for a non-articulated vehicle. move(v) executes one
-- logical stock frame and returns false when blocked. It may change the
-- heading/speed and install a nonzero progress just as the source does.
-- Callers supply the currently applicable stock track and order speed cap,
-- and the block condition. Crossing collisions and physics are separate.
function R.tick(v,limit,overtaking,move,context,acceleration,minimum)
  local budget=R.update(v,acceleration or (overtaking and 512 or 256),minimum or 0,limit)
  local step=R.advance_distance(v.heading)
  local blocked=false
  while budget>=step do
    budget=budget-step
    if not move(v,context) then blocked=true;break end
    step=R.advance_distance(v.heading)
  end
  if v.progress==0 then v.progress=blocked and step-1 or budget end
  return blocked
end
return R
