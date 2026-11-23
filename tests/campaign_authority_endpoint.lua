-- No engine globals. The worker-side endpoint uses the ordinary stock Sim rules.
local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
local T=dofile(mod.."/openttd/terrain.lua")
local s=Sim.new(1751)
s.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
for _,tile in ipairs(s.tiles) do
  tile.terrain,tile.h="grass",0
  tile.wood,tile.house,tile.site,tile.build,tile.owner=nil,nil,nil,nil,nil
end
local runtime=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,{
  road={start_year=1950,breakdowns=0,service_interval=150},
})
local A=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,runtime)
local john="Authorised"
local p,q,d=Sim.id(4,7),Sim.id(14,7),Sim.id(8,8)
local build={kind="road_build",first=p,last=q,revision=0}
local built=A.command(john,build)
assert(built.ok and built.revision==1)
local cash=s.companies[john].cash
assert(not A.command(john,build).ok and cash==s.companies[john].cash)
assert(not A.snapshot(1,1,33,1).ok and not A.snapshot(0,1,1,1).ok)
local patch=A.snapshot(4,7,11,1)
assert(patch.ok and #patch.value.tiles==11 and patch.value.tiles[1].id==p)
for _,tile in ipairs(patch.value.tiles) do assert(tile.build=="road" and tile.road and tile.road>0) end
patch.value.tiles[1].build="changed in projection"
assert(s.tiles[p].build=="road")
assert(Sim.build(s,john,"road_station",{p,q}))
assert(Sim.build(s,john,"road_depot",{d}))
local id=assert(Sim.purchase(s,john,"bus","passenger",nil,d))
local first={kind="road_order_add",vehicle=id,station=s.tiles[p].station,revision=1}
assert(A.command("Not owner",first).why=="NOT_YOUR_ROAD_VEHICLE")
assert(A.command(john,first).revision==2)
assert(A.command(john,{kind="road_order_add",vehicle=id,station=s.tiles[q].station,revision=2}).revision==3)
assert(A.command(john,{kind="road_toggle",vehicle=id,revision=3}).revision==4)
assert(not A.advance(5).ok and A.advance(1).tick==74)
local close=A.snapshot(3,6,24,12)
local far=A.snapshot(35,22,4,3)
assert(close.ok and #close.value.vehicles==1 and close.value.vehicles[1].id==id)
assert(far.ok and #far.value.vehicles==0)
assert(s.fleet[id].running)
print("PASS single-owner construction/road orders; stale and foreign edits rejected; scoped projection does not own actors")
local sectors=A.snapshots({{x=3,z=6,w=24,h=12},{x=35,z=22,w=4,h=3}},.5)
assert(sectors.ok and sectors.tick==74 and #sectors.value==2 and #sectors.value[1].actors==1 and #sectors.value[2].actors==0)
assert(not A.snapshots({{x=1,z=1,w=1,h=1},{x=2,z=2,w=100,h=100}}).ok)
print("PASS multiple sectors captured at the same authoritative tick")
local bend={tool="bend",first=Sim.id(20,10),last=Sim.id(23,13)}
local offer=A.road_quote(john,bend)
assert(offer.ok and offer.revision==4 and #offer.value.tiles>2 and offer.value.cost>0)
local starting_cash=s.companies[john].cash
s.topology=s.topology+1
assert(not A.command(john,{kind="road_commit",revision=4,request=bend,quote=offer.value}).ok)
assert(s.companies[john].cash==starting_cash)
local fresh=A.road_quote(john,bend)
local built_bend=A.command(john,{kind="road_commit",revision=4,request=bend,quote=fresh.value})
assert(built_bend.ok and #built_bend.value==#fresh.value.tiles)
assert(s.companies[john].cash==starting_cash-fresh.value.cost)
print("PASS worker validates and applies the ordinary paid road bend; obsolete topology quote cannot spend")
assert(A.company("Another").why=="COMPANY_NOT_OPEN")
assert(A.command("Another",{kind="company_open",revision=5}).revision==6)
local before=A.company("Another")
assert(before.ok and before.value.day==nil and before.day==1 and before.value.cash>0)
assert(A.command("Another",{kind="company_loan",revision=6,amount=10000}).revision==7)
assert(A.company("Another").value.cash==before.value.cash+10000)
local vehicle=assert(Sim.vehicle_offer(s,"bus"))
assert(not A.command(john,{kind="road_buy",revision=7,engine="bus",cargo="passenger",depot=d,cost=vehicle.cost+1}).ok)
local purchase=A.command(john,{kind="road_buy",revision=7,engine="bus",cargo="passenger",depot=d,cost=vehicle.cost})
assert(purchase.ok and purchase.revision==8 and s.fleet[purchase.value].owner==john)
print("PASS typed company and depot actions charge only the owning company at the quoted price")
local paint=A.snapshot(3,6,17,5)
assert(#paint.value.corners==18*6)
local source=paint.value.tiles[19].surface
assert(source.build==s.tiles[p].build and source.road_bits==s.tiles[p].road_bits)
source.build="visual only"
assert(s.tiles[p].build=="road_station")
print("PASS projected ground, road geometry and shared corners are detached from authoritative tiles")
local s2=Sim.new(1751)
s2.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
s2.rail_paid_service,s2.rail_owned_service,s2.rail_block_preview=true,true,true
for _,t in ipairs(s2.tiles) do
  t.terrain,t.h="grass",0
  t.wood,t.house,t.site,t.build,t.owner=nil,nil,nil,nil,nil
end
local rails=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s2,{
  road={start_year=1950,breakdowns=0,service_interval=150},rail={ready={},engines={},split={}},
})
local station_worker=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,rails)
assert(station_worker.command(john,{kind="company_open",revision=0}).ok)
local t0,t1=Sim.id(12,15),Sim.id(21,15)
local rails_offer=station_worker.rail_quote(john,{tool="track",first=t0,last=t1,track=0})
assert(rails_offer.ok and #rails_offer.value.tiles==10 and rails_offer.value.cost>0)
local money=s2.companies[john].cash
assert(not station_worker.command("Stranger",{kind="rail_commit",revision=1,token=rails_offer.value.token}).ok)
assert(station_worker.command(john,{kind="rail_commit",revision=1,token=rails_offer.value.token}).ok)
assert(s2.tiles[t0].rail_tracks==1 and s2.companies[john].cash==money-rails_offer.value.cost)
assert(not station_worker.command(john,{kind="rail_commit",revision=2,token=rails_offer.value.token}).ok)
local depot=station_worker.rail_quote(john,{tool="depot",first=Sim.id(11,15),direction=2})
assert(depot.ok,depot.why)
assert(station_worker.command(john,{kind="rail_commit",revision=2,token=depot.value.token}).ok)
print("PASS worker owns pinned railway track and auto-connecting depot quote, debit and commit")
local plot=Sim.id(36,26)
local land=A.terrain_quote(john,{operation="raise",first=plot})
assert(land.ok and #land.value.corners==1 and land.value.cost>0)
local cost=A.company(john).value.cash
local applied=A.command(john,{kind="terrain_commit",revision=8,token=land.value.token})
assert(applied.ok and T.corner(s.corner_grid,36,26)==1)
assert(A.company(john).value.cash==cost-land.value.cost)
local clear=A.terrain_quote(john,{operation="bulldoze",first=Sim.id(21,10)})
assert(clear.ok and A.command(john,{kind="terrain_commit",revision=9,token=clear.value.token}).ok)
print("PASS worker reshapes shared terrain and bulldozes through the existing paid commands")
local bridge=A.transport_quote(john,{operation="bridge",mode="road",tile=Sim.id(6,24),last=Sim.id(10,24),style=0})
assert(bridge.ok,bridge.why)
local before_bridge=A.company(john).value.cash
local committed=A.command(john,{kind="transport_commit",revision=10,token=bridge.value.token})
assert(committed.ok and #committed.value.tiles==5 and A.company(john).value.cash==before_bridge-bridge.value.cost)
assert(s.bridge_above[Sim.id(8,24)])
print("PASS worker commits a real timber bridge at the stock price and preserves ground below")
local support=A.snapshot(8,24,1,1).value.registries
assert(support.bridge_above and support.stock_road_bridges)
local support_id=support.bridge_above[Sim.id(8,24)]
assert(support.stock_road_bridges[support_id].axis==0 and #support.stock_road_bridges[support_id].middle==3)
assert(not support.stations and not support.fleet and not support.companies)
print("PASS bridge support sectors include the linked span without exposing unrelated simulation registries")
