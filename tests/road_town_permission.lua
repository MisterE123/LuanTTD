local R=dofile("mods/luanttd_core/openttd/road_town_permission.lua")
local cross={4,8,1,2}
for t,min in pairs({[0]=16,64,112,-1000}) do
  assert(select(2,R.check(min-1,t,true,15,10,cross))=="TOWN_REFUSES")
  assert(R.check(min,t,true,15,10,cross)==math.max(min-50,math.min(min,-100)))
  assert(select(2,R.check(min,t,false,15,10,cross))=="TOWN_REFUSES")
end
assert(R.check(500,0,false,15,8,{4,8,1,0})==482,"unconnected half is not an inner street")
assert(R.check(500,0,false,15,4,{0,0,1,0})==482,"only one connecting neighbor is an edge")
assert(R.check(500,0,false,15,1,{1,2,4,8})==482,"nonreciprocal pavement doesn't form a neighbor")
assert(R.check(-180,3,true,15,10,cross)==-180,"do not raise a rating already below the penalty floor")
assert(R.check(-72,3,true,15,10,cross)==-100)
local town={x=0,z=0}
assert(R.in_radius(town,{x=2,z=0},4) and not R.in_radius(town,{x=2,z=1},4))
assert(not R.in_radius(town,{x=1,z=0},1))
assert(R.month(197,{{time_since_load=20},{time_since_load=21,time_since_unload=21},{time_since_unload=0}})==209)
assert(R.month(1000,{{time_since_load=20},{time_since_load=21}})==997)
assert(R.month(-1000,{{time_since_load=21}})==-1000)
local Sim=dofile("mods/luanttd_core/sim.lua")
local A=dofile("mods/luanttd_core/town_road_authority.lua")(Sim,R)
local state=Sim.new(1751)
local c=Sim.company(state,"a");local d=Sim.company(state,"b")
c.stock_town_authority_ratings={[1]=100}
local rail,road=Sim.id(11,10),Sim.id(10,10)
state.stations[1]={id=1,tile=road,mode="road",owner="a",time_since_load=20,town_growth_service_clock=true}
state.stations[2]={id=2,tile=road,mode="road",owner="b",time_since_load=21,town_growth_service_clock=true}
state.stock_rail_stations={[7]={id=7,tile=rail,owner="a"}}
state.stock_ship_commercial={service={stations={[24]={sign={x=11,y=10},host_mode="rail",host_id=7,owner="a",time_since_unload=8},
  [25]={sign={x=11,y=10},host_mode="rail",host_id=8,owner="b",time_since_unload=8}}}}
A.month(state,{id=1,x=10,z=10,radii={4}},A.station_view(state))
assert(c.stock_town_authority_ratings[1]==129 and d.stock_town_authority_ratings[1]==485)
local copy=dofile("mods/luanttd_core/packed_campaign.lua")
local restored=assert(copy.decode(copy.encode(state)))
assert(restored.companies.a.stock_town_authority_ratings[1]==129)

print("PASS RC1 town road authority thresholds, reciprocity, outer and inner deductions, rating floor and monthly station age")
