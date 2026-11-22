-- Geographic seed and actual stock placement quotes; never a substitute
-- mocked map for rules already mounted in live games.
local mod="mods/luanttd_core/"
local function load(p)return dofile(mod..p..".lua")end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Slope=load("openttd/slope")
local id=Sim.id
local function fresh()
  local s=Sim.new(1751)
  load("town_layout")(Sim,s)
  local fixed={}
  for i,t in ipairs(s.tiles) do
    if t.site or t.build or t.house then fixed[i]={t.site,t.build,t.house} end
  end
  local previous=load("terrain_preview")(Sim,Terrain,s)
  local g,stats=dofile("tests/coastal_corridor_fixture.lua")(Sim,Terrain,s,previous)
  s.corner_grid=g
  for i,q in pairs(fixed) do
    local t=s.tiles[i]
    assert(t.site==q[1] and t.build==q[2] and t.house==q[3] and t.terrain~="water")
    local x,z=Sim.xy(i)
    assert(Terrain.tile(g,x,z)==0,("Unlevel existing town/facility at %d,%d"):format(x,z))
  end
  return s,stats,previous
end
local s,stats,old=fresh()
assert(stats.name=="coastal test circuit" and stats.seed==1751 and s.corner_grid.revision==0)
assert(stats.land+stats.water==Sim.W*Sim.H and stats.water>=300 and stats.flat>=900 and stats.peak>=5)
assert(stats.shore>=100)
assert(s.sites[1].name=="Port Alder" and s.sites[2].name=="Mason Quay")
local terrain=function(i)
  local x,z=Sim.xy(i)
  return Terrain.tile(s.corner_grid,x,z)
end
local layout_changes=0
for i,level in ipairs(s.corner_grid.levels) do if old.levels[i]~=level then layout_changes=layout_changes+1 end end
assert(layout_changes>=1200)
local lake_connected,queue={}, {id(25,36)}
lake_connected[queue[1]]=true
local i=1
while queue[i] do
  local tile=queue[i];i=i+1
  for d=1,4 do
    local next_=Sim.adjacent(tile,d)
    if next_ and not lake_connected[next_] and s.tiles[next_].terrain=="water" then
      queue[#queue+1]=next_;lake_connected[next_]=true
    end
  end
end
assert(#queue==stats.water,"Some apparent ocean cells are unreachable isolated water.")
for i,t in ipairs(s.tiles) do
  local x,z=Sim.xy(i)
  local m,h=terrain(i)
  assert(t.h==h)
  local a=Terrain.corner(s.corner_grid,x,z)
  local b=Terrain.corner(s.corner_grid,x+1,z)
  local c=Terrain.corner(s.corner_grid,x,z+1)
  local d=Terrain.corner(s.corner_grid,x+1,z+1)
  assert(Slope.valid(a,b,c,d))
  if t.terrain=="water" then assert(m==0 and h==0 and t.water_class=="sea" and not t.coastal_water) end
  for u=0,4 do
    local n=id(x+1,z)
    if n then
      assert(Terrain.height(s.corner_grid,x,z,1,u/4)==Terrain.height(s.corner_grid,x+1,z,0,u/4))
    end
    n=id(x,z+1)
    if n then
      assert(Terrain.height(s.corner_grid,x,z,u/4,1)==Terrain.height(s.corner_grid,x,z+1,u/4,0))
    end
  end
end
local s2=fresh()
for i,h in ipairs(s.corner_grid.levels) do assert(h==s2.corner_grid.levels[i]) end
for i,t in ipairs(s.tiles) do assert(t.variant==s2.tiles[i].variant and t.wood==s2.tiles[i].wood) end

local title="coastal test circuit QA"
local first,last=id(stats.bridge.x1,stats.bridge.z),id(stats.bridge.x2,stats.bridge.z)
local ok,cost=Sim.road_bridge(s,title,first,last,0,true)
assert(ok and cost==2447,tostring(cost))
assert(Sim.road_bridge(s,title,first,last,2,true))
local Track=load("openttd/rail_track")
local Follow=load("openttd/rail_follow")(Track)
local Costs=load("openttd/rail_yapf_cost")(Track,Follow)
local Search=load("openttd/rail_yapf_search")(Track,Follow,Costs)
local Lab=load("trackworks")(Sim,Track,Follow,Slope,Costs,Search,terrain)
local H=load("openttd/rail_height")(Track,Slope)
local Q=load("openttd/rail_construction")(Track,load("openttd/rail_signals")(Track),H)
local Site=load("openttd/rail_span_site")
local B=load("openttd/rail_bridge")(load("openttd/road_bridge")(Slope),Q,Site)
local U=load("openttd/rail_tunnel")(load("openttd/road_tunnel"),Q,Site,Track)
local Spans=load("rail_span_world")(Sim,Terrain,H,B,U,Track)
s.rail_span_enabled=true
local bp,why=Spans.quote_bridge(s,title,id(21,15),id(27,15))
assert(bp and bp.deck==2 and #bp.middle==5,tostring(why))
assert(Sim.road_bridge(s,title,first,last,0,false))
assert(Spans.commit(s,title,bp)==false) -- changes force fresh quote, even parallel
assert(Spans.commit(s,title,assert(Spans.quote_bridge(s,title,id(21,15),id(27,15)))))
local near,far=id(21,15),id(27,15)
local source_types=load("openttd/rail_types")
local old_cash=s.companies[title].cash
local bridge_key=s.tiles[near].rail_span_id
local low=s.tiles[id(24,15)]
local near_type,far_type=assert(Spans.electric_record(s,near)),assert(Spans.electric_record(s,far))
assert(near_type.other==far and far_type.other==near and near_type.length==5)
assert(near_type.dir==Track.SW and far_type.dir==Track.NE)
assert(near_type.middle[3]==id(24,15) and not Spans.electric_record(s,id(24,15)))
local native_board={tile=function(i) return Spans.electric_record(s,i) end}
local function wire(ids)
  return assert(source_types.quote_convert(native_board,ids,1,{owner=title,available=3}))
end
for _,selection in ipairs({{near},{far},{near,far},{far,near}}) do
  local q=wire(selection)
  assert(q.cost==476 and #q.charged==1 and #q.updates==2 and q.infra[0]==-28 and q.infra[1]==28)
end
assert(s.tiles[id(24,15)]==low and low.rail_type==nil and s.companies[title].cash==old_cash)
s.rail_bridge_above[id(24,15)]=nil
assert(not Spans.electric_record(s,near) and not Spans.electric_record(s,far))
s.rail_bridge_above[id(24,15)]=bridge_key
local saved=s.stock_rail_spans[bridge_key]
saved.tail.railtype=1
assert(not Spans.electric_record(s,near))
saved.tail.railtype=0
assert(Spans.electric_record(s,near))
-- Same native transaction as ordinary rail conversion, with span-only
-- QA readiness. The shipped game deliberately does not pass this callback.
local Wire=load("rail_electrification_world")(Sim,Terrain,Track,source_types,Spans)
local ctx={availability=function() return 3 end,span_art_ready=function(_,p) return p.kind=="bridge" end}
local line={near}
for _,i in ipairs(near_type.middle) do line[#line+1]=i end
line[#line+1]=far
assert(Wire.quote(s,title,line,1,ctx).cost==476)
local lo=assert(Wire.quote(s,title,{far},1,ctx))
assert(lo.cost==476 and #lo.ids==7)
assert(not Wire.quote(s,title,{id(24,15)},1,ctx))
local with_badge=load("rail_electrification_world")(Sim,Terrain,Track,source_types)
assert(not with_badge.quote(s,title,{near},1,ctx))
local before_type=s.topology
s.tiles[id(24,15)].rail_reserved=1
local refused,why=Wire.commit(s,title,lo,ctx)
assert(not refused and why=="RAIL_RESERVED" and s.companies[title].cash==old_cash and s.topology==before_type)
s.tiles[id(24,15)].rail_reserved=nil
local did,paid,dirty,receipt=Wire.commit(s,title,lo,ctx)
assert(did and paid==476 and #dirty==7 and receipt.infra[0]==-28 and receipt.infra[1]==28)
assert(s.companies[title].cash==old_cash-476 and not Wire.commit(s,title,lo,ctx))
assert(saved.railtype==1 and saved.head.railtype==1 and saved.tail.railtype==1 and s.tiles[id(24,15)]==low)
assert(s.tiles[near].rail_type==nil and s.tiles[far].rail_type==nil and low.rail_type==nil)
local downgrade=assert(Wire.quote(s,title,{near,far},0,ctx))
assert(downgrade.cost==84 and Wire.commit(s,title,downgrade,ctx))
assert(saved.railtype==0 and saved.head.railtype==0 and saved.tail.railtype==0)
assert(s.companies[title].cash==old_cash-560 and low.rail_type==nil)
local Passenger,Rate=load("openttd/passengers"),load("openttd/station_rating")
local Catchment=load("openttd/station_catchment")(Passenger,Rate)
local Coal=load("openttd/coal_industry")(Passenger,Rate,Catchment,load("openttd/income"))
local CW=load("coal_industry_world")(Sim,Terrain,Coal)
assert(CW.seed(s,id(30,11),id(40,12)))
local Timber=load("timber_world")(Sim,Terrain,Sim.timber_rules())
assert(Timber.default_1751(s))
for x=28,37 do
  local i=id(x,14)
  local shape,h=terrain(i)
  assert(shape==0 and h==1 and not s.tiles[i].wood)
  assert(Lab.change(s,title,i,0,false,shape))
end
assert(Lab.depot(s,title,id(28,14),Track.SW))
assert(Lab.station(s,title,id(31,14),id(32,14)))
assert(Lab.station(s,title,id(36,14),id(37,14)))
assert(Lab.service_route(s,title,{tile=id(28,14)},2))

local Air=load("airport_network")(Sim,Terrain,{W=4,H=3})
for _,p in ipairs(stats.airfields) do
  local quote,error_,pos=Air.quote(s,title,id(p[1],p[2]))
  assert(quote and #quote.tiles==12,tostring(error_).."@"..tostring(pos))
end
local Water=load("openttd/ship_follow")(Track)
local Facilities=load("openttd/ship_facilities")(Track,Water)
local Network=load("ship_network")(Sim,Terrain,Water,Facilities)
assert(Network.quote(s,title,"dock",id(5,32)))
assert(Network.quote(s,title,"dock",id(8,32)))
assert(Network.quote(s,title,"depot",id(12,34),0))
assert(CW.seed(s2,id(12,27),id(5,28)))
-- Default workbenches coexist through true calendar boundaries rather
-- than feeding the forest economy a fractional 1 February ordinal.
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_timber,s.road_coal=true,true
Sim.mount_road_bus_market(s,load("openttd/stock_engine_calendar"),1950,true)
Sim.mount_coastal_flood(s)
for _=1,100 do Sim.daily(s) end
local year,month,day=Sim.date(s)
assert(year==1950 and month==4 and day==11 and Sim.road_timber_active(s) and Sim.road_coal_active(s))
local oil=fresh()
local Oil=assert(Sim.mount_oil_world(oil,Terrain,true))
assert(Oil.default_1751(oil))
local farm=fresh()
local Farm,rng=Sim.mount_farm_world(farm,Terrain,true)
assert(Farm,rng);assert(Farm.default_1751(farm,rng))
print(("COASTAL_CIRCUIT_PASS: %d changed corners, %d sea tiles, %d shoreline slopes, %d dry flat cells; real coal/timber, optional alternative freight, bridges, depot, stations, runways and docks."):format(layout_changes,stats.water,stats.shore,stats.flat))
