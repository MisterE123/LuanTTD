local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Slope=load("sim"),load("openttd/terrain"),load("openttd/slope")
local T=load("openttd/rail_track")
local F=load("openttd/water_flood")
local R=load("openttd/rail_half_water")(T,Slope)
local W=load("water_flood_world")(Sim,Terrain,F,T,Slope,R)
local Water=load("openttd/ship_follow")(T)
local Net=load("ship_network")(Sim,Terrain,Water,{})
local Codec=load("packed_campaign")
local View=load("campaign_terrain_projection")
local function case(bits)
  local s=Sim.new(22)
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)return x==8 and z==8 and 1 or 0 end,
    {freeform_edges=true})
  local id,wet=Sim.id(8,8),Sim.id(8,9)
  for i=1,Sim.W*Sim.H do s.tiles[i]={terrain="grass",h=0,variant=0,stock_void=true} end
  s.tiles[id]={terrain="grass",h=0,variant=0,owner="Builder",build="stock_rail",rail_tracks=bits,rail_ground=1}
  s.tiles[wet]={terrain="water",h=0,variant=0,water_class="sea"}
  return s,id,wet
end
local s,id=case(12)
local b=W.board(s).tile(8,8)
assert(b.slope==8 and b.foundation_slope==232 and b.foundation_base==0)
s.stock_rail_dispatch={life={claims={[id]=2}},runs={}}
assert(W.visit(s,8,9)==0 and s.tiles[id].rail_tracks==12)
s.stock_rail_dispatch.life.claims[id]=nil
s.stock_rail_dispatch.runs[1]={consist={parts={{tile=id}}}}
assert(W.visit(s,8,9)==0 and s.tiles[id].rail_tracks==12)
s.stock_rail_dispatch.runs[1]=nil
assert(W.visit(s,8,9)==1)
assert(s.tiles[id].rail_tracks==4 and s.tiles[id].rail_ground==13 and s.tiles[id].owner=="Builder")
assert(View.tile(s.tiles[id]).rail_ground==13)
assert(Water.at(Net.board(s),id)==T.trackdirs(8),"Sail along the lower stock curve only")
local south,east=Sim.id(8,9),Sim.id(9,8)
s.tiles[east]={terrain="water",h=0,variant=0,water_class="sea"}
local board=Net.board(s)
local Y=load("openttd/ship_yapf")(T,Water,load("openttd/yapf_road_search"))
local M=load("openttd/ship_motion")(T,Water)
local boat=assert(M.new(board,south,9,{acceleration=256,max_speed=256}))
local dest=assert(Y.destination(board,boat,{kind="tile",tile=east}))
local ok,last=Y.find(board,boat,south,T.trackdirbit(9),dest)
assert(ok,"The lower shore rail must connect both legs of the water bend")
local trace=Y.trace(board,boat,dest,last)
assert(#trace==3 and trace[2].tile==id and trace[2].td==11 and M.set_path(boat,trace))
local entered=false
for _=1,70 do
  local event=M.step(board,boat)
  assert(event~="reverse")
  if boat.tile==id then entered=true;assert(boat.track==8 and boat.z==0) end
  if boat.tile==east then break end
end
assert(entered and boat.tile==east,"Physical ship must sail through the stock lower rail half")
local saved=assert(Codec.decode(Codec.encode(s)))
assert(saved.tiles[id].rail_ground==13 and Water.at(Net.board(saved),id)==T.trackdirs(8))
s,id=case(8)
assert(W.visit(s,8,9)==1)
assert(not s.tiles[id].rail_tracks and s.tiles[id].coastal_water and s.tiles[id].terrain=="water" and not s.tiles[id].owner)
s,id=case(4)
assert(W.visit(s,8,9)==1 and s.tiles[id].rail_tracks==4 and s.tiles[id].rail_ground==13)
print("PASS coastal rail: tide removes only free lower tracks, retains upper ownership, allows lower navigation, and survives checkpoint")
