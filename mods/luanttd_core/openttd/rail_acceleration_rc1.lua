-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: GroundVehicle<Train>::GetAcceleration
-- (ground_vehicle.cpp) and Train::GetCurrentMaxSpeed/GetCurveSpeedLimit
-- (train_cmd.cpp). The host supplies whole-consist, stock integer caches.
local K={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local function trunc(n) return n<0 and ceil(n) or floor(n) end
local function int32(n) return max(-2147483648,min(2147483647,trunc(n))) end

function K.force(cache,speed,brake,maglev,tunnel,slope_resistance)
  local mass=max(cache.weight,1)
  local watt=cache.power*746
  local area=tunnel and 28 or 14
  local resistance=floor(area*cache.air_drag*speed*speed/1000)+(slope_resistance or 0)
  if not maglev then resistance=resistance+cache.axle_resistance+mass*floor(15*(512+speed)/512) end
  local force
  if speed==0 then
    local kickoff=not brake and not maglev and min(cache.tractive_effort,watt) or watt
    force=max(kickoff,mass*8+resistance)
  elseif maglev then force=floor(watt/25)
  else
    force=floor(watt*18/(speed*5))
    if not brake then force=min(force,cache.tractive_effort) end
  end
  if brake then return int32(min(-force-resistance,-10000)/mass) end
  if force==resistance then return 0 end
  local a=int32((force-resistance)/(mass*4))
  return force<resistance and min(-1,a) or max(1,a)
end

-- TrainCheckIfLineEnds uses the post-HandleBreakdown countdown.
-- Its cap is applied only once DoUpdateSpeed has accumulated a whole move.
local breakdown_speeds={225,210,195,180,165,150,135,120,105,90,75,60,45,30,15,15}
function K.breakdown_speed(countdown)
  if countdown>1 then return breakdown_speeds[16-floor(countdown/16)%16] end
end

function K.curves(parts,advantage,tilt,modifier)
  local limit,left,right,sample,sum,last,pos=65535,0,0,0,0,nil,0
  for i=1,#parts-1 do
    local a,b=parts[i],parts[i+1]
    local delta=(b.pose.direction-a.pose.direction)%8
    if delta==1 or delta==7 then
      if delta==1 then right=right+1 else left=left+1 end
      if last then
        local gap=pos-last
        sample,sum=sample+1,sum+gap
        if gap<=8 and limit>88 then limit=88 end
      end
      last=pos
    elseif delta==2 or delta==6 then limit=61 end
    pos=pos+a.length
  end
  if sample>0 and limit>88 and not (left==1 and right==1) then
    limit=232-(13-max(1,min(12,floor(ceil(sum/8)/sample))))^2
  end
  if limit<65535 then
    limit=limit+floor(limit/2)*(advantage or 0)
    if tilt then limit=limit+floor(limit/5) end
    limit=limit+trunc(limit*(modifier or 0)/256)
    limit=max(2,min(65535,limit))
  end
  return limit
end

function K.limit(cache,current,curves,station_distance,any_in_depot,bridge,order,can_lead)
  local limit=curves
  if station_distance and station_distance>0 then
    local delta=floor(current/(station_distance+1))
    local station=limit>current-delta and current-floor(delta/10) or 120
    limit=min(limit,max(station,25*station_distance))
  end
  if any_in_depot then limit=min(limit,61) end
  limit=min(limit,bridge or 65535,order or 65535)
  if can_lead==false then limit=min(limit,32) end
  return min(limit,cache.max_track_speed)
end
return K
