local path="mods/luanttd_core/"
local S=dofile(path.."sim.lua")
local T=dofile(path.."openttd/terrain.lua")
local G=dofile(path.."openttd/town_growth.lua")
local B=dofile(path.."openttd/town_growth_build.lua")(G,dofile(path.."openttd/town_growth_houses.lua"))
local H=dofile(path.."openttd/town_passengers.lua")
S.W,S.H=64,64
local s=S.new(1)
s.tiles,s.sites,s.fleet={},{},{}
s.corner_grid=T.new(S.W,S.H)
for id=1,S.W*S.H do s.tiles[id]={terrain="grass",h=0,variant=1} end
s.stock_generated_profile={width=S.W,depth=S.H,river_rng_cursor=1777}
s.stock_farm_fields,s.stock_farm_industries={},{}
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
local growth=dofile(path.."town_growth_runtime.lua")(S,T,G,B,H)
local town={kind="town",id=1,name="Temperate town",tile=S.id(7,8),population=900}
s.sites[1]=town
s.stock_town_growth={version=1,order={1},towns={[1]=G.new(1,7,8,{num_houses=90,population=900})}}
local road=S.id(7,8)
local depot=S.id(10,8)
local t=s.tiles[road]
t.build,t.road_town,t.road_bits,t.roadside="road",1,10,"grass"
s.tiles[depot].build,s.tiles[depot].road_town="road_depot",1
local farm=S.mount_farm_world(s,T,true)
s.stock_farm_industries[7]={id=7,removed=false}
local id,invalid=S.id(19,16),S.id(20,16)
s.stock_farm_fields[id]={kind="clear",ground="field",slope=0,base=0,counter=5,variant=4,fences={},industry=7}
s.stock_farm_fields[invalid]={kind="clear",ground="field",slope=0,base=1,counter=4,variant=8,fences={},industry=7}
local occupied=S.id(21,18)
s.tiles[occupied].house=true
s.tiles[occupied].source_house={id=0x19,town=1,completed=true}
-- Choose a site where the hash lets it grow in the five passes.
local tree_id=S.id(13,2) -- 12*11+9=141, visits at phases 0..4
s.tiles[tree_id].wood={class=4,type=1,count=1,growth=0,ground=0,density=3}
local sea=S.id(3,52)
s.tiles[sea].terrain,s.tiles[sea].water_class="water","sea"
local wet=S.id(4,52)
s.passenger_rating_rng={12345,67890}
local now=s.day
S.mount_coastal_flood(s)
local clock=s.passenger_house_clock
local last=H.new_clock(clock.log_x,clock.log_y,clock.head,0)
local field_tick,live_next
H.advance_initial(last,0x500,function(i,tick)
  if i+1==id then field_tick=tick end
end)
H.advance(last,1,function(i,t) live_next=t end)
local out,trace=S.prepare_initial_landscape(s,growth,farm)
assert(out.road==1 and out.decorated==1 and not s.tiles[depot].roadside)
assert(out.fields==1 and out.grown==1 and not s.stock_farm_fields[invalid])
local r=s.stock_farm_fields[id]
assert(r.counter==2 and r.variant==5 and next(r.fences) and r.last_tick==field_tick)
assert(clock.counter==0x500 and live_next==1281 and s.day==now)
assert(trace.start_head==1777 and trace.next_head==clock.head and trace.tree_changes>=1)
assert(s.tiles[tree_id].wood.growth==1)
assert(trace.tide_changes>0 and s.tiles[wet].water_class=="sea")
assert(trace.houses==5 and trace.passenger>0)
local cargo=s.stock_town_growth.towns[1].supplied.passenger
assert(cargo.new_max==trace.passenger and not cargo.new_act and not next(s.stations))
assert(s.passenger_rating_rng[1]~=12345 and s.passenger_rating_rng[2]~=67890)
assert(not pcall(S.prepare_initial_landscape,s,growth,farm))
print("PASS ordered RC1 setup: town streets, field cycles, tree growth, housing cargo, loaded LFSR head, first live phase")
