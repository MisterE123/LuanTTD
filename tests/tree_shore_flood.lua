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
