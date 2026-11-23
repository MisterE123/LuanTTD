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
