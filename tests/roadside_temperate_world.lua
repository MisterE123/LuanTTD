local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Board,Details=load("openttd/roadside_temperate"),load("openttd/roadside_details")
local Q=load("campaign_terrain_projection")
local W=load("road_reconstruction_world")(Sim,Terrain,{zone=function(t)return t.zone end},
  load("openttd/road_reconstruction"),load("openttd/road_slope"),
  load("openttd/rail_track"),load("openttd/slope"),Board)
local s=Sim.new(11)
local id=Sim.id(8,8)
local town_a={id=1,kind="town",tile=Sim.id(7,8),zone=4}
local town_b={id=2,kind="town",tile=Sim.id(20,8),zone=3}
s.stock_generated_profile={version=1}
s.sites={town_a,town_b}
s.stock_town_growth={towns={town_a,town_b}}
local t={terrain="grass",build="road",owner="Builder",road_bits=5}
s.tiles[id]=t
local revision=s.topology
assert(W.decorate(s,8,8)=="paved")
assert(W.decorate(s,8,8)=="street_lights")
assert(not W.decorate(s,8,8) and s.topology==revision)
assert(t.stock_roadside_town==1 and #s.changed==2 and Q.tile(t).roadside=="street_lights")
t.roadworks="paved";town_a.zone=3
assert(not W.decorate(s,8,8) and t.roadside=="street_lights")
t.roadworks=nil
assert(W.decorate(s,8,8)=="barren" and W.decorate(s,8,8)=="trees")
t.build="road_depot";t.roadside=nil
assert(not W.decorate(s,8,8) and not t.roadside)
-- Source details are based on the road OR tram mask, but two road
-- pieces are required independently of tram cables.
assert(#Details.points("street_lights",5,5,false,3,5)==2)
assert(#Details.points("trees",5,5,false,3,6)==4)
assert(not Details.points("trees",5,5,false,3,5))
assert(not Details.points("trees",5,5,"paved",3,12))
assert(not Details.points("street_lights",4,5,false,3,12))
print("PASS ordinary stock roadside staging, roadwork priority, bridge clearance and worker appearance projection")
