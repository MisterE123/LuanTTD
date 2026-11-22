-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Ported to Lua from pinned OpenTTD 14.1: src/cargopacket.h
-- (UpdateLoadingTile, UpdateUnloadingTile, GetDistance), src/cargopacket.cpp
-- (ChooseAction, packet split, AgeCargo), src/vehicle.cpp (CallVehicleTicks),
-- src/station_cmd.cpp (MoveGoodsToStation, UpdateStationWaiting),
-- src/economy.cpp (CargoPayment::PayFinalDelivery). See PORTING.md.
-- Bayline adapter: single-tile stops, town-level production, and daily tick
-- batches. No link-graph routing, disjoint station platforms or feeder profit.
local P={day_ticks=74,aging_ticks=185}
local floor,abs,min=math.floor,math.abs,math.min
function P.age_vehicle(v,days)
  -- OpenTTD's new vehicle counter starts at one. Advancing the vehicle
  -- phase even while it is empty matches the stock counter, while Bayline
  -- groups 74 ticks and resolves arrivals/boarding at day boundaries.
  local elapsed=(v.passenger_age_ticks or (P.aging_ticks-1))+P.day_ticks*days
  local periods=floor(elapsed/P.aging_ticks)
  v.passenger_age_ticks=elapsed%P.aging_ticks
  for _,p in ipairs(v.batches or {}) do
    p.age=min(65535,(p.age or 0)+periods)
  end
end
function P.pickup(p,st,xy)
  local x,z=xy(st.tile)
  p.origin_station=p.origin_station or st.id
  p.origin_tile=p.origin_tile or st.tile
  p.travel_x=(p.travel_x or 0)+x
  p.travel_z=(p.travel_z or 0)+z
  p.age=p.age or 0
end
function P.drop(p,st,xy)
  local x,z=xy(st.tile)
  p.travel_x=p.travel_x-x
  p.travel_z=p.travel_z-z
end
function P.distance(p,at,xy)
  local x,z=xy(at)
  local ox,oz=xy(p.origin_tile)
  return min(abs(p.travel_x-x)+abs(p.travel_z-z),abs(ox-x)+abs(oz-z))
end
function P.accept_at(p,st)
  return p.origin_station~=st.id
end
function P.split(p,take)
  if take==p.units then return p end
  local out={}
  for k,v in pairs(p) do out[k]=v end
  p.units=p.units-take
  out.units=take
  return out
end
function P.waiting(st)
  local sum=0
  for _,p in ipairs(st.stock.passenger or {}) do sum=sum+p.units end
  return sum
end
function P.enqueue(st,p)
  local queue=st.stock.passenger or {}
  st.stock.passenger=queue
  local tail=queue[#queue]
  if tail and tail.source==p.source and tail.origin_station==p.origin_station and
       tail.origin_tile==p.origin_tile and tail.age==p.age and
       tail.travel_x==p.travel_x and tail.travel_z==p.travel_z and
       tail.last_vehicle==p.last_vehicle and tail.day==p.day and tail.units+p.units<=65535 then
    tail.units=tail.units+p.units
  else
    queue[#queue+1]=p
  end
end
-- Production distribution from the ordinary non-exclusivity code in
-- MoveGoodsToStation; st/supply filtering and rating updates are external.
-- Each station carries its 8-bit fractional amount into later production.
function P.allocate(amount,result)
  if amount<=0 or #result==0 then return end
  if #result==1 then result[1].fixed=amount*(result[1].rating+1);return end
  local owner_best,owner_sum,best,best_sum,used={},{},0,0,0
  for _,p in ipairs(result) do
    local owner,r=p.st.owner,p.rating
    local old=owner_best[owner] or 0
    if r>old then owner_best[owner]=r;best_sum=best_sum+r-old;best=math.max(best,r) end
    owner_sum[owner]=(owner_sum[owner] or 0)+r
  end
  local fixed=amount*(best+1)
  for _,p in ipairs(result) do
    local o=p.st.owner
    p.fixed=floor(fixed*owner_best[o]*p.rating/best_sum/owner_sum[o])
    used=used+p.fixed
  end
  if fixed>used then
    table.sort(result,function(a,b)
      return a.rating>b.rating or (a.rating==b.rating and a.st.id<b.st.id)
    end)
    for i=1,fixed-used do result[i].fixed=result[i].fixed+1 end
  end
end
function P.whole_units(st,fixed)
  local total=fixed+(st.passenger_fraction or 0)
  st.passenger_fraction=total%256
  return floor(total/256)
end
return P
