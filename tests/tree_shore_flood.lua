local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Flood=load("sim"),load("openttd/terrain"),load("openttd/water_flood")
local W=load("water_flood_world")(Sim,Terrain,Flood)
local Track=load("openttd/rail_track")
local Water=load("openttd/ship_follow")(Track)
local Ship=load("ship_network")(Sim,Terrain,Water,{})
local Codec=load("packed_campaign")
local View=load("campaign_terrain_projection")
local function case(xes,zs)
  local s=Sim.new(1751)
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z) return xes[x] and zs[z] and 1 or 0 end,
    {freeform_edges=true})
  for id=1,Sim.W*Sim.H do s.tiles[id]={terrain="grass",h=0,variant=0,stock_void=true} end
  local source,id=Sim.id(8,9),Sim.id(8,8)
  s.tiles[source]={terrain="water",water_class="sea",h=0,variant=0}
  s.tiles[id]={terrain="grass",h=0,variant=0,wood={class=4,type=7,count=2,growth=4,ground=1,density=3}}
  return s,id,source
end
local s,id,source=case({[8]=true,[9]=true},{[8]=true})
assert(W.board(s).tile(8,8).slope==9)
assert(W.visit(s,8,9)==1)
local wood=s.tiles[id].wood
assert(wood.type==7 and wood.count==2 and wood.growth==4 and wood.ground==3 and wood.water_class=="sea")
assert(s.tiles[id].coastal_water and s.tiles[id].terrain=="water" and s.changed[1]==id)
assert(Water.at(Ship.board(s),id)==0,"A forest isn't a navigable coastal half")
local projected=View.tile(s.tiles[id])
assert(projected.coastal_water and projected.wood.ground==3)
assert(W.visit(s,8,8)==0,"Sea exposure keeps the shore grove wet")
s=assert(Codec.decode(Codec.encode(s)))
wood=s.tiles[id].wood
assert(wood.ground==3 and s.tiles[id].coastal_water)
s.tiles[source].terrain,s.tiles[source].water_class="grass",nil
assert(W.visit(s,8,8)==1)
assert(wood.type==7 and wood.count==2 and wood.growth==4 and wood.ground==0 and wood.density==3 and not wood.water_class)
assert(not s.tiles[id].coastal_water and s.tiles[id].terrain=="grass")
-- Single-corner slope and flat: source LandscapeClear removes the grove.
for _,row in ipairs({{{[8]=true},{[8]=true}},{{},{}}}) do
  s,id,source=case(unpack(row))
  local shape=W.board(s).tile(8,8).slope
  assert(Flood.one_raised(shape) or shape==0)
  assert(W.visit(s,8,9)==1 and not s.tiles[id].wood and s.tiles[id].terrain=="water")
  assert((s.tiles[id].coastal_water==true)==(shape~=0))
end
-- A bridge overlay must not be stripped by the natural tick.
s,id,source=case({[8]=true,[9]=true},{[8]=true})
s.rail_bridge_above={[id]=1}
assert(W.visit(s,8,9)==0 and s.tiles[id].wood.ground==1)
print("PASS RC1 wooded shores: intact flood/dry-out, flat and corner clearance, save, projection and ship blocking")

-- LandscapeClear is dispatched by stock tile type. A flooded full-edge grove
-- is still trees, never an open-water tile or a protected building.
s,id,source=case({[8]=true,[9]=true},{[8]=true})
assert(W.visit(s,8,9)==1)
local player="Forester"
local c=Sim.company(s,player)
c.cash=1000
s.sites={{id=1,kind="town",tile=Sim.id(8,7),name="Coast"}}
local C=load("campaign_road_construction")(Sim,s)
local request={tool="drag",axis=1,first=id,last=id,start_half=true,end_half=true}
local before=Sim.road_site_clear_cost(s.tiles[id])
assert(before==40)
local q,why=C.quote(player,request)
assert(q,why)
assert(#q.tiles==1 and s.tiles[id].wood.count==2 and c.cash==1000)
assert(q.cost==230,"road pieces/foundation plus $40 tree clearance")
s.bridge_above={[id]=123}
local a,error_=C.quote(player,request)
assert(not a and error_:find("protected structure",1,true))
s.bridge_above=nil
assert(C.commit(player,request,q,true))
assert(not s.tiles[id].wood and not s.tiles[id].coastal_water and s.tiles[id].terrain=="grass")
assert(s.tiles[id].build=="road" and c.cash==1000-q.cost and c.stock_town_authority_ratings[1]==465)
local _,reason=C.quote(player,{tool="drag",axis=1,first=source,last=source,start_half=true,end_half=true})
assert(reason:find("bridge over open water",1,true),reason)
print("PASS paid RC1 coast grove road clearance through the campaign handler; bridge/sea protections remain")
-- A drag may legally build a prefix. The successful receipt must still
-- tell players why the final tile was not built.
s,id,source=case({[8]=true,[9]=true},{[8]=true})
assert(W.visit(s,8,9)==1)
local start=Sim.id(7,8)
s.tiles[start]={h=0,terrain="grass",variant=0}
s.bridge_above={[id]=123}
c=Sim.company(s,player)
c.cash=1000
C=load("campaign_road_construction")(Sim,s)
request={tool="drag",axis=0,first=start,last=id,start_half=false,end_half=true}
local prefix,why=C.quote(player,request)
assert(prefix,why)
assert(prefix.stopped_at==id and prefix.stop_reason:find("protected structure",1,true))
local placed,msg=C.commit(player,request,prefix,true)
assert(placed and msg:find("Stopped",1,true) and msg:find("protected structure",1,true),msg)
assert(s.tiles[start].build=="road" and s.tiles[id].wood)
print("PASS partial road gesture reports the actual stopping reason in its quote and receipt")
