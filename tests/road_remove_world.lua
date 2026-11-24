local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local Terrain=dofile(mod.."openttd/terrain.lua")
local W=dofile(mod.."road_remove_world.lua")(Sim,Terrain,{occupied=function(_,id)return id==Sim.id(12,7) end})
local s=Sim.new(1746)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
local name="Builder"
Sim.company(s,name)
for x=10,14 do s.tiles[Sim.id(x,7)]={terrain="grass",h=0,build="road",road_bits=10,owner=name} end
local rail={kind="road",owner="Other",bits=5}
local t=s.tiles[Sim.id(14,7)]
t.tram,t.road_disallowed=rail,2
s.tiles[Sim.id(11,7)].owner="Other"
local q=assert(W.plan(s,name,Sim.id(10,7),Sim.id(14,7),0,true,false))
assert(q.cost==160 and #q.changes==3)
assert(q.changes[1].road_bits==8 and q.changes[2].road_bits==0 and q.changes[3].road_bits==2)
for _,change in ipairs(q.changes) do W.apply_plain(s,change) end
assert(t.tram==rail and t.road_disallowed==nil and t.road_bits==2)
assert(s.tiles[Sim.id(11,7)].road_bits==10 and s.tiles[Sim.id(12,7)].road_bits==10)
assert(s.tiles[Sim.id(13,7)].build==nil and s.tiles[Sim.id(13,7)].owner==nil)
print("PASS private normal-road adapter keeps unrelated owners, occupied traffic and parallel tram layers intact")
