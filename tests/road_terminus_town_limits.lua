-- Production road stop planner: location, municipal naming and catchment
-- are separate. A legal terminus beside edge houses must remain buildable.
local dir="mods/luanttd_core/"
local Sim=dofile(dir.."sim.lua")
local Terrain=dofile(dir.."openttd/terrain.lua")
local s=Sim.new(1751)
s.tiles={};s.sites={}
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for id=1,Sim.W*Sim.H do s.tiles[id]={terrain="grass",h=0} end
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_bay_build=true,true,true,true,true
local at,co=Sim.id,"Road Test"
local center=at(8,10)
s.sites[1]={id=1,name="Market Town",tile=center,kind="town",stock={},received={},produced={}}
s.tiles[center].site=1
local old,edge,rural,stop=at(8,12),at(18,12),at(28,16),at(28,20)
local house=at(18,11)
s.tiles[house].house=true
s.tiles[house].source_house={id=0,town=1,completed=true}
for _,a in ipairs({old,edge,rural,stop}) do
  local x,z=Sim.xy(a)
  assert(Sim.build(s,co,"road",Sim.line(a,at(x+2,z))))
end
assert(Sim.site_radius(s,old)==1 and not Sim.site_radius(s,edge) and not Sim.site_radius(s,rural))
assert(Sim.road_passenger_acceptance(s,edge)==8 and Sim.road_passenger_acceptance(s,rural)==0)
assert(Sim.build(s,co,"road_bay_pair",{edge,rural}))
assert(Sim.build(s,co,"road_station",{stop}))
for _,a in ipairs({edge,rural,stop}) do
  local st=assert(s.stations[s.tiles[a].station])
  assert(st.site==1 and st.name:match("^Market Town") and #st.served==0)
end
assert(Sim.road_bay_status(s,edge) and Sim.road_bay_status(s,rural))
local wrong=at(19,12)
local q,why=Sim.plan(s,co,"road_bay_pair",{wrong})
assert(not q and why:find("exactly one road approach",1,true))
print("PASS termini beyond the old town radius: true house acceptance, valid rural stop, closest town name and approach guard")
