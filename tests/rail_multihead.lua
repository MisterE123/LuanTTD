-- SPDX-License-Identifier: GPL-2.0-only
local dir="mods/bayline/"
local R=dofile(dir.."openttd/rail_roster.lua")
local Sim=dofile(dir.."sim.lua")
local Track=dofile(dir.."openttd/rail_track.lua")
local Lab=dofile(dir.."trackworks.lua")(Sim,Track,dofile(dir.."openttd/rail_follow.lua")(Track))
local Fleet=dofile(dir.."rail_depot_fleet.lua")(Sim,Lab,R)
local function fails(why,r,e) assert(not r and e==why,tostring(e).." ~= "..why) end
local function copy(a)
  if type(a)~="table" then return a end
  local r={};for k,v in pairs(a) do r[k]=copy(v) end
  return r
end
local d=R.entry(11)
assert(d.multiheaded and d.multiple_unit and d.capacity==38 and d.tare==32 and d.image_index==8)
assert(d.base_intro==13149 and d.decay_speed==20 and d.vehicle_life==12 and d.model_life==30)
assert(d.cargo_age_ticks==185 and d.load_amount==5 and d.length==8 and d.purchase_enabled==false)
assert(R.purchase_price(11)==17187)
local display=R.display(11)
assert(display.capacity==76 and display.power==600 and display.weight==64 and display.vehicles==2)
assert(display.tractive_effort==186200)
local parts=assert(R.physical_parts({{stock_id=11,cargo_count=38,rear_cargo_count=30},27,11,15}))
assert(#parts==6 and parts[1].role=="front" and parts[1].mate==3)
assert(parts[2].stock_id==27 and parts[3].role=="rear" and parts[3].mate==1 and parts[3].cargo_count==30)
assert(parts[4].role=="front" and parts[4].mate==5 and parts[5].role=="rear" and parts[5].mate==4)
assert(parts[6].stock_id==15)
local s=assert(R.stats({{stock_id=11,cargo_count=38,rear_cargo_count=38}}))
assert(s.price==17187 and s.parts[1].price==8593 and s.parts[2].price==8593 and s.parts[2].purchase_charge==0)
assert(s.power==600 and s.tare==64 and s.weight==68 and s.max_weight==68 and s.acceleration==32)
assert(s.display_max_speed==112 and s.max_track_speed==112 and s.air_drag==23 and s.tractive_effort==197837)
assert(s.running_year_fp==436800 and s.running_year==1706 and s.engine_count==1)
assert(s.total_length==16 and table.concat(s.offsets,",")=="0,8" and table.concat(s.coupling,",")=="8,4")
assert(s.cargo_capacity.passenger==76 and s.cargo_count.passenger==76 and s.cargo_load_per_pulse.passenger==10)
assert(s.parts[1].kind=="engine" and s.parts[2].kind=="rear_engine")
assert(s.parts[1].image_index==8 and s.parts[2].image_index==9)
assert(s.parts[1].powered and s.parts[2].powered and s.parts[1].power==300 and s.parts[2].power==300)
assert(s.parts[1].running_factor==42 and s.parts[2].running_factor==42)
assert(s.parts[1].slope_resistance==10200 and s.parts[2].slope_resistance==10200)
assert(R.stats({{stock_id=11,cargo_count=15,rear_cargo_count=31}}).weight==65,
  "Do not round the sum of the passengers' weights")
assert(R.stats({11,27},{max_train_tiles=1}).too_long and not R.stats({11},{max_train_tiles=1}).too_long)
local three=assert(R.stats({{stock_id=11,cargo_count=38,rear_cargo_count=38},{stock_id=27,cargo_count=40}}))
assert(three.price==19116 and three.tare==89 and three.weight==95 and three.max_weight==95)
assert(three.power==600 and three.engine_count==1 and three.acceleration==24 and three.running_year_fp==436800)
assert(three.total_length==24 and table.concat(three.offsets,",")=="0,8,16")
assert(three.cargo_capacity.passenger==116 and three.cargo_count.passenger==116 and three.cargo_load_per_pulse.passenger==15)
assert(three.parts[1].mate==3 and three.parts[2].stock_id==27 and three.parts[2].price==1929 and three.parts[3].mate==1)
local depot={kind="depot",owner="A",railtype=0,id=2}
fails("TOO_MANY_VEHICLES_IN_GAME",R.quote(depot,"A",{11,27},{roster_preview=true,mount_manley=true,vehicle_slots=2}))
local q=assert(R.quote(depot,"A",{11,27},{roster_preview=true,mount_manley=true,vehicle_slots=3,free_locomotive_numbers=1}))
assert(q.price==19116)
fails("RAIL_VEHICLE_NOT_MOUNTED",R.quote(depot,"A",{11,27,27},{roster_preview=true,mount_manley=true}))

assert(R.loading_wait(16,1,10,0)==40 and R.loading_wait(16,1,10,0,{gradual_loading=false})==10)
assert(R.load_slice({stock_id=11,cargo_count=35},50)==3 and R.unload_slice({stock_id=11,cargo_count=38})==5)
fails("INVALID_CARGO_COUNT",R.stats({{stock_id=11,rear_cargo_count=39}}))
assert(R.stats(copy(parts)).cargo_count.passenger==68)
local bad=copy(parts);bad[3].mate=4;fails("INVALID_DUAL_HEAD_LINK",R.stats(bad))
bad=copy(parts);bad[2].role="front";bad[2].mate=4;fails("INVALID_DUAL_HEAD_LINK",R.stats(bad))
bad={copy(parts[1])};fails("INVALID_DUAL_HEAD_LINK",R.stats(bad))
bad={{stock_id=11,role="front",mate=2},{stock_id=11,role="rear",mate=1},27}
fails("INVALID_DUAL_HEAD_LINK",R.stats(bad))
fails("RAIL_VEHICLE_NOT_MOUNTED",R.quote({kind="depot",owner="A",railtype=0,id=2},"A",{11},{roster_preview=true}))

local world=Sim.new(1751)
local at=Sim.id(2,4)
world.tiles[at].owner,world.tiles[at].rail_tracks="A",1
world.tiles[Sim.id(3,4)].owner,world.tiles[Sim.id(3,4)].rail_tracks="A",1
assert(Lab.depot(world,"A",at,Track.SW))
local c=Sim.company(world,"A")
assert(Fleet.initialize(world,{starting_year=1960,startup_random=9001,generation_seed=1751,
  climate="temperate",vehicle_pool=2}))
assert(Fleet.availability(world,11).public)
local prior=c.cash
fails("RAIL_VEHICLE_NOT_MOUNTED",Fleet.quote(world,"A",at,{11},{mount_manley=true}))
assert(c.cash==prior and not Fleet.occupies_depot(world,at))
-- Prepare uses explicit role/mate after a save, not the single logical
-- design id. This injection models a future paid constructor receipt,
-- not an enabled purchase and not a migration of user data.
world.stock_rail_fleet.units[1]={id=1,unit_number=1,owner="A",depot=at,depot_dir=Track.SW,
  stock_ids={11},status="depot",parts=R.physical_parts({11})}
world.stock_rail_fleet.next_id=2
world=copy(world)
local order=assert(Fleet.prepare_dispatch(world,"A",1))
assert(#order.parts==2 and #order.stock_ids==1 and order.stats.cargo_capacity.passenger==76)
fails("TOO_MANY_VEHICLES_IN_GAME",Fleet.quote(world,"A",at,{0}))
print("PASS: linked physical Manley–Morel halves; mixed weights, split costs, independent capacity and purchase hold")
