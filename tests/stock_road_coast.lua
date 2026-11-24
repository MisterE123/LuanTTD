-- SPDX-License-Identifier: GPL-2.0-only
-- 16.0-RC1 CmdBuildRoad invokes LandscapeClear with Auto|NoWater.
-- ClearTile_Water checks NoWater on clear water, never on coastal slopes.
local mod="mods/luanttd_core/"
local function load(name) return dofile(mod..name..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local owner="Coastal Roads"
local function fixture()
  local w=Sim.new(8711)
  w.sites,w.stations,w.fleet={},{},{}
  w.road_economy,w.road_stock_house_supply=true,true
  w.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x>12 and 1 or 0 end,{freeform_edges=true})
  for id in ipairs(w.tiles) do
    local x,z=Sim.xy(id)
    local _,h=Terrain.tile(w.corner_grid,x,z)
    w.tiles[id]={terrain=x<=12 and "water" or "grass",h=h,variant=1,
      water_class=x<=12 and "sea" or nil,coastal_water=x==12 or nil}
  end
  return w,Sim.company(w,owner)
end
local function bridge_error(msg)
  assert(type(msg)=="string" and msg:find("bridge over open water",1,true),tostring(msg))
end
do
  local w,c=fixture()
  local start,goal=Sim.id(12,8),Sim.id(15,13)
  local route=load("campaign_road_construction")(Sim,w)
  local request={tool="bend",first=start,last=goal}
  local q=assert(route.quote(owner,request))
  local cash,rev=c.cash,w.topology
  assert(w.tiles[start].coastal_water and w.tiles[start].build==nil and w.topology==rev,
    "preview must not clear or build a tile")
  local proposal=assert(Sim.autoroad_bend_plan(w,owner,start,goal))
  local shore=0
  for _,entry in ipairs(proposal.changes) do
    if entry.clear_road_coast then
      assert(entry.road_site_cost==40,"two raised corners are charged ClearRough, not ClearWater")
      shore=shore+1
    end
  end
  assert(shore==6 and q.cost==proposal.cost)
  local ok,note,ids=route.commit(owner,request,q,true)
  assert(ok,note)
  assert(c.cash==cash-q.cost and w.topology==rev+1 and #ids==#q.tiles)
  assert(Terrain.corner(w.corner_grid,12,8)==0 and Terrain.corner(w.corner_grid,13,8)==1)
  for z=8,13 do
    local t=w.tiles[Sim.id(12,z)]
    assert(t.build=="road" and t.terrain=="grass" and not t.coastal_water and not t.water_class)
    assert(w.tiles[Sim.id(11,z)].terrain=="water")
  end
end
do
  local w,c=fixture()
  local shore,sea=Sim.id(12,9),Sim.id(11,9)
  local route=load("campaign_road_construction")(Sim,w)
  local intent={tool="drag",first=shore,last=Sim.id(12,11),axis=1,start_half=false,end_half=true}
  local q=assert(route.quote(owner,intent))
  local t=w.tiles[shore]
  local cash=c.cash
  t.coastal_water=nil
  assert(not route.commit(owner,intent,q,true))
  assert(t.terrain=="water" and not t.build and c.cash==cash)
  t.coastal_water=true
  local ok,note=route.commit(owner,intent,q,true)
  assert(ok,note)
  for _,kind in ipairs({"sea","river","canal"}) do
    local water=w.tiles[sea]
    water.water_class=kind
    if kind=="canal" then water.build,water.stock_canal="canal",true end
    local balance=c.cash
    local denied,msg=Sim.autoroad_bend_build(w,owner,sea,Sim.id(14,6))
    assert(not denied and c.cash==balance and water.terrain=="water")
    bridge_error(msg)
  end
end
do
  local w,c=fixture()
  local shore=Sim.id(12,8)
  local cash=c.cash
  w.stock_coal_ship_run={vehicle={tile=shore,path={}}}
  local ok,why=Sim.autoroad_bend_build(w,owner,shore,Sim.id(15,13))
  assert(not ok and why:find("vessel",1,true) and w.tiles[shore].coastal_water and c.cash==cash)
end
do
  local w,c=fixture()
  local x,z=12,8
  local shore=Sim.id(x,z)
  w.corner_grid=Terrain.new(Sim.W,Sim.H,function(a,b) return a==x and b==z and 1 or 0 end)
  local q=assert(Sim.autoroad_plan(w,owner,shore,shore,0,false,false))
  assert(q.changes[1].road_site_cost==10000,"an isolated raised corner is charged ClearWater")
  local cash=c.cash
  local ok,note=Sim.apply_road_construction(w,owner,q)
  assert(ok,note)
  assert(c.cash==cash-q.cost and Terrain.corner(w.corner_grid,x,z)==1)
  assert(w.tiles[shore].build=="road" and not w.tiles[shore].coastal_water)
end
print("PASS pinned coastal-road rule: two-way bend and straight previews, atomic failed stale quotes, exact clearance price, real ocean/river/canal and vessel rejection")
