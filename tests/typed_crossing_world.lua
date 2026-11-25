local p="mods/luanttd_core/"
local function m(name) return dofile(p..name..".lua") end
local Sim,Terrain,Track=m("sim"),m("openttd/terrain"),m("openttd/rail_track")
local Crossing=m("openttd/level_crossing")(Track)
local World=m("level_crossing_world")(Sim,Terrain,Crossing,Track)
local types=m("openttd/rail_types")
local s=Sim.new(1751)
local owner="Wire Company"
Sim.company(s,owner)
local id=Sim.id(8,9)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 1 end)
s.level_crossing_enabled=true
local held=false
local ctx={vehicles_at=function()return {}end,reserved=function()return held end}
local function asphalt()
  s.tiles[id]={build="road",terrain="grass",owner=owner,road_bits=10}
  return s.tiles[id]
end
local function railway(type_)
  s.tiles[id]={build="stock_rail",terrain="grass",owner=owner,rail_tracks=2,rail_type=type_}
  return s.tiles[id]
end
for gauge=0,3 do
  assert(types.entry(gauge).no_crossings==false)
  s.stock_level_crossing_art=nil
  local t=asphalt()
  local request={kind="rail",track=1,railtype=gauge}
  if gauge~=0 then
    assert(not World.quote(s,owner,id,request,ctx))
    railway(gauge)
    assert(not World.quote(s,owner,id,{kind="road",pieces=10},ctx))
    t=asphalt()
    s.stock_level_crossing_art={[gauge]=true}
  end
  local q=assert(World.quote(s,owner,id,request,ctx))
  assert(q.price==({100,150,200,300})[gauge+1] and q.crossing.railtype==gauge)
  assert(World.commit(s,owner,q,ctx))
  assert(t.level_crossing.railtype==gauge and not t.rail_type and not t.rail_tracks)
  local board=World.rail_board(s,{tile=function()end},ctx)
  assert(board.tile(id).railtype==gauge and board.tile(id).trackbits==2)
  held=true
  assert(board.tile(id).reserved)
  assert(not World.rail_remove_quote(s,owner,id,ctx))
  held=false
  World.rail_remove_apply(s,assert(World.rail_remove_quote(s,owner,id,ctx)))
  assert(t.build=="road" and not t.level_crossing and t.road_bits==10)
  t=railway(gauge)
  assert(World.commit(s,owner,assert(World.quote(s,owner,id,{kind="road",pieces=10},ctx)),ctx))
  assert(t.level_crossing.railtype==gauge and not t.rail_type)
  World.road_remove_apply(s,assert(World.road_remove_quote(s,owner,id,10,ctx)))
  assert(t.build=="stock_rail" and t.rail_type==gauge and t.rail_tracks==2 and not t.level_crossing)
end
print("PASS RC1 typed crossing quote, live reservation, and both removal directions on every stock gauge")

local plan=m("crossing_gesture")
s.tiles[id]={terrain="grass",tram={kind="road",tram_bits=10,tramtype=1,tram_owner=owner}}
s.stock_level_crossing_art={[1]=true}
local c=assert(plan(Sim,s,id,1))
assert(c.railtype==1 and c.track==1)
assert(World.commit(s,owner,assert(World.quote(s,owner,id,c,ctx)),ctx))
assert(s.tiles[id].level_crossing.tramtype==1 and not s.tiles[id].level_crossing.roadtype)
print("PASS explicit crossing picker accepts pure tram without inventing pavement")
