-- RC1 BuildBridge has Auto + NoWater, but ClearTile_Water's Coast and
-- CoastRocks cases still clear. Trees with a shore underlay use TreeTypeProcs.
local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Slope,Track=load("sim"),load("openttd/terrain"),load("openttd/slope"),load("openttd/rail_track")
local Basic=load("openttd/road_bridge")(Slope)
local H=load("openttd/rail_height")(Track,Slope)
local Signals=load("openttd/rail_signals")(Track)
local Q=load("openttd/rail_construction")(Track,Signals,H)
local Site=load("openttd/rail_span_site")
local Rail=load("rail_span_world")(Sim,Terrain,H,load("openttd/rail_bridge")(Basic,Q,Site),
  load("openttd/rail_tunnel")(load("openttd/road_tunnel"),Q,Site,Track),Track)
local Aqua=load("ship_aqueduct_world")(Sim,Terrain,load("openttd/aqueduct")(Basic))
Sim.W,Sim.H=64,64
local function fresh()
  local s=Sim.new(1950)
  s.tiles,s.sites={},{}
  s.rail_span_enabled=true
  s.stock_generated_profile={width=64,depth=64}
  s.corner_grid=Terrain.new(64,64,function(x) return (x<=10 or x>=17) and 1 or 0 end,{freeform_edges=true})
  for z=1,64 do for x=1,64 do
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    local sea=x>=10 and x<=16
    s.tiles[Sim.id(x,z)]={terrain=sea and "water" or "grass",h=base,variant=1,
      water_class=sea and "sea" or nil,coastal_water=sea and slope~=0 or nil}
  end end
  return s
end
local function id(x) return Sim.id(x,22) end
local head,tail,mid=id(10),id(16),id(13)
local owner="Coast"
local function project(s,mode,dry)
  if mode=="road" then
    local ok,msg,plan=Sim.road_bridge(s,owner,head,tail,0,dry)
    if not ok then return nil,msg end
    return dry and plan or assert(s.stock_road_bridges[s.bridge_above[mid]])
  elseif mode=="rail" then
    local p,why=Rail.quote_bridge(s,owner,head,tail)
    if not p or dry then return p,why end
    assert(Rail.commit(s,owner,p));return p
  else
    if dry then return Aqua.quote(s,owner,head,tail) end
    return Aqua.build(s,owner,head,tail)
  end
end
for _,mode in ipairs({"road","rail","water"}) do
  local s=fresh()
  local c=Sim.company(s,owner);c.cash=250000
  local copy=table.concat(s.corner_grid.levels,",")
  local lo,hi,sea=s.tiles[head],s.tiles[tail],s.tiles[mid]
  assert(lo.coastal_water and hi.coastal_water and not sea.coastal_water)
  hi.stock_water_rocks=true
  assert(project(s,mode,true).site_cost==80) -- two inclined shore tiles, rough-clear base cost.
  lo.wood={class=4,count=3,ground=3,density=3,type=0,growth=3}
  local original=lo.wood
  local p=assert(project(s,mode,true))
  assert(p.site_cost==60+40 and #p.clears==2 and lo.wood==original and hi.stock_water_rocks)
  hi.coastal_water=nil -- ordinary water tile with no Coast flag may not clear.
  assert(not project(s,mode,true) and c.cash==250000 and lo.wood==original)
  hi.coastal_water=true
  s.ship_pilot={vehicle={tile=mid,path_index=2,path={{tile=mid},{tile=tail}}}} -- the normal vessel guard.
  assert(not project(s,mode,true) and c.cash==250000 and lo.wood==original)
  s.ship_pilot=nil
  local built=assert(project(s,mode,false))
  assert(built.price==p.price and c.cash==250000-p.price and not lo.wood and not hi.stock_water_rocks)
  assert(lo.terrain=="grass" and hi.terrain=="grass" and not lo.coastal_water and not hi.coastal_water)
  assert(lo.stock_clear_density==0 and hi.stock_clear_density==0 and sea.terrain=="water")
  assert(s.tiles[Sim.id(16,23)].coastal_water and table.concat(s.corner_grid.levels,",")==copy)
end
print("PASS RC1 shared coast and rocky-coast bridge ramps for road, rail and aqueduct; wooded coast pricing and vessel/NoWater guard")
