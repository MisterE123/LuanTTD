-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, src/table/engines.h MR #138–139 and ROV #22–23.
-- Stock three-quarter sprite art is not imported. These are engine data.
local F={}
local base=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local rows={
  goods_truck={stock_id=138,vehicle_type=1,image=5,name="Balogh Goods Truck",
    intro_after_1920=5479,decay_speed=20,life=15,base_life=55,climates=7,cargo="goods",
    purchase_factor=107,running_factor=90,speed=96,capacity=14,weight_quarters=38,power_tens_hp=12},
  craighead_goods_truck={stock_id=139,vehicle_type=1,image=22,name="Craighead Goods Truck",
    intro_after_1920=19724,decay_speed=20,life=15,base_life=55,climates=7,cargo="goods",
    purchase_factor=130,running_factor=168,speed=176,capacity=16,weight_quarters=48,power_tens_hp=22},
}
local climate=dofile(base.."/openttd/climate_road_freight_rc1.lua")
F.climate_order=climate.all
for key,row in pairs(climate.rows) do rows[key]=row end
function F.climate(engine) return climate.rows[engine]~=nil end
function F.climate_roster(name) return climate.by_landscape[name] or {} end
function F.climate_available(engine,name)
  for _,key in ipairs(F.climate_roster(name)) do if key==engine then return true end end
  return false
end
local originals=dofile(base.."/openttd/road_farm_fleet_data.lua")
F.farm_order={"livestock_van","livestock_uhl","livestock_foster","grain_truck","grain_thomas","grain_goss","wood_truck","wood_foster","wood_moreland"}
F.other_order={"coal_uhl","coal_dw","mail_mps","mail_reynard","mail_perry","oil_foster","oil_perry","goods_goss","iron_mps","iron_uhl","iron_chippy","steel_balogh","steel_uhl","steel_kelling","valuables_balogh","valuables_uhl","valuables_foster"}
for k,r in pairs(originals) do rows[k]=r end
F.road_order={}
for _,set in ipairs({F.farm_order,F.other_order}) do
  for _,k in ipairs(set) do F.road_order[#F.road_order+1]=k end
end
function F.farm(engine)
  local r=originals[engine]
  return r and (r.cargo=="wood" or r.cargo=="grain" or r.cargo=="livestock") or false
end
function F.additional(engine)
  return originals[engine]~=nil and not F.farm(engine)
end
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
  if originals[engine] then
    r.daily=2
    if engine=="wood_truck" or engine=="grain_truck" or engine=="livestock_van" then r.year=1935 end
  end
  return r
end
return F
