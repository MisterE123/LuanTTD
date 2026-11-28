-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 table/engines.h. Grain road models resolve the
-- original active-climate cargo group to maize or wheat.
local D={}
local base=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local grain=dofile(base.."/openttd/road_farm_fleet_data.lua")
local Water=dofile(base.."/openttd/town_water_industry_rc1.lua")
local function fleet(order,cargo,climates,rows)
  for i,r in ipairs(rows) do
    local name,id,image,intro,life,purchase,running,speed,capacity,weight,power=unpack(r)
    D[order[i]]={name=name,stock_id=id,road_model=id-116,vehicle_type=1,climates=climates,cargo=cargo,
      image=image,intro_after_1920=intro,decay_speed=20,life=15,base_life=life,
      purchase_factor=purchase,running_factor=running,speed=speed,capacity=capacity,weight_quarters=weight,power_tens_hp=power}
  end
end
local food={"food_foster","food_perry","food_chippy"}
local fruit={"fruit_balogh","fruit_uhl","fruit_kelling"}
local water={"water_uhl","water_balogh","water_mps"}
local maize={"maize_hereford","maize_thomas","maize_goss"}
local wheat={"wheat_hereford","wheat_thomas","wheat_goss"}
fleet(food,"food",6,{
  {"Foster Food Van",156,11,5479,55,112,90,96,17,38,12},
  {"Perry Food Van",157,28,18628,55,134,168,176,20,48,22},
  {"Chippy Food Van",158,45,30681,85,144,240,224,22,69,45},
})
fleet(fruit,"fruit",4,{
  {"Balogh Fruit Truck",168,15,5479,55,118,90,96,18,38,12},
  {"Uhl Fruit Truck",169,32,21335,55,148,168,176,20,48,22},
  {"Kelling Fruit Truck",170,49,33753,85,158,240,224,23,69,45},
})
for i,k in ipairs({"grain_truck","grain_thomas","grain_goss"}) do
  for _,v in ipairs({{maize[i],"maize"},{wheat[i],"wheat"}}) do
    local row={}
    for key,value in pairs(grain[k]) do row[key]=value end
    row.cargo,row.road_model=v[2],row.stock_id-116
    D[v[1]]=row
  end
end
for i,k in ipairs(water) do D[k]=Water.road_tankers[i] end
local function join(...)
  local out={}
  for _,a in ipairs({...}) do for _,id in ipairs(a) do out[#out+1]=id end end
  return out
end
return {rows=D,all=join(water,food,fruit,maize,wheat),
  by_landscape={arctic=join(food,wheat),tropic=join(water,food,fruit,maize)},
  primary={water=water[1],food=food[1],fruit=fruit[1],maize=maize[1],wheat=wheat[1]}}
