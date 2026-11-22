local root="mods/luanttd_core/openttd/"
local function m(n) return dofile(root..n..".lua") end
local P,R,Income=m("passengers"),m("station_rating"),m("income")
local Cat=m("station_catchment")(P,R)
local Coal=m("coal_industry")(P,R,Cat,Income)
local Timber=m("timber_industry")(P,Cat,R,Income,Coal,m("town_goods"))
local Factory=m("industry_worldgen")
local Legacy,Gen=Factory(Coal),Factory(Coal,Timber)
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local world={width=64,height=64,freeform=true,
  towns={{id=1,x=20,z=20},{id=2,x=40,z=32},{id=3,x=47,z=47}}}
local low={kind="clear",base=0,slope=0}
function world.tile() return low end
assert(Legacy.specs[2]==nil and Legacy.specs[3]==nil)
eq(Gen.specs[2].picture,"sawmill_0");eq(Gen.specs[3].picture,"forest_0")
for id=0,3 do
  local p,force=Gen.probability(world,id,{})
  eq(p,id==0 and 8 or 5);eq(force,true)
  local q,editor=Gen.probability(world,id,{editor=true})
  eq(q,p);eq(editor,false)
end
assert(Gen.forest_site("temperate",0))
assert(not Gen.forest_site("arctic",12,11) and Gen.forest_site("arctic",13,11))
assert(not Gen.forest_site("arctic"))
assert(not Gen.quote(world,3,24,24,0,{landscape="arctic"}))
local flat=assert(Gen.quote(world,3,30,35,0,{}))
eq(flat.level,0);eq(#flat.cells,18)
eq(flat.cells[18].offset_x,2);eq(flat.cells[18].offset_z,4)
eq(flat.cells[18].gfx,16)
local function reject(err,id,x,z,variant,others)
  local p,e=Gen.quote(world,id,x,z,variant,{},others)
  assert(not p);eq(e,err)
end
reject("INDUSTRY_LAYOUT_UNPORTED",2,20,20,1)
reject("INDUSTRY_LAYOUT_UNPORTED",3,20,20,1)
reject("INDUSTRY_TOO_CLOSE",3,30,35,0,{{type=14,x=44,z=49,town=3}})
assert(Gen.quote(world,3,30,35,0,{},{{type=14,x=45,z=50,town=3}}))
reject("INDUSTRY_TOO_CLOSE",2,44,49,0,{{type=3,x=30,z=35,town=1}})
assert(Gen.quote(world,2,45,50,0,{},{{type=3,x=30,z=35,town=1}}))
reject("ONLY_ONE_ALLOWED_PER_TOWN",3,21,21,0,{{type=3,x=20,z=20,town=1}})

local draws={}
local function push(...)
  for _,v in ipairs{...} do draws[#draws+1]=v end
end
local function candidate(x,z,seed,layout)
  push(x+64*z,seed,0x20000+seed,layout or 0)
end
local function accepted(n,colour,seed)
  push(0x120+colour)
  for i=1,n do push(seed+i) end
end
candidate(19,17,11,4294967295) -- legal stock variant 1, unported native asset
candidate(20,17,12);accepted(8,3,100)
candidate(34,31,21) -- within inclusive 14 corners of sawmill
candidate(35,32,22);accepted(18,6,130)
push(4294967295) -- weighted extra forest across the two enabled types
candidate(47,47,23);accepted(18,8,180)
local at=0
local function rng()
  at=at+1
  return assert(draws[at],"Unexpected random draw "..at)
end
local actual=Gen.generate(world,{density=6,custom_count=3,enabled={[2]=true,[3]=true},
  multiple_per_town=true,random=rng,commit=function() return true end})
eq(at,#draws);eq(at,68)
eq(actual.attempted,5);eq(actual.target,3);eq(actual.forced,2);eq(actual.shortfall,0)
eq(actual.choices[1].type,2);assert(actual.choices[1].forced)
eq(actual.choices[2].type,3);assert(actual.choices[2].forced)
eq(actual.choices[3].type,3);assert(not actual.choices[3].forced)
eq(actual.failures.INDUSTRY_LAYOUT_UNPORTED,1);eq(actual.failures.INDUSTRY_TOO_CLOSE,1)
local mill=Gen.record(actual.placed[1],9,{year=1950})
eq(mill.kind,"sawmill");eq(mill.accepted.cargo,"wood");eq(mill.produced.cargo,"goods")
eq(mill.produced.rate,0);eq(#mill.tiles,8);eq(mill.random_colour,3)
eq(mill.tiles[8].random_bits,108);eq(mill.selected_layout,1)
local forest=Gen.record(actual.placed[2],10,{year=1950})
eq(forest.kind,"forest");eq(forest.produced.cargo,"wood");eq(forest.produced.rate,13)
eq(forest.produced.last.production,104);eq(forest.random_colour,6);eq(forest.random,22)
eq(#forest.tiles,18);eq(forest.tiles[18].random_bits,148)
local tile=forest.tiles[18]
eq(tile.stage,2);eq(tile.construction_counter,3);assert(not tile.completed)
Timber.tile_loop(forest,tile,{},function() error("Worldgen construction does not move cargo") end)
eq(tile.stage,3);assert(tile.completed)

-- All sixteen slots are randomized under smooth economy, even though
-- the secondary industry starts at rate zero.
for _,p in ipairs({actual.placed[1],actual.placed[2]}) do
  local n=0
  Gen.initialize(p,303,404,function() n=n+1;return n==1 and 4294967295 or n end,{original=false})
  local v=Gen.record(p,10,{original=false})
  eq(n,16+1+#p.cells)
  eq(v.produced.rate,p.kind=="forest" and 19 or 0)
  eq(v.tiles[#p.cells].random_bits,n)
end
print("PASS optional source Sawmill and Forest: exclusions, layout draw, initialization, rates and lifecycle")
