-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 train_cmd.cpp, station_cmd.cpp, order_cmd.cpp, vehicle.cpp,
-- ground_vehicle.hpp, vehicle_base.h and train.h. Original acceleration
-- only. Realistic propulsion, consist recaching, path reservations,
-- train reversals, and cargo/loading dwell are handled outside this module.
return function(T,F)
local R={NEAR=0,MIDDLE=1,FAR=2,AXIAL_DISTANCE=192,CORNER_DISTANCE=128}
local floor,min,max=math.floor,math.min,math.max

-- Order flags are the original bit positions. The caller owns live order and reversing state. An ordinary non-stop-to-destination order
-- uses {kind="station",station=id,nonstop=1,stop_location=R.FAR}.
function R.should_stop(v,id)
  local order=v.order or {}
  local destination=order.kind=="station" and order.station==id
  return not (order.kind=="depot" and not order.part_of_orders)
    and v.last_station~=id and floor((order.nonstop or 0)/(destination and 2 or 1))%2==0
end

-- The platform length is measured in stock 1/16-tile units and includes
-- the current tile. Pose direction is eight-way; the platform is axial.
function R.stop_location(board,tile_id,v,direction)
  local dir=floor(direction/2)
  local ahead=F.platform(board,tile_id,dir)*16
  local length=ahead+F.platform(board,tile_id,T.reverse_side(dir))*16-16
  local station=board.tile(tile_id).station
  local order=v.order or {}
  local target=v.total_length>=length and R.FAR or
    (order.kind=="station" and order.station==station and order.stop_location or R.MIDDLE)
  local stop
  if target==R.NEAR then stop=v.total_length
  elseif target==R.MIDDLE then stop=length-floor((length-v.total_length)/2)
  elseif target==R.FAR then stop=length
  else error("Unknown stock platform stop location") end
  return stop-floor((v.front_length+1)/2),ahead,length
end

-- Call on an approved M.step's proposed x/y but pass the OLD heading.
-- TrainController calls VehicleEnterTile before committing the new
-- heading at a boundary. Speed/slowing are mutable; coordinates are not.
-- "arrived" means emit TrainEnterStation / BeginLoading after this sample.
function R.station_step(board,tile_id,proposal,v,direction)
  local tile=board.tile(tile_id)
  if not tile or tile.kind~="station" or v.front==false or not R.should_stop(v,tile.station) then
    return "pass"
  end
  local stop,ahead,length=R.stop_location(board,tile_id,v,direction)
  if stop+ahead-16>=length then return "pass" end
  local x,y=proposal.x%16,proposal.y%16
  local dir=floor(direction/2)
  if dir%2~=0 then x,y=y,x end
  if y~=8 then return "pass" end
  if dir~=T.SE and dir~=T.SW then x=15-x end
  stop=stop%16
  if x==stop then return "arrived" end
  if x<stop then
    v.slowing=true
    local cap=max(0,(stop-x)*20-15)
    if cap<v.speed then v.speed=cap end
    return "approach",cap
  end
  return "pass"
end

-- Only the movement boundary from TrainEnterStation / BeginLoading.
-- It intentionally leaves subspeed and progress intact.
function R.begin_loading(v,id)
  v.last_station=id
  v.speed=0
end

-- Train::UpdateAcceleration: power/weight divides BEFORE multiplication.
function R.acceleration(power,weight)
  return max(1,min(floor(power/weight)*4,255))
end

function R.advance_distance(direction)
  return direction%2==1 and R.AXIAL_DISTANCE or R.CORNER_DISTANCE*2
end

-- Train::GetCurrentMaxSpeed's original acceleration branch.
function R.original_speed_limit(v)
  return min(v.max_track_speed,v.order_max_speed or 65535,v.visible_bridge_speed or 65535)
end

function R.is_braking(v)
  return not not (v.stopped or v.reversing or v.stuck)
end

-- One TrainLocoHandler pass (not a whole Train::Tick, which calls twice).
-- Fixed point matches uint spd = subspeed + accel, then cast signed
-- and arithmetic >>8 when used for the whole-speed difference.
function R.update_speed(v,limit,force,minimum)
  limit=limit or R.original_speed_limit(v)
  local spd=(v.subspeed or 0)+(force or v.acceleration*(R.is_braking(v) and -4 or 2))
  v.subspeed=spd%256
  local cap=limit
  if v.speed>limit then cap=max(v.speed-floor(v.speed/10)-1,limit) end
  v.speed=max(min(v.speed+floor(spd/256),cap),minimum or 0)
  local budget=floor(v.speed*3/4)+(v.progress or 0)
  v.progress=0
  return budget
end

-- TrainController original acceleration heading/height penalties.
-- acceleration_type 0=rail, 1=monorail, 2=maglev (RailTypeInfo).
function R.after_turn(v,old,new,acceleration_type)
  if new==old then return end
  local diff=(old-new)%8
  local factor=(diff==1 or diff==7) and (acceleration_type==2 and 0 or 64) or 128
  v.speed=v.speed-floor(factor*v.speed/256)
end

function R.after_grade(v,old_z,new_z)
  if old_z<new_z then
    v.speed=v.speed-floor(v.speed*64/256)
  elseif old_z>new_z then
    local speed=(v.speed+2)%65536
    if speed<=v.max_track_speed then v.speed=speed end
  end
end

-- The movement-budget loop from one TrainLocoHandler, after the caller's
-- order/depot/loading/line-end guards. v.direction is the current heading;
-- advance(v) may commit a pixel, call begin_loading, or set a signal's
-- explicit progress field. Its "crashed" result interrupts the loop.
-- Advancing always spends the distance measured BEFORE that advance.
function R.move_pass(v,advance,limit,force,minimum)
  local j=R.update_speed(v,limit,force,minimum)
  local distance=R.advance_distance(v.direction)
  local calls=0
  while j>=distance do
    j=j-distance
    calls=calls+1
    local result=advance(v)
    if result=="crashed" then break end
    distance=R.advance_distance(v.direction)
    if v.speed==0 then break end
  end
  if v.progress==0 then v.progress=j%256 end
  return calls
end

return R
end
