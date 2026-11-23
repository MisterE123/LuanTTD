local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local s=Sim.new(1751)
local Terrain=dofile(mod.."openttd/terrain.lua")
dofile(mod.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(Sim,Terrain,s)
local r=dofile(mod.."campaign_authority_runtime.lua")(Sim,mod,s,{road={start_year=1950,breakdowns=0,service_interval=150}})
local A=dofile(mod.."campaign_authority_endpoint.lua")(Sim,r)
local name="RoadQA"
local a,b,depot=Sim.id(9,12),Sim.id(18,12),Sim.id(17,13)
assert(Sim.build(s,name,"road",Sim.line(a,b)))
assert(Sim.build(s,name,"road_station",{a,b}))
assert(Sim.build(s,name,"road_depot",{depot}))
local v=assert(Sim.purchase(s,name,"bus","passenger",nil,depot))
for _,stop in ipairs({a,b}) do assert(Sim.add_order(s,name,v,s.tiles[stop].station)) end
assert(Sim.toggle(s,name,v))
for _=1,28 do
  r.day()
  if r.news.history(name,1,8).count==2 then break end
end
local newspaper=A.news(name,1).value
assert(newspaper.count==2, "both physical bus stops should have been visited")
for i,row in ipairs(newspaper.items) do
  assert(row.icon=="bus" and row.kind=="arrival_player" and not row.owner)
  assert(row.tile==a or row.tile==b)
  if i>1 then assert(newspaper.items[i-1].seq>row.seq) end
end
for _=1,14 do r.day() end
local arrivals=0
for _,row in ipairs(A.news(name,1).value.items) do if row.icon=="bus" then arrivals=arrivals+1 end end
assert(arrivals==2,"repeat bus visits must not add first arrivals")
-- A removed physical station must not be navigable from preserved news.
s.stations[s.tiles[a].station]=nil
r.news.topology_changed()
arrivals=0
for _,row in ipairs(A.news(name,1).value.items) do
  if row.icon=="bus" then arrivals=arrivals+1;assert(row.tile==b) end
end
assert(arrivals==1)
local N=dofile(mod.."openttd/news.lua")
local isolated=N.new()
for _=1,1100 do N.push(isolated,{kind="general",economy=0}) end
assert(#isolated.items==1024 and isolated.items[#isolated.items].seq==77)
N.push(isolated,{kind="advice",economy=0,headline="Test private",owner=name,private=true})
local outsider,count=N.history(isolated,"Other",1,8)
assert(count==1023 and outsider[1].seq==1100)
print("PASS physical bus arrives once at each stop, station removal deletes reference, hard cap and per-company privacy")
