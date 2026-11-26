local path="mods/luanttd_core/"
local S=dofile(path.."sim.lua")
local T=dofile(path.."openttd/terrain.lua")
local G=dofile(path.."openttd/town_growth.lua")
local B=dofile(path.."openttd/town_growth_build.lua")(G,dofile(path.."openttd/town_growth_houses.lua"))
local H=dofile(path.."openttd/town_passengers.lua")
local F=dofile(path.."generated_campaign.lua")
S.W,S.H=64,64
local s=S.new(1)
s.tiles,s.sites,s.fleet={},{},{}
s.corner_grid=T.new(S.W,S.H)
for id=1,S.W*S.H do s.tiles[id]={terrain="grass",h=0,variant=1} end
s.stock_generated_profile={width=S.W,depth=S.H}
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
local now=s.day
local tick=s.passenger_house_clock.counter
local out=F.settle_frontage(S,s,{road,road,depot},growth.reconstruction,farm)
assert(out.road==1 and out.decorated==1 and not s.tiles[depot].roadside)
assert(out.fields==1 and out.grown==1 and not s.stock_farm_fields[invalid])
local r=s.stock_farm_fields[id]
assert(r.counter==2 and r.variant==5 and next(r.fences) and not r.last_tick)
assert(s.passenger_house_clock.counter==tick and s.day==now)
assert(not pcall(F.settle_frontage,S,s,{},growth.reconstruction,farm))
print("PASS five actual static RC1 setup visits: town surface, crop cycle, stale index, and no gameplay time advance")
