-- RunTileLoop -> CallVehicleTicks -> CallLandscapeTick (OpenTTD RC1
-- openttd.cpp). Force production, loading, and station rating onto the
-- same tick so a separate rail clock or an early rating really diverges.
local root="mods/luanttd_core/"
local function load(n) return dofile(root..n..".lua") end
local Sim=load("sim")
local Rating,Packets,Income=load("openttd/station_rating"),load("openttd/passengers"),load("openttd/income")
local Queue=load("station_rating_runtime")(Sim,Rating,Packets)
local C=load("openttd/station_catchment")(Packets,Rating,function()return 8 end,function()return 0 end)
local S=load("passenger_station_service")(C,Packets,Income,Rating,Queue,load("road_loading_runtime"),load("openttd/loading_timing"))
local owner="Passenger Co"
local physical=Sim.id(8,8)
local road={id=9,mode="road",owner=owner,stock_station_id=3,stock={},tile=Sim.id(15,8)}
local s={seed=1,day=3,tiles={},stations={[9]=road},topology=8,stock_generated_profile={},stock_town_growth={towns={}},
  corner_grid={},road_stock_house_supply=true,road_stock_loading=true,road_stock_clock=true,rail_paid_service=true,
  stock_rail_stations={[3]={id=3,stock_station_id=0,owner=owner,tiles={physical}}}}
s.tiles[physical]={rail_station_id=3,owner=owner}
s.tiles[Sim.id(8,7)]={house=true,source_house={id=0,town=1}}
local H={W=Sim.W,H=Sim.H,xy=Sim.xy,id=Sim.id,nearest_town=function()return {id=1} end,date=function()return 1950 end}
local observed={}
local ctx={width=Sim.W,height=Sim.H,xy=Sim.xy,house_at=function()return {id=0,town=1} end,
  year=function()return 1950 end,gradual=true}
local rail_id=0x4000+3
local train_id=950
local Mux={town_hooks={},consume=function(state,service,tick,mounted_ctx)
  if tick~=1000 then return end
  observed[#observed+1]="tile production"
  assert(S.produce(service,7,6,94,1,mounted_ctx)>0)
end}
local F=load("ship_paid_runtime")(H,S,Mux,function() end,function() end,
  load("rail_paid_actors"),nil,C,function(state)
    observed[#observed+1]="shared RNG"
    return 0 -- loss path performs at least one actual rating draw
  end)
local Rail={current_paid=function()end,paid_passengers=function()return {}end}
local train
local road_service={open_tick=function(_,tick)
  return function(st)
    assert(st==road)
    if tick==1000 then
      observed[#observed+1]="load road 3"
      assert(train.units==5,"Lower-ID rail platform loads before the separate road stop")
    end
  end,{9},{}
end}
local day=F.day(s,nil,Rail,nil,999,true,road_service)
local service=assert(s.stock_ship_commercial.service)
local platform=assert(service.stations[rail_id])
train=S.vehicle(service,{id=train_id,owner=owner,mode="rail",length=16,speed=64,built=1950})
S.pre_motion_tick(service,998,{station_active=function()return false end})
S.post_motion_tick(service,998,ctx)
local _,events=day.before(999)
assert(S.begin(service,train_id,rail_id,1,physical,{platform_tiles=1},999,ctx,events))
day.after(999,{},events)
day.finish_ratings(999,function(tick,station) Queue.station_tick(s,station,nil,tick) end)
local quality=platform.passenger_rating_state
quality.rating,quality.has_rating,quality.last_speed,quality.time_since_pickup=35,true,120,15
platform.rating_phase,road.passenger_rating_phase=184,184
local original=S.landscape_rating
S.landscape_rating=function(state,st,tick,source)
  observed[#observed+1]="rate rail "..st.stock_station_id
  assert(train.units==5,"Train boards before simultaneous platform rating")
  assert(state.post_tick==tick and tick==1000)
  return original(state,st,tick,source)
end
local ready
ready,events=day.before(1000)
assert(train.units==5 and platform.rating_phase==184)
assert(day.road_departures(1000)[1]==9)
observed[#observed+1]="move vehicles"
day.after(1000,ready,events)
observed[#observed+1]="grow towns and trees"
day.finish_ratings(1000,function(tick,station)
  observed[#observed+1]="rate road "..station.stock_station_id
  Queue.station_tick(s,station,nil,tick)
end)
assert(table.concat(observed,"|")==
 "tile production|load road 3|move vehicles|grow towns and trees|rate rail 0|shared RNG|rate road 3",table.concat(observed,"|"))
assert(platform.rating_phase==0 and road.passenger_rating_phase==0)
print("PASS same-tick stock production, train boarding, town growth phase, then rail/road ratings in physical StationID order")
