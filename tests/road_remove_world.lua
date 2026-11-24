local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local Terrain=dofile(mod.."openttd/terrain.lua")
local W=dofile(mod.."road_remove_world.lua")(Sim,Terrain,{occupied=function(_,id)return id==Sim.id(12,7) end})
local s=Sim.new(1746)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
local name="Builder"
Sim.company(s,name)
for x=10,14 do s.tiles[Sim.id(x,7)]={terrain="grass",h=0,build="road",road_bits=10,owner=name} end
local rail={kind="road",tram_owner="Other",tram_bits=5,tramtype=1}
local t=s.tiles[Sim.id(14,7)]
t.tram,t.road_disallowed=rail,2
s.tiles[Sim.id(11,7)].owner="Other"
local q=assert(W.plan(s,name,Sim.id(10,7),Sim.id(14,7),0,true,false))
assert(q.cost==160 and #q.changes==3)
assert(q.changes[1].road_bits==8 and q.changes[2].road_bits==0 and q.changes[3].road_bits==2 and q.changes[3].under==5)
for _,change in ipairs(q.changes) do W.apply_plain(s,change) end
assert(t.tram==rail and t.road_disallowed==nil and t.road_bits==2)
assert(s.tiles[Sim.id(11,7)].road_bits==10 and s.tiles[Sim.id(12,7)].road_bits==10)
assert(s.tiles[Sim.id(13,7)].build==nil and s.tiles[Sim.id(13,7)].owner==nil)
print("PASS private normal-road adapter keeps unrelated owners, occupied traffic and parallel tram layers intact")

-- NoTest terrain changes may make a later inner tile become an edge:
-- stock test sees [10,11,12], actual sweep sees 11 after 10 vanished.
local Town=dofile(mod.."openttd/road_town_permission.lua")
local town={}
function town.town(state,_,id,wanted,journal)
  local rate=journal.ratings[1] or 500
  local near={}
  for direction=1,4 do
    local n=Sim.adjacent(id,direction)
    near[direction]=journal.road[n] or (n and Sim.road_bits(state,n) or 0)
  end
  local changed,why=Town.check(rate,0,false,Sim.road_bits(state,id),wanted,near)
  if not changed then return nil,why end
  journal.ratings[1]=changed
  return true
end
town.occupied=function()return false end
local TownWorld=dofile(mod.."road_remove_world.lua")(Sim,Terrain,town)
for x=10,12 do s.tiles[Sim.id(x,8)]={terrain="grass",h=0,build="road",road_bits=10,road_town=1} end
local city_first,city_last=Sim.id(10,8),Sim.id(12,8)
local ripe=assert(TownWorld.plan(s,name,city_first,city_last,0,false,true))
assert(#ripe.changes==3 and ripe.cost==240 and ripe.ratings[1]==446)
assert(s.tiles[city_first].road_bits==10 and s.tiles[city_first+1].road_bits==10)
s.companies[name].cash=100
ripe=assert(TownWorld.plan(s,name,city_first,city_last,0,false,true))
assert(#ripe.changes==1 and ripe.cost==80 and ripe.unfunded and ripe.ratings[1]==464)
print("PASS isolated ordered town permission replay reflects prior cuts and stock NoTest budget behavior")
