local mod="mods/luanttd_core/"
local R=dofile(mod.."openttd/rail_roster.lua")
local data=dofile(mod.."openttd/temperate_bank_data.lua")
local a=assert(R.entry(37))
assert(a.name=="Armoured Van" and a.image_index==43 and a.cargo=="valuables" and a.cargo_id==data.cargo.id)
assert(a.cost_factor==255 and a.tare==30 and a.capacity==20 and a.base_intro==1827)
assert(a.source_model_life==50 and a.climates==7 and a.decay_speed==20 and a.vehicle_life==20)
assert(a.length==8 and a.load_amount==5 and a.speed==0 and a.power==0)
assert(R.purchase_price(37)==1992 and a.purchase_enabled==false)
for _,f in ipairs({1,3,10}) do
  for n=0,20 do
    local stats=assert(R.stats({0,{stock_id=37,cargo_count=n}},{freight_trains=f}))
    assert(stats.weight==47+30+math.floor(n*f*data.cargo.weight_16/16))
  end
end
local depot={kind="depot",owner="bank_test",railtype=0}
local quote,why=R.quote(depot,depot.owner,{0,37},{roster_preview=true})
assert(not quote and why=="RAIL_VEHICLE_NOT_MOUNTED")
assert(R.quote(depot,depot.owner,{0,37},{roster_preview=true,mount_profile_wagons={[37]=true}}))
local Art=dofile(mod.."rail_dispatch_manifest.lua")
for n=0,20 do
  assert(Art.wagon({stock_engine=0,stock_wagon=37},{rail_valuables_status=function() return {onboard=n,capacity=20} end},{})=="armoured_van")
end
local hidden=Art.scan("not-a-real-mod-path",false,false)
assert(not hidden.ready.armoured_van)
print("PASS exact RC1 #37 capacity, mass, price, service gate and identical closed appearance at all loading levels")
