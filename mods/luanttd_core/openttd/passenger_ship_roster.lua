-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 table/engines.h MS 206–208, SVI 2–4 and
-- table/pricebase.h BuildShip/RunningShip. No stock art is embedded.
local R={order={206,207,208},purchase_base=65000,running_base=5600}
local rows={
  [206]={stock_id=206,local_id=2,image=2,vehicle_type=2,name="MPS Passenger Ferry",
    intro_after_1920=2192,decay_speed=5,life=30,base_life=55,climates=7,
    purchase_factor=96,acceleration=1,max_speed=64,capacity=100,running_factor=90},
  [207]={stock_id=207,local_id=3,image=2,vehicle_type=2,name="FFP Passenger Ferry",
    intro_after_1920=18628,decay_speed=5,life=30,base_life=90,climates=7,
    purchase_factor=112,acceleration=1,max_speed=128,capacity=130,running_factor=80},
  [208]={stock_id=208,local_id=4,image=3,vehicle_type=2,name="Bakewell 300 Hovercraft",
    intro_after_1920=17257,decay_speed=10,life=25,base_life=90,climates=7,
    purchase_factor=148,acceleration=1,max_speed=224,capacity=100,running_factor=190},
}
function R.model(id)
  local row=rows[id]
  if not row then return end
  local r={}
  for k,v in pairs(row) do r[k]=v end
  r.id=id
  return r
end
function R.quote(id,purchase_base)
  local r=R.model(id)
  if not r then return end
  r.price=math.floor((purchase_base or R.purchase_base)*r.purchase_factor/256)
  return r
end
function R.running_fixed(id,ticks,running_base)
  return math.floor((running_base or R.running_base)*assert(rows[id]).running_factor*ticks/(365*74))
end
return R
