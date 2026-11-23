local path="mods/luanttd_core/"
local R=dofile(path.."openttd/rail_roster.lua")
local Freight=dofile(path.."rail_freight_kinds.lua")
local Art=dofile(path.."rail_dispatch_manifest.lua")
local row=assert(R.entry(34))
assert(row.image_index==40 and row.name=="Wood Truck" and row.cargo=="wood" and row.cargo_id==7)
assert(row.cost_factor==181 and R.purchase_price(34)==1414 and row.tare==16 and row.capacity==30)
assert(row.base_intro==1827 and row.decay_speed==20 and row.vehicle_life==20 and row.source_model_life==50)
assert(row.climates==7 and row.length==8 and row.load_amount==5 and row.speed==0 and row.power==0)
local depot={kind="depot",owner="timber_test",railtype=0}
local price,why=R.quote(depot,depot.owner,{0,34},{roster_preview=true})
assert(not price and why=="RAIL_VEHICLE_NOT_MOUNTED")
assert(R.quote(depot,depot.owner,{0,34},{roster_preview=true,mount_profile_wagons={[34]=true}}))
for n=0,30 do
  local stats=assert(R.stats({0,{stock_id=34,cargo_count=n}},{freight_trains=3}))
  assert(stats.weight==47+16+n*3)
  local Sim={rail_wood_status=function() return {onboard=n,capacity=30} end}
  assert(Art.wagon({stock_engine=0,stock_wagon=34},Sim,{})=="wood_truck_"..(n>=15 and "loaded" or "empty"))
end
assert(Freight.art_ready(Freight.profiles.wood,{wood_truck_empty=true,wood_truck_loaded=true}))
assert(not Freight.art_ready(Freight.profiles.wood,{wood_truck_loaded=true}))
for _,order in ipairs({{"wood","goods","farm"},{"goods","farm","wood"},{"farm","wood","goods"}}) do
  local H=dofile(path.."hotbar.lua")
  H.enable_railworks(true,true,true)
  H.enable_rail_coal();H.enable_rail_oil();H.enable_rail_metals(true,true);H.enable_rail_valuables()
  for _,cargo in ipairs(order) do H["enable_rail_"..cargo](true,true) end
  local f=assert(H.menus.rail_goods_freight)
  assert(f.title=="Timber & Goods trains")
  assert(f[2][1]=="rail_goods_load" and f[3][1]=="rail_goods_unload")
  assert(f[4][1]=="rail_wood_load" and f[5][1]=="rail_wood_unload")
  assert(#H.compact(H.menus.railfreight)==10 and #H.compact(f)==8)
  assert(H.path("rail_farm_freight") and H.path("rail_metal_freight") and H.path("rail_bank_freight"))
end
print("PASS exact RC1 #34 data, direction art thresholds, media gates and compact coexisting Wood/Goods routes")
