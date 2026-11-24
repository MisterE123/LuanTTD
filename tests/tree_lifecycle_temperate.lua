local base="mods/luanttd_core/openttd/"
local W=dofile(base.."tree_worldgen.lua")
local T=dofile(base.."tree_lifecycle_temperate.lua")(W)
local tree={class=4,type=7,ground=0,growth=3,density=2,count=1}
local function fail() error("Unexpected RNG/neighbor draw") end
local quiet=T.visit(tree,0,0,7*256,T.NO_GROWTH,fail,fail)
assert(quiet~=tree and quiet.density==3 and tree.density==2 and quiet.growth==3)
assert(T.visit(tree,1,0,2*256,T.SPREAD_ALL,fail,fail)==tree)
local function run(choice,d,target)
  local draws=0
  local out,event=T.visit(tree,0,0,15*256,T.SPREAD_ALL,function()
    draws=draws+1
    return draws==1 and choice or d*536870912
  end,function(direction) assert(direction==d);return target end)
  return out,event,draws
end
local next,event,n=run(0);assert(next.growth==4 and n==1 and not event)
next,event,n=run(1);assert(next.growth==0 and next.count==2 and n==1 and not event)
next,event,n=run(4);assert(next.growth==3 and n==1 and not event)
next,event,n=run(2,7,{class=6,coast=true,slope=3,rocky=true})
assert(not event and n==2 and next.density==3)
next,event,n=run(2,5,{class=6,coast=true,slope=3})
assert(event.kind=="plant" and event.direction==5 and event.tree.growth==0 and event.tree.count==1
  and event.tree.type==7 and event.tree.ground==3 and event.tree.density==3)
next,event,n=run(2,3,{class=0,ground=0,density=2})
assert(not event and n==2)
next,event,n=run(2,2,{class=0,ground=1,density=3})
assert(event.tree.ground==1 and not event.tree.water_class and n==2)
tree.growth,tree.count=6,2
next,event=T.visit(tree,0,0,15*256,T.SPREAD_ALL,fail,fail)
assert(next.count==1 and next.growth==3 and not event)
tree.count=1
next,event=T.visit(tree,0,0,15*256,T.SPREAD_ALL,fail,fail)
assert(not next and event.kind=="clear" and event.ground==0 and event.density==3)
next,event=T.visit(tree,0,0,15*256,T.NO_SPREAD,fail,fail)
assert(next.growth==0 and next.count==1 and not event)
for stage=0,5 do
  if stage~=3 then
    tree.growth=stage
    assert(T.visit(tree,0,0,15*256,T.SPREAD_ALL,fail,fail).growth==stage+1)
  end
end
assert(not W.can_plant({class=6,coast=true,rocky=true,slope=3},true))
assert(W.can_plant({class=6,coast=true,slope=3},false))
print("PASS Temperate source tree lifecycle: ground clock, seven stages, spread draws and rocky coast exclusion")
local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local Terrain=dofile(base.."terrain.lua")
local Adapter=dofile(mod.."tree_lifecycle_world.lua")(Sim,Terrain,T)
local s=Sim.new(23)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 1 end)
local function at(x,z,t) local id=Sim.id(x,z);s.tiles[id]=t;return t,id end
local mid=at(7,7,{terrain="hill",h=1,wood={class=4,type=7,ground=0,density=3,growth=3,count=1}})
local right=at(8,7,{terrain="hill",h=1,stock_clear_density=0})
local function planting_clock()
  local calls=0
  return function() calls=calls+1;return calls==1 and 2 or 5*536870912 end
end
local function due(x,z) return ((15-(11*(x-1)+9*(z-1)))%16)*256 end
assert(not Adapter.visit(s,7,7,due(7,7),planting_clock()) and not right.wood)
for i=0,2 do Adapter.visit(s,8,7,due(8,7)+i*2048,fail) end
assert(right.stock_clear_density==nil)
assert(Adapter.visit(s,7,7,due(7,7),planting_clock()).kind=="plant")
assert(right.wood.type==7 and right.wood.growth==0 and right.wood.count==1)
Adapter.visit(s,8,7,due(8,7),fail);assert(right.wood.growth==1 and mid.wood.growth==3)
local view=dofile(mod.."campaign_terrain_projection.lua").tile(right)
assert(view.wood.growth==1)
local packed=dofile(mod.."packed_campaign.lua")
local reload=assert(packed.decode(packed.encode(s)))
assert(reload.tiles[Sim.id(8,7)].wood.growth==1)
local preserve=at(7,8,{terrain="water",water_class="sea",coastal_water=true,h=1,
  wood={class=4,type=7,ground=3,density=3,growth=6,count=1}})
assert(Adapter.visit(s,7,8,due(7,8),fail).kind=="clear")
assert(not preserve.wood and preserve.coastal_water and preserve.water_class=="sea")
print("PASS native tree lifecycle adapter: immature clearance, actual neighbor planting, projected and packed stage, shore restoration")
