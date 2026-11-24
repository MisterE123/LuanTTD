local base="mods/luanttd_core/openttd/"
local G=dofile(base.."tree_worldgen.lua")
local Terrain=dofile(base.."terrain.lua")
local Area=dofile(base.."landscaping.lua")(Terrain)
local K=dofile(base.."tree_plant_temperate.lua")(G,Area)
local grid=Terrain.new(64,64,function()return 1 end)
local tiles={
  [1]={id=1,class=4,count=4},[2]={id=2,class=4,count=3},[3]={id=3,class=0,ground=3,density=3},
  [4]={id=4,class=6,coast=true,slope=1},[5]={id=5,class=6,coast=true,slope=3,rocky=true},
  [6]={id=6,class=6,coast=true,slope=3},[7]={id=7,class=0,ground=1,density=3},
  [8]={id=8,class=0,ground=0,density=2},[9]={id=9,class=0,ground=0,density=3,bridge_above=true},
}
local calls=0
local opts={tile=function(x,z) assert(z==1);return tiles[x] end,species=255,
 clear=function(t)
   calls=calls+1
   return t.class==6 and 40 or 500,{class=0,ground=0,density=0}
 end}
local plan=assert(K.quote(grid,1,1,9,1,false,opts))
assert(calls==2 and #plan.items==6 and plan.cost==680)
assert(plan.items[1].id==2 and plan.items[1].add and not plan.items[1].rate_town)
assert(plan.items[2].id==3 and plan.items[2].ground==G.ground.grass and plan.items[2].density==0)
assert(plan.items[3].id==5 and plan.items[3].ground==G.ground.grass and plan.items[3].density==0)
assert(plan.items[4].id==6 and plan.items[4].ground==G.ground.shore and plan.items[4].density==3)
assert(plan.items[5].id==7 and plan.items[5].ground==G.ground.rough)
assert(plan.items[6].id==8 and plan.items[6].density==2)
assert(K.new_tree(plan.items[4],function()return 4294967295 end).type==11)
opts.species=0
local plain=assert(K.quote(grid,7,1,8,1,false,opts))
assert(K.new_tree(plain.items[1],function()error("Explicit planting used RNG") end).type==0)
opts.quota=2*K.unit+63
plan=assert(K.quote(grid,1,1,9,1,false,opts))
assert(#plan.items==1 and plan.cost==40 and plan.quota_after==K.unit+63)
opts.quota=K.unit
local nope,why=K.quote(grid,2,1,8,1,false,opts)
assert(not nope and why=="TREE_PLANT_LIMIT_REACHED")
opts.quota=nil;opts.cash=679
local needed
nope,why,needed=K.quote(grid,1,1,9,1,false,opts)
assert(not nope and why=="NOT_ENOUGH_MONEY" and needed==680)
opts.cash=nil;opts.clear=function() return nil,"DISALLOWED_LAND_CLEAR" end
nope,why=K.quote(grid,1,1,9,1,false,opts)
assert(not nope and why=="DISALLOWED_LAND_CLEAR")
assert(K.rating(218)==220 and K.rating(190)==197 and K.rating(350)==350)
assert(K.replenish(K.unit,1)==65*K.unit and K.replenish(nil,1)==K.burst*K.unit)
print("PASS OpenTTD plant trees command: cost, limits, random draws, clear fields/rocks, shore, town ratings")
