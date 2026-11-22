-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, src/table/engines.h MR #139 and ROV #23.
-- Stock three-quarter sprite art is not imported. These are engine data.
local F={}
local rows={
  craighead_goods_truck={stock_id=139,vehicle_type=1,image=22,name="Craighead Goods Truck",
    intro_after_1920=19724,decay_speed=20,life=15,base_life=55,climates=7,cargo="goods",
    purchase_factor=130,running_factor=168,speed=176,capacity=16,weight_quarters=48,power_tens_hp=22},
}
function F.row(engine)
  local r=rows[engine]
  if not r then return end
  local out={}
  for k,v in pairs(r) do out[k]=v end
  return out
end
function F.offer(engine)
  local r=F.row(engine)
  if not r then return end
  r.mode="road";r.development=true;r.stock_engine_id=r.stock_id;r.stock_id=nil
  r.buy_factor=r.purchase_factor;r.cost=math.floor(14000*r.purchase_factor/256)
  r.display_speed=r.speed/2;r.tractive_effort=76;r.air_drag=0
  r.load_amount=5;r.cargo_age_ticks=185
  return r
end
return F
