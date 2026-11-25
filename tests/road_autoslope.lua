local src="mods/luanttd_core/openttd/"
local function m(n) return dofile(src..n..".lua") end
local R=m("road_autoslope")(m("road_slope"),m("slope"),m("road_stop_build"))
assert(R.normal(10,5,0,0,1)==250)
assert(R.normal(10,0,1,5,0)==250)
assert(R.normal(10,0,1,5,1)==nil)
assert(R.normal(10,0,1,3,0)==nil)
assert(R.normal(10,0,1,5,0,{autoslope=false})==nil)
assert(R.normal(10,0,1,5,0,{build_on_slopes=false})==nil)
assert(R.normal(10,0,1,5,0,{foundation_price=418})==418)
assert(R.terminal(2,false,0,1,1,0)==250)
assert(not R.terminal(2,true,0,1,1,0))
assert(not R.terminal(0,false,0,1,1,0))
assert(R.terminal(2,true,0,1,5,0)==250)
assert(R.terminal(2,true,5,0,0,1)==250)
assert(not R.terminal(2,true,5,0,0,2))
print("PASS stock road plane comparison and one/two entrance constraints")

local Sim=dofile("mods/luanttd_core/sim.lua")
local Terrain=m("terrain")
local player="Survey Company"
local x,z=8,9
local id=Sim.id(x,z)
local function scenario(part)
  local s=Sim.new(1751)
  for idx in pairs(s.tiles) do s.tiles[idx]={terrain="grass",h=1,variant=0} end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v)
    return u==x and v==z and 0 or 1
  end)
  part.h,part.terrain,part.variant=0,"grass",0
  s.tiles[id]=part
  return s
end
for _,part in ipairs({
  {build="road",owner="Another company",road_bits=10},
  {build="road",owner=player,road_bits=5,tram={kind="road",tram_bits=10}},
  {tram={kind="road",tram_bits=10,tram_owner=player}},
  {build="road_depot",owner=player,depot_dir=2,road_bits=2,road_terminal_level=1},
  {build="road_station",owner=player,station=1,road_bits=10,stop_axis=10,road_terminal_level=1},
  {build="road_station",owner=player,station=1,road_bits=2,stop_axis=2,road_terminal_level=1},
  {tram={kind="depot",dir=2,terminal_level=1,tram_bits=2,tram_owner=player}},
  {tram={kind="drive_stop",dir=0,terminal_level=1,tram_bits=10,tram_owner=player}},
}) do
  local s=scenario(part)
  local cash=Sim.company(s,player).cash
  local okay,price=Sim.landscape(s,player,"raise",x,z,nil,nil,false,true)
  assert(okay and price==500)
  assert(s.tiles[id]==part and Sim.company(s,player).cash==cash and Terrain.tile(s.corner_grid,x,z)==7)
  assert(Sim.landscape(s,player,"raise",x,z))
  assert(s.tiles[id]==part and Terrain.tile(s.corner_grid,x,z)==0 and Sim.company(s,player).cash==cash-500)
  -- Deliberately raise the *high* corner: raising the deck is not autoslope.
  assert(not Sim.landscape(s,player,"raise",x,z))
  assert(s.tiles[id]==part and Sim.company(s,player).cash==cash-500)
end
print("PASS deck-preserving landscape command across eight ordinary road/tram/terminal shapes")
