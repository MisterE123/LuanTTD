-- SPDX-License-Identifier: GPL-2.0-only
local function src(p) return dofile("mods/luanttd_core/"..p..".lua") end
local S={W=128,H=64}
function S.id(x,z) if x>=1 and z>=1 and x<=S.W and z<=S.H then return (z-1)*S.W+x end end
function S.xy(i) return (i-1)%S.W+1,math.floor((i-1)/S.W)+1 end
function S.nearest_town() return {id=1} end
local Terrain={tile=function(g,x,z)
  local patch=g[S.id(x,z)]
  if patch then return patch[1],patch[2] end
  return 0,0
end}
function S.adjacent(i,d)
  local x,z=S.xy(i)
  local a=({{0,-1},{1,0},{0,1},{-1,0}})[d]
  return S.id(x+a[1],z+a[2])
end
local rig=src("openttd/oil_rig")
local coal=src("openttd/coal_industry")()
local oil=src("openttd/oil_industry")(src("openttd/farm_factory_industry"),nil,nil,nil,nil,coal)
local W=src("offshore_rig_world")(S,Terrain,rig,oil)
local rando,offers=0,{}
local ctx={economy_year=1960,original=true,
  random=function() rando=rando+1;return 2432955+rando end}
local s={seed=5,topology=1,sites={},tiles={},corner_grid={freeform_edges=true},
  next_stock_ship_station=4,next_small_airport=7,
  stock_ship_stations={[3]={id=3,owner="Other"}},
  stock_ship_buoys={[2]={id=2}},
  stock_small_airports={[6]={id=6,owner="Other"}}}
for z=1,S.H do for x=1,S.W do
  s.tiles[S.id(x,z)]={terrain="water",water_class="sea"}
end end
local origin=S.id(12,18)
s.tiles[origin].water_class="river"
local plan,why=W.quote(s,origin,ctx)
assert(plan,why)
assert(#plan.cells==6 and plan.cells[1].water_class=="river" and plan.town==1 and rando==0)
ctx.vehicle_on_ground=function(id) return id==origin end
assert(not W.place(s,plan,ctx))
assert(not s.stock_oil_placements and #s.sites==0 and s.topology==1 and rando==0)
ctx.vehicle_on_ground=nil
plan.cells[3].gfx=99
assert(not W.place(s,plan,ctx))
assert(not s.stock_oil_placements and #s.sites==0 and s.topology==1 and rando==0)
plan=assert(W.quote(s,origin,ctx))
local i,dirty=W.place(s,plan,ctx)
assert(i and #dirty==6 and i.neutral_station==nil and i.id==0x3000)
assert(i.produced[1].cargo=="oil" and i.produced[1].rate==15 and i.produced[2].cargo=="passenger" and i.produced[2].rate==2)
assert(rando==7 and s.topology==2 and s.tiles[origin].stock_industry.id==i.id)
assert(not W.quote(s,S.id(12,48),ctx)) -- one rig of this type per town
assert(not W.place(s,plan,ctx))
for _,c in ipairs(rig.water_checks) do assert(not s.tiles[S.id(plan.x+1+c[1],plan.z+1+c[2])].stock_industry) end
local o={complete_rig=function(ind,t) return W.complete(s,ind,t,ctx) end}
local function offer(_,c,n)
  offers[c]=(offers[c] or 0)+n
  return n
end
for step=1,11 do assert(oil.tile_loop(i,i.tiles[1],o,offer)==0 and not i.neutral_station) end
oil.tile_loop(i,i.tiles[1],o,offer)
local id=assert(i.neutral_station)
assert(id==7 and s.stock_neutral_stations[id].tile==origin and not i.tiles[2].completed)
assert(s.stock_ship_stations[id].owner==nil and s.stock_small_airports[id].owner==nil)
assert(s.stock_ship_stations[id].oil_rig==i.id and s.stock_small_airports[id].delta_z==54)
assert(s.tiles[origin].ship.kind=="oilrig" and s.tiles[origin].airfield.layout=="oilrig")
assert(s.stock_ship_stations[3].owner=="Other" and s.stock_small_airports[6].owner=="Other" and s.stock_ship_buoys[2].id==2)
assert(s.next_stock_ship_station==8 and s.next_small_airport==8 and s.topology==3)
assert(#W.docking_tiles(s,id,function() return true end)==10)
assert(#W.docking_tiles(s,id,function(cell) return cell==S.id(11,18) end)==1)
local track=src("openttd/rail_track")
local Follow=src("openttd/ship_follow")(track)
local ship=dofile("mods/luanttd_core/ship_network.lua")(S,Terrain,Follow,src("openttd/ship_facilities")(track,Follow))
local board=ship.board(s)
assert(Follow.at(board,origin)==0,"Anchor cannot be treated as ordinary water")
for _,c in ipairs(plan.cells) do assert(Follow.at(board,c.id)==0,"Water class alone cannot permit ships") end
local docks=board.station_dock_tiles(id)
assert(#docks==10)
for _,dock in ipairs(docks) do assert(Follow.ship_destination(board,dock,id),"Invalid rig berth") end
assert(not Follow.ship_destination(board,S.id(10,18),id))
-- Run the shared stock amount threshold. A passenger lot of two waits
-- until the third production tick creates six waiting passengers.
i.counter=259
for step=1,259 do
  oil.production_tick(i,{})
  oil.tile_loop(i,i.tiles[1],o,offer)
end
assert(offers.oil==30 or offers.oil==45,offers.oil)
assert(offers.passenger==nil or offers.passenger==6,offers.passenger)
i.produced[2].waiting=4;oil.tile_loop(i,i.tiles[1],o,offer)
local prior=offers.passenger
i.produced[2].waiting=6;oil.tile_loop(i,i.tiles[1],o,offer)
assert(offers.passenger==(prior or 0)+6)
i.removed=true
local cleanup,key=W.close(s,i)
assert(key==7 and #cleanup==6 and s.sites[1].closed)
assert(not s.stock_ship_stations[id] and not s.stock_small_airports[id] and not s.stock_neutral_stations[id])
assert(not s.tiles[origin].ship and not s.tiles[origin].airfield and s.tiles[origin].water_class=="river")
assert(#W.close(s,i)==0 and s.topology==4)
print("PASS offshore worker state: transactional six-cell site, real construction and cargo threshold, one neutral ID, ten nearby water approaches, closure restores water")
