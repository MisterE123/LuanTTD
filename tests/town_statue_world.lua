local p="mods/luanttd_core/"
local function load(n) return dofile(p..n..".lua") end
local Sim,Terrain,G=load("sim"),load("openttd/terrain"),load("openttd/town_growth")
local H=load("openttd/town_passengers")
local W=load("town_growth_runtime")(Sim,Terrain,G,load("openttd/town_growth_build")(G,load("openttd/town_growth_houses")),H)
local A=load("campaign_authority_endpoint")
local Codec=load("packed_campaign")
local Project=load("campaign_terrain_projection")
local s=Sim.new(1751)
load("town_layout")(Sim,s)
s.corner_grid=load("terrain_preview")(Sim,Terrain,s)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
Sim.mount_stock_town_growth(s,W)
s.stock_generated_profile={width=Sim.W,depth=Sim.H}
local authority=A(Sim,{world=s})
local owner,rival="Patron","Neighbor"
local c,other=Sim.company(s,owner),Sim.company(s,rival)
local town_id=s.stock_town_growth.order[1]
local status=authority.town_authority(owner,town_id)
local q=status.value.statue
assert(q.tile and not q.affordable and q.cost==187500)
local command={kind="town_build_statue",town=town_id,tile=q.tile,cost=q.cost,revision=status.revision}
assert(not authority.command(owner,command).ok and c.cash==100000)
c.cash=200000
s.bridge_above={[q.tile]=1}
assert(not authority.command(owner,command).ok and c.cash==200000)
s.bridge_above=nil
local result=authority.command(owner,command)
assert(result.ok,result.why)
local t=s.tiles[q.tile]
assert(t.stock_landmark.kind=="statue" and t.stock_landmark.owner==owner and t.stock_landmark.town==town_id)
assert(t.owner==owner and c.cash==12500 and c.expense==187500 and other.cash==100000)
assert(authority.town_authority(owner,town_id).value.statue.existing==q.tile)
assert(not authority.town_authority(rival,town_id).value.statue.existing)
assert(not Sim.build(s,owner,"clear",{q.tile}) and not Sim.build(s,rival,"road",{q.tile}))
assert(Project.tile(t).stock_landmark.kind=="statue")
assert(Sim.station_has_town_statue(s,{town=town_id,owner=owner}))
assert(Sim.station_has_town_statue(s,{mode="road",site=town_id,owner=owner}))
assert(not Sim.station_has_town_statue(s,{town=town_id,owner=rival}))
assert(not Sim.station_has_town_statue(s,{town=town_id+1,owner=owner}))
local Kernel=load("openttd/station_rating")
local g={rating=128,last_speed=85,last_age=5,time_since_pickup=8,max_waiting_cargo=0,has_rating=true}
local rn,ry
for i=1,35 do
  rn=Kernel.step(g,{waiting=0,destinations=0})
  g.rating=rn.rating
end
local n=g.rating
for i=1,35 do
  ry=Kernel.step(g,{waiting=0,destinations=0,statue=Sim.station_has_town_statue(s,{town=town_id,owner=owner})})
  g.rating=ry.rating
end
assert(g.rating==n+26)
local restored=assert(Codec.decode(Codec.encode(s)))
assert(restored.stock_statue_count==1 and restored.stock_town_growth.towns[town_id].statues[owner]==q.tile)
assert(restored.tiles[q.tile].stock_landmark.kind=="statue")
assert(Sim.station_has_town_statue(restored,{town=town_id,owner=owner}))
print("PASS ordinary statue authority, pinned price, private town record, protected model data, persistent station rating")
-- A flattening foundation leaves non-flat objects untouched. A flat object
-- at sea level can be cleared by the source water owner, not the company.
local Flood=load("water_flood_world")(Sim,Terrain,load("openttd/water_flood"))
local function coast(slope)
  local state=Sim.new(1751)
  state.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z) return slope and x==8 and z==8 and 1 or 0 end,
    {freeform_edges=true})
  for i=1,Sim.W*Sim.H do state.tiles[i]={terrain="grass",h=0,variant=0,stock_void=true} end
  local sea,statue,stake=Sim.id(8,9),Sim.id(8,8),Sim.id(9,9)
  state.tiles[sea]={terrain="water",water_class="sea",h=0,variant=0}
  state.tiles[statue]={terrain="grass",owner=owner,h=0,variant=0,
    stock_landmark={kind="statue",town=town_id,owner=owner}}
  state.tiles[stake]={terrain="grass",owner=owner,h=0,variant=0,stock_object={kind="owned_land"}}
  state.stock_statue_count=1
  state.stock_town_growth={towns={[town_id]={statues={[owner]=statue}}}}
  assert(Flood.visit(state,8,9)==(slope and 1 or 2))
  assert(not state.tiles[stake].stock_object and not state.tiles[stake].owner)
  assert(state.tiles[stake].terrain=="water")
  assert((state.tiles[statue].stock_landmark~=nil)==slope)
  assert(Sim.town_statue_station_bonus(state,owner,town_id)==slope)
  if not slope then
    assert(state.stock_statue_count==0 and state.tiles[statue].terrain=="water" and not state.tiles[statue].owner)
  end
end
coast(false)
coast(true)
print("PASS flat stock objects flood; founded slope and town rating state follow source")
