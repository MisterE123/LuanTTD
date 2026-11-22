local p="mods/bayline/openttd/"
local F=dofile(p.."tree_worldgen.lua")
local Slope=dofile(p.."slope.lua")
local G=dofile(p.."terragenesis.lua")(Slope)
local Clear=dofile(p.."terragenesis_clear.lua")
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end

-- Fail closed on protected, occupied, unsuitable and totally unknown terrain.
assert(not F.can_plant({class=6,coast=true},true))
assert(not F.can_plant({class=6,coast=true,slope=1},true))
assert(not F.can_plant({class=6,coast=false,slope=0},true))
assert(F.can_plant({class=6,coast=true,slope=3},true))
assert(not F.can_plant({class=6,coast=true,slope=3,bridge_above=true},true))
assert(not F.can_plant({class=0,ground=3},true))
assert(not F.can_plant({class=0,ground=4,raw_ground=2},true))
assert(not F.can_plant({class=0,ground=0,bridge_above=true},true))
assert(F.can_plant({class=0,ground=1},true))
assert(not F.can_plant({class=0,ground=5},false))
assert(F.can_plant({class=0,ground=5},true))
for _,class in ipairs{1,2,3,4,5,7,8,9,10} do
  assert(not F.can_plant({class=class,ground=0},true))
end

local base=Clear.generate(G.generate({
  width=64,depth=64,seed=1751,rng_state=G.startup_rng(1751),terrain_type=3,
}),G.next_random)
local function tile(x,z)
  local c,w,g=Clear.describe(base.tile(x,z))
  local mask,h=Slope.classify(base.corner(x,z),base.corner(x+1,z),base.corner(x,z+1),base.corner(x+1,z+1))
  return {class=c,ground=g,slope=mask,height=h,coast=w==2}
end
local board={width=64,depth=64,freeform=true,tile=tile}
local none=F.generate(board,base.rng_after,G.next_random,{tree_placer=0})
eq(none.stats.random_draws,0);eq(none.stats.tiles,0)
eq(none.rng_after[1],base.rng_after[1]);eq(none.rng_after[2],base.rng_after[2])
local orig=F.generate(board,base.rng_after,G.next_random,{tree_placer=1})
eq(orig.stats.groups,2);eq(orig.stats.base_attempts,378);eq(orig.stats.same_height_attempts,0)
eq(orig.stats.tiles,430);eq(orig.stats.shore_tiles,20)
local improved=F.generate(board,base.rng_after,G.next_random)
eq(improved.stats.groups,2);eq(improved.stats.base_attempts,126);eq(improved.stats.same_height_attempts,822)
eq(improved.stats.tiles,553);eq(improved.stats.total_trees,1380);eq(improved.stats.shore_tiles,30)
eq(improved.stats.random_draws,2951);eq(improved.rng_after[1],399317553);eq(improved.rng_after[2],1658045267)
local seen={}
improved.each(function(x,z,b)
  eq(b.class,4)
  local i=(z-1)*64+x
  assert(not seen[i] and F.can_plant(tile(x,z),true));seen[i]=true
  local clone=improved.tree(x,z)
  eq(b.type,clone.type)
  b.type=999
  eq(improved.tree(x,z).type,clone.type)
end)
eq(base.rng_after[1],3351320871);eq(base.rng_after[2],3998776434)
assert(not improved.tree(65,1) and not improved.tree(1,1))
print("PASS forest placement is seeded, typed, unique, protected and immutable")
