local root="mods/luanttd_core/"
local function m(n)return dofile(root..n..".lua")end
local Sim,T,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Bind=m("campaign_simulation_bindings")(Sim,root:sub(1,-2))
local owner="Montrose Air"
local s=Sim.new(251)
Sim.W,Sim.H=64,64
s.tiles,s.sites={},{}
s.corner_grid=T.new(64,64,function()return 0 end)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
s.air_owned_preview,s.air_fleet_preview=true,true
for id=1,64*64 do s.tiles[id]={terrain="grass",h=0,variant=1} end
for i,px in ipairs({10,44}) do
  local id=Sim.id(px,26)
  s.sites[i]={id=i,tile=id,kind="town",name="Airport town",population=240,service=0,stock={},produced={},received={}}
  s.tiles[id].site=i
  for x=px-3,px+9 do for z=13,17 do
    local t=s.tiles[Sim.id(x,z)]
    t.house,t.source_house=true,{id=4,town=i,completed=true}
  end end
end
local stock=m("openttd/stock_engine_calendar")
Sim.mount_road_bus_market(s,stock,1979,false)
local n=Bind.air(s,Slope,function()return true end,true,nil,nil,{metropolitan=true})
local q,e=n.quote(s,owner,Sim.id(10,18),"metropolitan")
assert(not q and e=="METROPOLITAN_AIRPORT_NOT_INTRODUCED")
s.day=stock.date(1985,1,1)-s.stock_bus_market.epoch
Sim.company(s,owner).cash=200000
local N,R,O=Bind.air(s,Slope,function()return true end,true,nil,nil,{metropolitan=true})
local function build(x,kind)
  local p,dirty=N.build(s,owner,Sim.id(x,18),kind)
  assert(p,dirty)
  assert(#dirty==36)
  return p
end
local one,two=build(10,"metropolitan"),build(44,"city")
assert(one.catchment_radius==6 and two.catchment_radius==5)
local unit=assert(O.commit(s,owner,assert(O.quote(s,owner,one.id,226))))
local run=assert(O.start(s,owner,one.id,two.id))
assert(unit.passengers==170 and run.target==one.id)
local visits={}
for d=1,240 do
  Sim.daily(s)
  assert(run.phase~="blocked",run.failure)
  if run.last_airfield then visits[run.last_airfield]=true end
  local paid=assert(Sim.air_paid_status(s,unit.id))
  if paid.fare>0 and visits[one.id] and visits[two.id] then
    local station=s.stock_ship_commercial.service.stations[0xC000+one.id]
    assert(#station.tiles==36 and station.tiles[1].kind=="airport_metropolitan")
    print("PASS Metropolitan paid service: RC1 date, 36 cells, catchment 6 and real roundtrip fares",d,paid.fare)
    return
  end
end
error("Metropolitan service did not pay and travel both ways")
