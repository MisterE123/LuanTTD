local mod=(core and core.get_modpath("luanttd_core") or "mods/luanttd_core")
local Sim=dofile(mod.."/sim.lua")
local Terrain=dofile(mod.."/openttd/terrain.lua")
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x<19 and 1 or 0 end)
s.rail_paid_service,s.rail_owned_service,s.ship_paid_service,s.air_paid_service=true,true,true,true
s.air_owned_preview,s.air_fleet_preview=true,true
for i,t in ipairs(s.tiles) do
  local x=Sim.xy(i)
  t.site,t.owner,t.wood,t.house,t.build=nil,nil,nil,nil,nil
  t.terrain=x>=19 and "water" or "grass"
end
local runtime=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,{
  road={start_year=1950,breakdowns=0,service_interval=150},
  rail={ready={},engines={},split={}},air={[215]=true},ferry={[206]=true}
})
local A=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,runtime)
local revision=0
local function command(owner,c)
  c.revision=revision
  local r=A.command(owner,c)
  assert(r.ok,r.why)
  revision=r.revision
  return r.value
end
for _,n in ipairs({"Rail","Water","Air"}) do command(n,{kind="company_open"}) end
local function choose(n,req)
  local q=A.transport_quote(n,req)
  assert(q.ok,q.why)
  local before=A.company(n).value.cash
  local value=command(n,{kind="transport_commit",token=q.value.token})
  assert(A.company(n).value.cash==before-q.value.cost)
  return value.id
end
local lower,upper=Sim.id(7,27),Sim.id(9,27)
choose("Water",{mode="ship",operation="waterwork",kind="canal",tile=lower,last=upper})
assert(s.tiles[lower].stock_canal and s.tiles[upper].stock_canal)
assert(s.tiles[lower].water_class=="canal")
local dock1=choose("Water",{mode="ship",operation="build",kind="dock",tile=Sim.id(18,8)})
local dock2=choose("Water",{mode="ship",operation="build",kind="dock",tile=Sim.id(18,16)})
local ship_depot=choose("Water",{mode="ship",operation="build",kind="depot",tile=Sim.id(22,10),axis=0})
local ferry_row=assert(A.depot("Water","ship",ship_depot).value.offers[1])
assert(ferry_row.help.service=="Passenger ferry" and ferry_row.help.connections:find("navigable water",1,true))
assert(choose("Water",{mode="ship",operation="buy",engine=206,depot=ship_depot})=="ferry")
assert(A.depot("Water","ship",ship_depot).value.vehicles[1].help.model:find("MPS Passenger Ferry",1,true))
command("Water",{kind="transport_start",mode="ship",depot=ship_depot,first=dock1,second=dock2})
assert(not A.transport_quote("Water",{mode="ship",operation="waterwork",kind="canal",
  tile=Sim.id(7,26),last=Sim.id(9,26)}).ok)
local ap=choose("Air",{mode="air",operation="build",tile=Sim.id(2,14)})
local aq=choose("Air",{mode="air",operation="build",tile=Sim.id(13,19)})
local air_row=assert(A.depot("Air","air",ap).value.offers[1])
assert(air_row.help.service=="Passenger and Mail aircraft" and air_row.help.model:find("Mail bags",1,true)
  and air_row.help.connections:find("compatible runway",1,true))
assert(choose("Air",{mode="air",operation="buy",engine=215,depot=ap}))
assert(A.depot("Air","air",ap).value.vehicles[1].help.model:find("Sampson U52",1,true))
command("Air",{kind="transport_start",mode="air",first=ap,second=aq})
local function track(req)
  local q=A.rail_quote("Rail",req)
  assert(q.ok,q.why)
  command("Rail",{kind="rail_commit",token=q.value.token})
end
local depot=Sim.id(2,5)
track({tool="track",first=Sim.id(3,5),last=Sim.id(14,5),track=0})
track({tool="depot",first=depot,direction=runtime.network.track.SW})
track({tool="station",first=Sim.id(4,5),last=Sim.id(6,5),axis=0,tracks=1,length=3})
track({tool="station",first=Sim.id(12,5),last=Sim.id(14,5),axis=0,tracks=1,length=3})
local prospects=assert(A.depot("Rail","rail",depot).value)
assert(#prospects.offers>=1 and #prospects.vehicles==0)
assert(prospects.offers[1].help.connections:find("two passenger rail platforms",1,true))
assert(not A.depot("Air","rail",depot).ok)
local engine=choose("Rail",{mode="rail",operation="buy",depot=depot,parts={0,27}})
command("Rail",{kind="transport_start",mode="rail",vehicle=engine,
  first=s.tiles[Sim.id(12,5)].rail_station_id,second=s.tiles[Sim.id(4,5)].rail_station_id})
local rail_row=A.depot("Rail","rail",depot).value.vehicles[1]
assert(rail_row.id==engine and rail_row.help.service=="Passenger train")
assert(A.orders("Rail","rail",engine).ok and A.orders("Water","ship","ferry").ok and A.orders("Air","air",1).ok)
assert(A.advance(4).tick==296 and runtime.rail.run.current(s).ticks>0)
assert(runtime.water.run.current(s).vehicle.tick>0 and runtime.air.run.current(s).vehicle.tick>0)
print("PASS worker builds, buys and dispatches rail, ferry and air using the normal commands")
local first={}
for _=1,30 do
  assert(A.advance(1).ok)
  local headlines=assert(A.news("Rail",1).value)
  for _,row in ipairs(headlines.items) do first[row.icon]=first[row.icon] or row end
  if first.train and first.ship and first.aircraft then break end
end
assert(first.train.kind=="arrival_player" and first.ship.kind=="arrival_other" and first.aircraft.kind=="arrival_other")
local recent=assert(A.news("Water",nil,0).value)
assert(recent.items[1].seq<recent.items[#recent.items].seq and recent.cursor==recent.head)
assert(recent.items[1].kind=="arrival_player" and recent.items[1].owner==nil and recent.items[1].tile)
for _,row in ipairs(recent.items) do assert(not row.owner and not row.ref_station) end
local latest=A.news("Rail",nil,nil,{action="last"}).value.article
assert(latest and latest.icon=="aircraft" and latest.year==1950)
assert(not A.news("Visitor",1).ok and not A.news("Rail",nil,-1).ok)
local Store=dofile(mod.."/packed_campaign.lua")
local saved=Store.decode(Store.encode(s))
local reload=dofile(mod.."/campaign_news.lua")(Sim,mod,{world=saved},{})
assert(reload.history("Rail",1,8).head==recent.head)
assert(not reload.arrive("ship","Water",dock1,Sim.id(19,8)),"station first-arrival bit survived checkpoint")
print("PASS real train, ferry and plane arrivals produce private-safe dated news; history and station one-shot bits persist")
local shed=Sim.id(5,23)
track({tool="depot",first=shed,direction=runtime.network.track.SW})
local function buy_part(kind,id)
  local quote=A.rail_assembly("Rail",shed)
  assert(quote.ok,quote.why)
  assert(not A.rail_assembly("Air",shed).ok)
  local match
  for _,offer in ipairs(quote.value[kind=="engine" and "engines" or "wagons"]) do
    if offer.id==id then match=offer;break end
  end
  assert(match,"eligible stock part missing")
  assert(match.help and (kind=="engine" and match.help.connections:find("Couple it to a passenger coach",1,true) or
    kind=="wagon" and match.help.service=="Passenger coach"))
  local money=A.company("Rail").value.cash
  command("Rail",{kind="rail_assembly",token=quote.value.token,operation=kind,stock=id})
  assert(A.company("Rail").value.cash==money-match.quote.price)
end
buy_part("wagon",27)
local loose=A.rail_assembly("Rail",shed).value
assert(#loose.bodies==1 and not loose.destinations[1].unit)
assert(loose.bodies[1].help.service=="Passenger coach")
buy_part("engine",0)
local staged=A.rail_assembly("Rail",shed).value
local position
for _,p in ipairs(staged.destinations) do if p.unit then position=p;break end end
assert(position)
if staged.bodies[1].unit then
  command("Rail",{kind="rail_assembly",token=staged.token,operation="move",from=staged.bodies[1].id})
  assert(#runtime.rail.owned.get(s,"Rail",position.unit).stock_ids==1)
  staged=A.rail_assembly("Rail",shed).value
end
assert(staged.bodies[1] and not staged.bodies[1].unit)
local no_charge=A.company("Rail").value.cash
command("Rail",{kind="rail_assembly",token=staged.token,operation="move",
  from=staged.bodies[1].id,to=position.id})
assert(A.company("Rail").value.cash==no_charge)
assert(#runtime.rail.owned.get(s,"Rail",position.unit).stock_ids==2)
assert(not A.command("Rail",{kind="rail_assembly",token=staged.token,operation="wagon",stock=27,revision=revision}).ok)
print("PASS worker issues priced separate locomotive/wagon offers, validates company, moves loosened cars and rejects replay")
local t=Sim.new(1751)
t.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
t.tram_enabled=true
for _,a in ipairs(t.tiles) do a.h=0;a.terrain="grass";a.wood=nil;a.house=nil;a.site=nil;a.build=nil end
local T=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,t,{
  road={start_year=1950,breakdowns=0,service_interval=150},
})
local W=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,T)
local name="Municipal Tramways"
assert(W.command(name,{kind="company_open"}).ok)
local function wbuild(kind,cells,direction)
  local q=W.transport_quote(name,{mode="tram",operation="build",kind=kind,cells=cells,direction=direction})
  assert(q.ok,q.why)
  local decision=W.command(name,{kind="transport_commit",token=q.value.token,revision=q.revision})
  assert(decision.ok,decision.why)
end
local id=Sim.id
local follow=dofile(mod.."/openttd/yapf_road_follow.lua")
local src,dst,other=id(5,10),id(8,8),id(8,13)
wbuild("depot",{src},follow.SW)
wbuild("road",Sim.line(id(6,10),id(8,10)))
wbuild("road",{id(6,10)},8)
wbuild("road",Sim.line(id(8,7),id(8,14)))
wbuild("drive_stop",{dst},follow.SE)
wbuild("drive_stop",{other},follow.SE)
local tram=assert(W.company(name))
assert(W.command(name,{kind="transport_start",mode="tram",depot=src,first=dst,second=other,revision=tram.revision}).ok)
assert(W.orders(name,"tram",1).ok)
assert(W.advance(4).ok and t.tram_pilot.steps>0)
local latest=W.company(name)
assert(W.command(name,{kind="transport_start",mode="tram",clear=true,revision=latest.revision}).ok)
assert(not t.tram_pilot and t.tiles[dst].tram)
print("PASS worker constructs track and stops, dispatches and advances the stock tram, reads orders and clears the run")
local model=t.stock_bus_market.models[117]
t.day=model.public_date-t.stock_bus_market.epoch-1
assert(not Sim.vehicle_available(t,"leopard_bus"))
assert(W.advance(1).ok and Sim.vehicle_available(t,"leopard_bus"))
local paper=W.news(name,1).value.items
local introduced
for _,row in ipairs(paper) do
  if row.kind=="new_vehicles" and row.headline:find("Hereford Leopard Bus",1,true) then
    introduced=row;break
  end
end
assert(introduced and introduced.day==1 and t.day==introduced.economy)
assert(W.advance(1).ok)
local count=0
for _,row in ipairs(W.news(name,1).value.items) do
  if row.headline==introduced.headline then count=count+1 end
end
assert(count==1)
print("PASS introduction is emitted once on the actual source public-sale date")
return true
