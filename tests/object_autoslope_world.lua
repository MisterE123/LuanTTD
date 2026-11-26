-- Real worker command endpoint, quote/commit, billing, projection and save.
local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Projection,Codec=load("campaign_terrain_projection"),load("packed_campaign")
local A,Landscape=load("campaign_authority_endpoint"),load("campaign_landscape_commands")
Sim.W,Sim.H=64,64
local s=Sim.new(1950)
s.tiles,s.sites={},{}
s.stock_generated_profile={width=64,depth=64}
s.stock_town_growth={towns={[1]={}},order={}}
s.corner_grid=Terrain.new(64,64,function() return 3 end,{freeform_edges=true})
for id=1,64*64 do s.tiles[id]={terrain="grass",h=3,variant=0} end
local owner,rival="Builder","Neighbor"
local c,other=Sim.company(s,owner),Sim.company(s,rival)
local api=A(Sim,{world=s,landscape=Landscape(Sim,s)})
local function quote(op,who,x,z)
  return api.terrain_quote(who,{operation=op,first=Sim.id(x,z)})
end
local function commit(op,who,x,z,cost)
  local q=quote(op,who,x,z)
  assert(q.ok,q.why)
  assert(q.value.cost==cost, ("expected %d, got %d"):format(cost,q.value.cost))
  local company=s.companies[who]
  local before=company.cash
  local result=api.command(who,{kind="terrain_commit",token=q.value.token,revision=q.revision})
  assert(result.ok,result.why)
  assert(company.cash==before-cost)
  return q.value
end
local start=Sim.id(10,10)
commit("company_hq",owner,10,10,80)
local original=assert(s.stock_company_hqs[owner])
assert(original.origin==start and original.level==3)
-- Lower a corner shared by all four parcels. They remain at their
-- absolute height; each parcel pays one foundation in the rival's quote.
local changed=commit("lower",rival,11,11,1250)
assert(#changed.tiles==4 and #changed.corners==1)
for part,id in ipairs(original.tiles) do
  local x,z=Sim.xy(id)
  local slope,base,top=Terrain.tile(s.corner_grid,x,z)
  local projected=Projection.tile(s.tiles[id])
  assert(slope~=0 and base==2 and top==3 and projected.h==base)
  local mark=projected.stock_landmark
  assert(mark.kind=="headquarters" and mark.level==3 and mark.owner==owner and mark.part==part)
end
-- Lifting the outer corner higher would move the entire object; quote
-- is non-mutating, and disabling the stock policy rejects valid changes.
assert(not quote("raise",rival,10,10).ok and other.cash==98750)
s.stock_road_town_policy={autoslope=false}
assert(not quote("raise",rival,11,11).ok)
s.stock_road_town_policy=nil
local saved=assert(Codec.decode(Codec.encode(s)))
assert(saved.stock_company_hqs[owner].level==3 and saved.tiles[start].h==2)
assert(saved.tiles[start].stock_landmark.owner==owner and saved.companies[rival].cash==98750)
commit("raise",rival,11,11,1250)
for _,id in ipairs(original.tiles) do
  local x,z=Sim.xy(id)
  assert(Terrain.tile(s.corner_grid,x,z)==0 and s.tiles[id].h==3)
end
-- Commission a real statue and terraform it with the same company
-- and with the other company. Neither gets to remove it outright.
local G=load("openttd/town_growth")
local W=load("town_growth_runtime")(Sim,Terrain,G,
  load("openttd/town_growth_build")(G,load("openttd/town_growth_houses")),load("openttd/town_passengers"))
s.stock_town_growth=nil
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
s.sites[1]={id=1,kind="town",tile=Sim.id(45,45),name="Adams"}
Sim.mount_stock_town_growth(s,W)
c.cash=400000
local offer=assert(api.town_authority(owner,1).value.statue)
assert(offer.affordable)
local commissioned=api.command(owner,{kind="town_build_statue",town=1,tile=offer.tile,cost=offer.cost,
  revision=api.town_authority(owner,1).revision})
assert(commissioned.ok,commissioned.why)
local sx,sz=Sim.xy(offer.tile)
commit("lower",rival,sx,sz,500)
local slope,base,top=Terrain.tile(s.corner_grid,sx,sz)
assert(slope~=0 and base==2 and top==3)
assert(Sim.town_statue_station_bonus(s,owner,1) and not Sim.town_statue_station_bonus(s,rival,1))
assert(not quote("bulldoze",owner,sx,sz).ok)
assert(not quote("lower",owner,sx,sz).ok) -- would require a steep foundation
local saved_statue=assert(Codec.decode(Codec.encode(s)))
assert(saved_statue.tiles[offer.tile].stock_landmark.kind=="statue")
assert(saved_statue.stock_town_growth.towns[1].statues[owner]==offer.tile)
commit("raise",owner,sx,sz,500)
-- Own undeveloped land remains owned at no extra foundation charge.
-- The same corner is denied to a rival. Natural radio and lighthouse
-- objects remain protected in normal play even if the top is unchanged.
local stake,lighthouse,transmitter=Sim.id(20,20),Sim.id(30,30),Sim.id(40,40)
commit("purchase_land",owner,20,20,420)
assert(not quote("lower",rival,20,20).ok)
commit("lower",owner,20,20,250)
assert(s.tiles[stake].owner==owner and Sim.is_owned_land(s.tiles[stake]))
s.tiles[lighthouse].stock_landmark={kind="lighthouse"}
s.tiles[transmitter].stock_landmark={kind="transmitter"}
assert(not quote("lower",owner,30,30).ok)
assert(not quote("lower",owner,40,40).ok)
print("PASS ordinary authority: all HQ foundations, town statue rating, other company's landscaping, protected natural landmarks and owned stakes, reopen")
