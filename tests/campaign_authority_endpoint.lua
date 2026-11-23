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
