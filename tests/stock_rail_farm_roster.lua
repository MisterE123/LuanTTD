local mod="mods/luanttd_core/"
local R=dofile(mod.."openttd/rail_roster.lua")
local Art=dofile(mod.."rail_dispatch_manifest.lua")
local Freight=dofile(mod.."rail_freight_kinds.lua")
local depot={kind="depot",owner="farm_test",railtype=0}
for _,v in ipairs({
  {31,"Livestock Van","livestock",37,20,192,1500,25,4,3,3,"livestock_van"},
  {33,"Grain Hopper","grain",39,19,182,1421,30,6,7,16,"grain_hopper"},
}) do
  local id,name,cargo,img,tare,factor,price,capacity,global,climates,weight,stem=unpack(v)
  local row=assert(R.entry(id))
  assert(row.name==name and row.cargo==cargo and row.image_index==img)
  assert(row.tare==tare and row.cost_factor==factor and R.purchase_price(id)==price)
  assert(row.capacity==capacity and row.cargo_id==global and row.climates==climates)
  assert(row.base_intro==1827 and row.decay_speed==20 and row.vehicle_life==20 and row.source_model_life==50)
  assert(row.length==8 and row.load_amount==5 and row.speed==0 and row.power==0)
  local q,why=R.quote(depot,depot.owner,{0,id},{roster_preview=true})
  assert(not q and why=="RAIL_VEHICLE_NOT_MOUNTED")
  assert(R.quote(depot,depot.owner,{0,id},{roster_preview=true,mount_profile_wagons={[id]=true}}))
  for n=0,capacity do
    local stats=assert(R.stats({0,{stock_id=id,cargo_count=n}},{freight_trains=3}))
    assert(stats.weight==47+tare+math.floor(n*3*weight/16))
    local expected=stem..(id==31 and "" or n>=15 and "_loaded" or "_empty")
    local sim={["rail_"..cargo.."_status"]=function() return {onboard=n,capacity=capacity} end}
    assert(Art.wagon({stock_engine=0,stock_wagon=id},sim,{})==expected)
  end
end
-- Both or either model may mount. A missing full Grain mesh must never
-- silently fall back to a passenger or metal wagon in the buying menu.
assert(not Freight.art_ready(Freight.profiles.grain,{grain_hopper_empty=true}))
assert(Freight.art_ready(Freight.profiles.grain,{grain_hopper_empty=true,grain_hopper_loaded=true}))
assert(Freight.art_ready(Freight.profiles.livestock,{livestock_van=true}))
local H=dofile(mod.."hotbar.lua")
H.enable_railworks(true,true,true)
H.enable_rail_coal();H.enable_rail_goods();H.enable_rail_oil();H.enable_rail_metals(true,true);H.enable_rail_valuables()
H.enable_rail_farm(true,true)
local f=assert(H.menus.railfreight)
assert(#H.compact(f)==10)
for _,k in ipairs({"rail_farm_freight","rail_goods_freight","rail_bank_freight","rail_metal_freight"}) do
  local path=assert(H.path(k))
  assert(path[#path-1]=="railfreight" and path[#path]==k)
end
assert(H.menus.rail_goods_freight[2][1]=="rail_goods_load" and H.menus.rail_goods_freight[3][1]=="rail_goods_unload")
assert(#H.compact(H.menus.rail_farm_freight)==8)
print("PASS exact stock #31/#33 prices, weights, art transitions, media gates and full hotbar")
