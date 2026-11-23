-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1: src/table/engines.h MS #204/#205, SVI
-- #0/#1, engine.cpp Engine::GetCost and ship_cmd.cpp Ship::GetRunningCost.
local R={order={204,205},purchase_base=65000,running_base=5600}
local rows={
  [204]={stock_id=204,id=204,local_id=0,image=1,vehicle_type=2,name="MPS Oil Tanker",
    climates=7,intro_after_1920=2922,decay_speed=5,life=30,base_life=50,default_cargo=3,
    purchase_factor=160,running_factor=140,acceleration=1,max_speed=48,capacity=220},
  [205]={stock_id=205,id=205,local_id=1,image=1,vehicle_type=2,name="CS-Inc. Oil Tanker",
    climates=7,intro_after_1920=17167,decay_speed=5,life=30,base_life=90,default_cargo=3,
    purchase_factor=176,running_factor=125,acceleration=1,max_speed=80,capacity=350},
}
function R.model(id)
  local row=rows[id]
  if not row then return nil end
  local result={ocean_speed_frac=0,canal_speed_frac=0,load_amount=10,refittable=false,cargo_age_ticks=185}
  for k,v in pairs(row) do result[k]=v end
  return result
end
function R.quote(id,buy_base)
  local r=R.model(id)
  if not r then return nil,"UNKNOWN_STOCK_TANKER" end
  r.price=math.floor((buy_base or R.purchase_base)*r.purchase_factor/256)
  return r
end
function R.running_fixed(id,ticks,running_base)
  return math.floor((running_base or R.running_base)*assert(rows[id]).running_factor*ticks/(365*74))
end
return R
