-- RC1 water subtype integration: generation, checkpoint, worker copy,
-- YAPF status, and actual player/flood terrain transitions.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local Sim,T,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local TG=m("openttd/terragenesis")(Slope)
local Clear=m("openttd/terragenesis_clear_rc1")
local Packed,P=m("packed_campaign"),m("campaign_terrain_projection")
local Profile=m("generated_campaign")
local Track=m("openttd/rail_track")
local Water=m("openttd/ship_follow")(Track)
local Flood=m("openttd/water_flood")
local Board=m("ship_network")(Sim,T,Water,{})
local Rivers=m("openttd/river_worldgen")(Slope)
local start={width=128,depth=128,seed=1751,terrain_type=1,quantity_sea_lakes=0,tgen_smoothness=1,
  freeform_edges=true,water_borders=15,variety=0,rng_state=TG.startup_rng(1751)}
local Gen={describe=Clear.describe}
function Gen.generate(options)
  local base,stats=Rivers.generate(TG.generate(options),TG.next_random,
    {terrain=T,original=false,amount_of_rivers=2,min_river_length=16})
  return Clear.generate(base,TG.next_random),stats
end
local s=Profile.landscape(Sim,T,Gen,start)
local restored=assert(Packed.decode(Packed.encode(s)))
local board=Board.board(s)
local wet,shore,river=0,0,0
for id,t in ipairs(s.tiles) do
  local saved=restored.tiles[id]
  assert(saved.stock_water_rocks==t.stock_water_rocks and saved.stock_river_bits==t.stock_river_bits)
  assert(P.matches_tile(t,P.tile(saved)))
  if t.stock_water_rocks then
    assert(t.terrain=="water" and t.water_class=="sea" and not t.stock_void)
    assert(P.tile(t).stock_water_rocks)
    assert(Water.at(board,id)==0 and not board.tile(id).is_water_tile)
    if t.coastal_water then shore=shore+1 else wet=wet+1 end
  elseif t.water_class=="river" then
    assert(t.stock_river_bits and board.tile(id).is_water_tile)
    river=river+1
  end
end
assert(wet>0 and shore>0 and river>0,("%d wet / %d shore / %d river"):format(wet,shore,river))

local world={tiles={},corner_grid=T.new(Sim.W,Sim.H,function(x,z)
  if z==8 and (x==8 or x==9) then return 1 end
  return 0
end,{freeform_edges=true})}
for i=1,Sim.W*Sim.H do world.tiles[i]={terrain="grass",h=0,variant=0} end
local apply=m("water_flood_world")(Sim,T,Flood)
local wet_id=Sim.id(8,9)
local rocky_id=Sim.id(8,8)
local a,b=world.tiles[wet_id],world.tiles[rocky_id]
a.terrain,a.water_class="water","sea"
b.stock_clear_ground=2
assert(apply.board(world).tile(8,8).slope==9)
assert(apply.visit(world,8,9)>0)
assert(b.stock_water_rocks and b.coastal_water and not b.stock_clear_ground)
assert(apply.clear_quote(world,"A",rocky_id)==40)
-- Slope with two raised corners is a DryOut coast; remove the sea source.
a.terrain,a.water_class="grass",nil
assert(apply.visit(world,8,8)==1)
assert(b.terrain=="grass" and b.stock_clear_ground==2 and not b.stock_water_rocks)
-- Explicitly clearing a rocky coast does not retain an inland rock tile.
b.terrain,b.water_class,b.coastal_water,b.stock_water_rocks="water","sea",true,true
apply.clear_apply(world,rocky_id)
assert(b.terrain=="grass" and not b.stock_clear_ground and not b.stock_water_rocks)
print(("PASS RC1 rocky water tiles: %d wet, %d coast, %d untouched river, packed/projected and exact transitions"):format(wet,shore,river))
