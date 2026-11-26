local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T,Codec=m("sim"),m("openttd/terrain"),m("packed_campaign")
local s=Sim.new(1751)
Sim.W,Sim.H=64,128
s.tiles={}
for i=1,64*128 do s.tiles[i]={h=1,terrain="grass",variant=1} end
s.corner_grid=T.new(Sim.W,Sim.H,function()return 1 end,{freeform_edges=true})
s.stock_generated_profile={width=64,depth=128}
local W=assert(Sim.mount_farm_world(s,T,true))
local P=m("openttd/farm_factory_fields")(m("openttd/coal_industry")())
local function id(x,z) return Sim.id(x+1,z+1) end
local b=W.field_board(s)
assert(b.width==64 and b.height==128 and b.freeform)
for _,p in ipairs({{0,9},{9,0},{63,9},{9,127},{64,9},{9,128}}) do assert(b.tile(p[1],p[2]).kind=="void") end
local rough=id(8,8);s.tiles[rough].stock_clear_ground=1
local rock=id(9,8);s.tiles[rock].stock_clear_ground=2
s.tiles[id(10,8)].wood={ground=1}
s.tiles[id(11,8)].wood={ground=3}
assert(not P.suitable(b.tile(8,8),false,false) and P.suitable(b.tile(8,8),true,true))
assert(P.suitable(b.tile(9,8),false,false))
assert(not P.suitable(b.tile(10,8),false,false) and P.suitable(b.tile(10,8),true,true))
assert(not P.suitable(b.tile(11,8),true,true))
b.make_field(8,8,8,123,7)
assert(s.tiles[rough].stock_clear_ground==nil and b.tile(8,8).ground=="field")
b.visit(8,8,1,false)
assert(not W.field(s,rough) and s.stock_farm_grass[rough]==0)
local restored=assert(Codec.decode(Codec.encode(s)))
assert(restored.stock_farm_grass[rough]==0)
b=W.field_board(restored)
assert(b.landscape_fields==restored.stock_farm_fields and b.landscape_regrowth==restored.stock_farm_grass)
assert(b.landscape_regrowth[rough]==0, "zero is a queued regrowth visit")
for i=1,7 do b.visit(8,8,1+i,false,rough);assert(restored.stock_farm_grass[rough]==i) end
b.visit(8,8,9,false)
assert(restored.stock_farm_grass[rough]==nil and b.tile(8,8).ground=="grass")
-- RC1 still exposes the surface as an ordinary clear tile no matter
-- which independent overhead/buried layer shares these coordinates.
for i,layer in ipairs({"bridge_above","rail_bridge_above","aqueduct_above","tunnel_below","rail_tunnel_below"}) do
  local x,z=12+i,9
  local at=id(x,z)
  restored[layer]={[at]=i}
  assert(b.tile(x,z).ground=="grass")
  b.make_field(x,z,4,123,7)
  local field=assert(W.field(restored,at))
  assert(b.landscape_fields[at]==field,"same-day planting is visible to the bound dispatcher")
  b.visit(x,z,1,false,at)
  assert(W.field(restored,at)==field and field.variant==5 and field.fences[0]==3)
  restored.tiles[at].build="road"
  b.visit(x,z,2,false)
  assert(not W.field(restored,at) and not b.landscape_fields[at])
end
local p=m("generated_campaign")
restored.stock_generated_profile.object_rng={10,20}
restored.stock_farm_fields[rough]={kind="clear",ground="field",variant=2,counter=0,fences={},base=1,slope=0}
local witnessed=false
p.forests(Sim,T,restored,{},{
  generate=function(board)
    assert(board.tile(9,9).ground==3,"Forest candidate pass must see stock farmland, not spare grass")
    witnessed=true
    return {each=function()end,rng_after={10,20},stats={}}
  end
},2)
assert(witnessed)
print("PASS native RC1 board edges, rough/trees planting, forest exclusion and grass regrowth across checkpoint")
