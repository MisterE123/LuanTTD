local Sim=dofile("mods/luanttd_core/sim.lua")
local Terrain=dofile("mods/luanttd_core/openttd/terrain.lua")
local function m(p) return dofile("mods/luanttd_core/"..p..".lua") end
local P,Rating,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,Rating)
local Coal=m("openttd/coal_industry")(P,Rating,C,Income)
local Timber=m("openttd/timber_industry")(P,C,Rating,Income,Coal,m("openttd/town_goods"))
local Rules=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),P,C,Rating,Income,Coal,Timber)
local W=dofile("mods/luanttd_core/oil_industry_world.lua")(Sim,Terrain,Rules)
local function build_world()
  local s=Sim.new(1751)
  dofile("mods/luanttd_core/town_layout.lua")(Sim,s)
  s.corner_grid=dofile("mods/luanttd_core/terrain_preview.lua")(Sim,Terrain,s)
  s.road_economy,s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply=true,true,true,true
  for kind,data in pairs(W.facilities) do Sim.facilities[kind]=data end
  return s
end
assert(W.refinery_edge(31,70,256,256,32,false))
assert(not W.refinery_edge(32,70,256,256,32,false))
assert(W.refinery_edge(63,110,512,256,32,false))
assert(not W.refinery_edge(64,110,512,256,32,false))
assert(W.refinery_edge(64,110,512,256,32,true))
local function id(x,z) return assert(Sim.id(x,z)) end
local s=build_world()
local rev=s.topology
local plan=assert(W.plan(s,11,2,15,17))
assert(#plan.wells.cells==5 and #plan.refinery.cells==15 and plan.refinery.level==0 and s.topology==rev)
plan.refinery.cells[1].gfx=18
local r,reason=W.place(s,plan)
assert(not r and reason=="STALE_OIL_PLACEMENT" and s.topology==rev)
local land=s.tiles[id(15,17)]
land.wood=true
r,reason=W.default_1751(s)
assert(not r and reason=="OIL_FOOTPRINT_OCCUPIED")
assert(not s.tiles[id(11,2)].stock_industry and s.topology==rev)
land.wood=nil
local firms,dirty=W.default_1751(s)
assert(firms and #dirty==20 and s.topology==rev+1)
assert(firms[W.BASE].source_type==11 and firms[W.BASE+1].source_type==4)
assert(not W.record(s,id(18,17))) -- Real stock layout hole.
assert(W.record(s,id(16,20)).gfx==20 and W.record(s,id(14,17))==nil)
assert(#s.sites==14 and s.sites[7].name=="Alder Steel")
local paths={
  {{12,4},{16,4},{16,7},{15,7},{15,8},{12,8},{12,14},{14,14},{14,16},{18,16}},
  {{12,4},{12,5},{16,5}},{{15,8},{15,12},{12,12}},
  {{18,16},{18,15},{14,15}},
}
local function xy(a) return id(a[1],a[2]) end
for _,points in ipairs(paths) do for i=2,#points do
  assert(Sim.build(s,"A","road",Sim.line(xy(points[i-1]),xy(points[i]))))
end end
local stops={}
for i,at in ipairs{{13,4},{16,16},{14,8}} do
  local t=xy(at)
  assert(Sim.build(s,"A","road_station",{t}))
  local st=s.stations[s.tiles[t].station]
  st.stop_type="truck"
  stops[i]=st
end
assert(Sim.build(s,"A","road_depot",{id(11,12)}))
local function leg(a,b,td)
  local _,arrive,_,frames=Sim.path(s,stops[a],stops[b],"road","A",nil,
    {engine="goods_truck",cargo="goods",road_arrival_td=td})
  assert(frames)
  return arrive,#frames
end
local first,f1=leg(1,2)
local _,f2=leg(2,1,first)
local second,f3=leg(2,3)
local _,f4=leg(3,2,second)
assert(f1==351 and f2==408 and f3==226 and f4==243)
s.stock_oil_industries[W.BASE].removed=true
local before=s.topology
local cleared=W.sweep_closed(s)
assert(#cleared==5 and s.topology==before+1 and s.sites[firms[W.BASE].site].closed)
assert(#W.sweep_closed(s)==0 and not W.record(s,id(11,2)))
assert(W.record(s,id(15,17)) and s.stations[stops[1].id]==stops[1])
print("PASS: exact 20-cell oil footprint, four road legs, and stock closure clears only its site")
