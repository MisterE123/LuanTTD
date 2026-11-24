local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local Terrain=dofile(mod.."openttd/terrain.lua")
local Slope=dofile(mod.."openttd/road_slope.lua")
local Sweep=dofile(mod.."openttd/road_remove_long.lua")
local prices=dofile(mod.."openttd/road_bridge.lua")(dofile(mod.."openttd/slope.lua"))
local salvage=prices.road_clear_cost(1)
assert(salvage==-102)
local W=dofile(mod.."tram_remove_world.lua")(Sim,Terrain,Slope,Sweep,salvage)
local s=Sim.new(1746)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
local owner="Tram operator"
local c=Sim.company(s,owner)
local function id(x) return Sim.id(x,9) end
for x=9,15 do
  local t=s.tiles[id(x)]
  t.build,t.road_bits,t.road_disallowed,t.road_town,t.owner="road",10,2,1,nil
  t.tram={kind="road",tram_bits=10,tramtype=1,tram_owner=owner}
end
s.tiles[id(10)].tram.tram_owner="Competitor"
s.tiles[id(11)].tram.kind="drive_stop"
local busy=function(tile)return tile==id(12) end
local first,last=id(9),id(15)
local request={first=first,last=last,axis=0,start_half=true,end_half=false}
local before=c.cash
local q=assert(W.plan(s,owner,request,busy))
assert(q.cost==6*salvage and #q.changes==4)
assert(q.changes[1].id==first and q.changes[1].tram_bits==8)
assert(q.changes[2].id==id(13) and q.changes[2].tram_bits==0)
assert(q.changes[4].id==last and q.changes[4].tram_bits==2)
assert(c.cash==before and s.tiles[first].tram.tram_bits==10)
assert(W.apply(s,owner,q))
assert(c.cash==before-q.cost and not s.tiles[id(13)].tram and not s.tiles[id(14)].tram)
for x=9,15 do
  local t=s.tiles[id(x)]
  assert(t.build=="road" and t.road_bits==10 and t.road_disallowed==2 and t.road_town==1)
end
assert(s.tiles[id(10)].tram.tram_bits==10 and s.tiles[id(12)].tram.tram_bits==10)
assert(not W.plan(s,owner,{first=id(10),axis=0,start_half=false,end_half=true},busy))
c.cash=0
s.tiles[id(14)].tram={kind="road",tram_bits=10,tramtype=1,tram_owner=owner}
local prefix=assert(W.plan(s,owner,{first=id(9),last=id(14),axis=0,start_half=false,end_half=true},busy))
assert(not prefix.unfunded and prefix.cost==3*salvage and #prefix.changes==2)
print("PASS normal tram layer removal obeys exact half drag and stock ELRL salvage, skips busy/foreign/platform tiles, and never edits road")

-- Drive the same typed command the regular campaign worker receives.
local factory=dofile(mod.."campaign_road_construction.lua")
local net={remove_plan=W.plan,apply_remove=W.apply}
local blocked=false
local worker=factory(Sim,s,nil,nil,{tram={net=net,busy=function()return blocked end}})
local one={tool="tram_remove",first=id(14),axis=0,start_half=true,end_half=true}
c.cash=500
local offer=assert(worker.quote(owner,one))
blocked=true
assert(not worker.commit(owner,one,offer,true))
assert(c.cash==500 and s.tiles[id(14)].tram.tram_bits==10)
blocked=false
assert(worker.commit(owner,one,offer,true))
assert(s.tiles[id(14)].tram.tram_bits==8 and s.tiles[id(14)].road_bits==10 and c.cash==602)
print("PASS worker tram removal revalidates physical occupancy against the shown quote")
