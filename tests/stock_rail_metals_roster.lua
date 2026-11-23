local R=dofile("mods/luanttd_core/openttd/rail_roster.lua")
local Data=dofile("mods/luanttd_core/openttd/iron_steel_data.lua")
local a,b=assert(R.entry(35)),assert(R.entry(36))
assert(a.image_index==41 and a.cargo=="iron_ore" and a.cargo_id==Data.cargo.iron_ore.id)
assert(b.image_index==42 and b.cargo=="steel" and b.cargo_id==Data.cargo.steel.id)
assert(a.cost_factor==179 and b.cost_factor==196 and a.tare==19 and b.tare==18)
assert(a.capacity==30 and b.capacity==20 and a.base_intro==1827 and b.base_intro==1827)
assert(a.source_model_life==50 and b.source_model_life==50 and a.climates==1 and b.climates==1)
assert(a.length==8 and b.length==8 and a.load_amount==5 and b.load_amount==5)
assert(R.purchase_price(35)==1398 and R.purchase_price(36)==1531)
assert(a.purchase_enabled==false and b.purchase_enabled==false)
local x=assert(R.stats({0,{stock_id=35,cargo_count=30},{stock_id=36,cargo_count=20}}))
assert(x.weight==134)
print("PASS exact 16.0-RC1 #35/#36 wagon source rows, cost, capacities and 50 t genuine stock cargo mass")

local Art=dofile("mods/luanttd_core/rail_dispatch_manifest.lua")
for _,case in ipairs({{35,"iron_ore",30,"iron_ore_hopper"},{36,"steel",20,"steel_truck"}}) do
  local id,cargo,cap,stem=unpack(case)
  for n=0,cap do
    local Sim={["rail_"..cargo.."_status"]=function() return {onboard=n,capacity=cap} end}
    assert(Art.wagon({stock_engine=0,stock_wagon=id},Sim,{})==stem..(n>=cap/2 and "_loaded" or "_empty"))
  end
end
print("PASS stock loading image selects the loaded body exactly at half capacity (15 t ore / 10 t steel)")
