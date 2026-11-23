-- SPDX-License-Identifier: GPL-2.0-only
-- Stock OpenTTD 14.1 1950 temperate dry-cargo ship. Source: table/engines.h
-- MS #211 and SVI #7; newgrf.cpp CalculateRefitMasks; engine.cpp
-- GetCost/DetermineCapacity; ship_cmd.cpp Ship::Tick/OnNewEconomyDay.
local R={
  id=211,local_id=7,image=0,name="Yate Cargo Ship",intro=2557,base_year=1920,
  life=30,base_life=55,decay=5,capacity=160,default_cargo=5,coal=1,
  max_speed=48,acceleration=1,ocean_speed_frac=0,canal_speed_frac=0,
  purchase_factor=128,refit_factor=8,running_factor=150,purchase_base=65000,running_base=5600,
  load_amount=10,gradual_wait=10,retry_wait=20,cargo_age_ticks=185,day_ticks=74,year_days=365,
}
-- Both stock dry-cargo vessels use the same refit class and loading
-- amount. Fast Bakewell is 190 units, while the earlier Yate is 160.
R.order={211,212}
local bakewell={id=212,stock_id=212,local_id=8,vehicle_type=2,image=0,name="Bakewell Cargo Ship",
  intro_after_1920=19724,decay_speed=5,life=30,base_life=98,climates=7,
  max_speed=80,capacity=190,purchase_factor=144,running_factor=113}
R.stock_id,R.vehicle_type,R.climates,R.intro_after_1920,R.decay_speed=211,2,7,R.intro,R.decay
function R.model(id)
  if id==nil or id==211 then return R end
  if id==212 then
    local t={}
    for k,v in pairs(R) do
      if type(v)=="number" or type(v)=="string" then t[k]=v end
    end
    for k,v in pairs(bakewell) do t[k]=v end
    return t
  end
end
-- Temperate original cargo classes: all dry cargo except passengers.
local mask={[1]=true,[2]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
function R.accepts_refit(cargo)
  return mask[cargo]==true
end
function R.quote(cargo,buy_base,current_cargo,id)
  local ship=R.model(id)
  if not ship then return nil,"UNKNOWN_STOCK_CARGO_SHIP" end
  if not R.accepts_refit(cargo) then return nil,"CARGO_NOT_REFITTABLE" end
  buy_base=buy_base or R.purchase_base
  if current_cargo==nil then current_cargo=R.default_cargo end
  local buy=math.floor(buy_base*ship.purchase_factor/256)
  local refit=current_cargo==cargo and 0 or math.floor(buy_base*R.refit_factor/1024)
  -- DetermineCapacity explicitly excludes ships from stock capacity
  -- multiplier conversion when refitting to a different cargo.
  return {capacity=ship.capacity,purchase=buy,refit=refit,total=buy+refit,cargo=cargo}
end
function R.running_fixed(running_ticks,running_base,id)
  return math.floor((running_base or R.running_base)*assert(R.model(id)).running_factor*running_ticks/(R.year_days*R.day_ticks))
end
function R.timing(Base)
  return {initial=Base.initial,can_leave=Base.can_leave,pulse=function(m)
    local n,stop,finished,refresh=Base.pulse(m)
    if m.loaded+m.unloaded>0 or m.retry_unload then
      n=m.gradual and R.gradual_wait or math.max(1,m.loaded+m.unloaded)
    else n=R.retry_wait end
    return n,stop,finished,refresh
  end}
end
return R
