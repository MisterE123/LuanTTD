local m="mods/luanttd_core/"
local function load(s) return dofile(m..s..".lua") end
local Sim,T,Tree=load("sim"),load("openttd/terrain"),load("openttd/tree_worldgen")
local adapter=load("tree_lifecycle_world")(Sim,T,load("openttd/tree_lifecycle_temperate")(Tree))
local save,view=load("packed_campaign"),load("campaign_terrain_projection")
local s=Sim.new(1751)
s.stock_generated_profile={}
s.corner_grid=T.new(Sim.W,Sim.H)
s.sites,s.stock_farm_fields={},{}
local name="Clear meadow"
Sim.company(s,name).cash=100000
local id=assert(Sim.id(8,8))
s.tiles[id]={terrain="grass",h=0,variant=1,build="road",road_bits=10,owner=name}
local _,base=T.tile(s.corner_grid,8,8)
local quote=assert(Sim.clear_area(s,name,id,id,false,false))
assert(quote.passed==1 and s.tiles[id].build=="road" and not s.tiles[id].stock_clear_density)
local done=assert(Sim.clear_area(s,name,id,id,false,true))
assert(done.cost==quote.cost and done.dirty[1]==id and not s.tiles[id].build and s.tiles[id].stock_clear_density==0)
assert(select(2,T.tile(s.corner_grid,8,8))==base)
s.changed=nil
local function accidental_rng() error("grass growth must not consume RNG") end
for visit=1,24 do
  -- Launch on arbitrary tile phase and simulate a save mid-stage.
  if visit==5 then s=assert(save.decode(save.encode(s))) end
  adapter.visit(s,8,8,183+visit*256,accidental_rng)
  local expected=visit<24 and math.floor(visit/8) or nil
  assert(s.tiles[id].stock_clear_density==expected)
  assert(view.tile(s.tiles[id]).stock_clear_density==expected,visit)
  if visit%8==0 then assert(s.changed and s.changed[1]==id);s.changed=nil
  else assert(not s.changed) end
end
local healthy=assert(Sim.clear_area(s,name,id,id,false,true))
assert(healthy.cost==20 and healthy.dirty[1]==id and s.tiles[id].stock_clear_density==0)
local before=Sim.company(s,name).cash
local again,why=Sim.clear_area(s,name,id,id,false,true)
assert((not again or #again.dirty==0) and Sim.company(s,name).cash==before,why)
local farm=assert(Sim.id(10,8))
s.tiles[farm]={terrain="grass",h=0,variant=0}
s.stock_farm_fields[farm]={field_type=3}
local f=assert(Sim.clear_area(s,name,farm,farm,false,true))
assert(f.cost==500 and not s.stock_farm_fields[farm] and s.tiles[farm].stock_clear_density==0)
print("PASS stock demolished roads, natural ground and fields start bare and regrow after exactly 24 visits; saves and projections match")
