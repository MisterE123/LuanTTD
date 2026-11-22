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
-- Temperate original cargo classes: all dry cargo except passengers.
local mask={[1]=true,[2]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
function R.accepts_refit(cargo)
  return mask[cargo]==true
end
function R.quote(cargo,buy_base,current_cargo)
  if not R.accepts_refit(cargo) then return nil,"CARGO_NOT_REFITTABLE" end
  buy_base=buy_base or R.purchase_base
  if current_cargo==nil then current_cargo=R.default_cargo end
  local buy=math.floor(buy_base*R.purchase_factor/256)
  local refit=current_cargo==cargo and 0 or math.floor(buy_base*R.refit_factor/1024)
  -- DetermineCapacity explicitly excludes ships from stock capacity
  -- multiplier conversion when refitting to a different cargo.
  return {capacity=R.capacity,purchase=buy,refit=refit,total=buy+refit,cargo=cargo}
end
function R.running_fixed(running_ticks,running_base)
  return math.floor((running_base or R.running_base)*R.running_factor*running_ticks/(R.year_days*R.day_ticks))
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
