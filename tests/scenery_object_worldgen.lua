local O=dofile("mods/luanttd_core/openttd/scenery_object_worldgen.lua")
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local w,h=64,64
local function idx(x,z) return (z-1)*w+x-1 end
local towns={{id=258,x=28,z=35},{id=7,x=36,z=35}}
local function fixture(read)
  return {width=w,depth=h,freeform=true,tile=read,towns=towns}
end
local function prng(draws,fallback)
  return function(s)
    s[1]=s[1]+1
    local r=draws[s[1]] or fallback
    assert(r~=nil,"too many draws")
    s[2]=r
    return r
  end
end
local high={class=0,slope=0,height=5}
local function high_cells(x,z)
  if x==1 or z==1 or x==w or z==h then return {class=7} end
  return high
end
local start={0,0}
local date=712204
local test=O.generate(fixture(high_cells),start,prng({idx(32,35),0xABCDEF21,0x123456F5}),{date=date})
eq(test.stats.attempts.transmitter,1);eq(test.stats.targets.lighthouse,0)
eq(test.rng_after[1],3);eq(test.rng_after[2],0x123456F5)
eq(start[1],0);eq(start[2],0)
local tx=assert(test.object(32,35))
eq(tx.type,O.transmitter);eq(tx.class,O.tile_class);eq(tx.colour,1);eq(tx.random_bits,245)
eq(tx.town,7);eq(tx.date,date);eq(tx.view,0);eq(tx.height_levels,10)
tx.colour=999;eq(test.object(32,35).colour,1)
assert(not test.object(65,35))

-- A transmitter exactly on the diagonal edge of the source 9x9 square
-- qualifies for the circular exclusion. The next position is legal.
local function high_with_tower(x,z)
  if x==36 and z==39 then return {class=10,object_type=O.transmitter,slope=0,height=5} end
  return high_cells(x,z)
end
test=O.generate(fixture(high_with_tower),start,prng({idx(32,35),idx(44,45),1,2}))
eq(test.stats.attempts.transmitter,2)
assert(not test.object(32,35) and test.object(44,45))
eq(test.rng_after[1],4)

-- The source first-column CircularTileSearch begins from a wrapped
-- linear tile, unlike a simple coordinate square. A far-edge transmitter
-- therefore blocks this one classic-edge candidate.
local function classic_edge(x,z)
  if x==w or z==h then return {class=7} end
  if x==63 and z==16 then return {class=10,object_type=O.transmitter,slope=0,height=5} end
  return high
end
local edge=fixture(classic_edge)
edge.freeform=false
test=O.generate(edge,start,prng({idx(1,18),idx(40,45),3,4}),{capacity=1})
eq(test.stats.attempts.transmitter,2)
assert(not test.object(1,18) and test.object(40,45))
-- Low flat land inland from sea; each attempted site from right to
-- left is road, bridged clear or graded clear before the real anchor.
local function shore(x,z,cut)
  if x==1 or x==w or z==1 or z==h then return {class=7} end
  if x==2 or x==63 or z==2 or z==63 then return {class=6,slope=0,height=0} end
  if z==33 then
    if x==62 then return {class=cut and 7 or 2}
    elseif x==61 then return {class=0,slope=0,height=2,bridge_above=true}
    elseif x==60 then return {class=0,slope=3,height=1}
    elseif x==59 then return {class=0,slope=0,height=2} end
  end
  return {class=0,slope=0,height=1}
end
local draws={}
for i=1,63 do draws[i]=0 end -- all high-ground transmitter trials fail
draws[64],draws[65],draws[66]=32,126,217
test=O.generate(fixture(shore),start,prng(draws,32),{capacity=1})
eq(test.stats.attempts.transmitter,63);eq(test.stats.shortfall.transmitter,1)
eq(test.stats.placed.lighthouse,1);eq(test.rng_after[1],66)
local lh=assert(test.object(59,33))
eq(lh.type,O.lighthouse);eq(lh.colour,14);eq(lh.random_bits,217)
eq(lh.height,2);eq(lh.height_levels,8)
assert(not test.object(62,33) and not test.object(61,33) and not test.object(60,33))
test=O.generate(fixture(function(x,z)return shore(x,z,true)end),start,prng({},32))
eq(test.stats.attempts.transmitter,63);eq(test.stats.attempts.lighthouse,63)
eq(test.stats.placed.lighthouse,0);eq(test.stats.random_draws,126)
test=O.generate(fixture(shore),start,prng({}),{date=0})
eq(test.stats.targets.transmitter,0);eq(test.stats.targets.lighthouse,0);eq(test.stats.random_draws,0)
test=O.generate(fixture(shore),start,prng({}),{capacity=0})
eq(test.stats.targets.transmitter,1);eq(test.stats.random_draws,0)
assert(not pcall(O.generate,fixture(shore),start,prng({}),{landscape="arctic"}))
print("PASS stock scenery object quotas, circular separation, sea scan, protection, draw ordering and immutable records")
