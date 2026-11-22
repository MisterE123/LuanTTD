-- SPDX-License-Identifier: GPL-2.0-only
local T=dofile("mods/luanttd_core/openttd/rail_track.lua")
local C=dofile("mods/luanttd_core/openttd/level_crossing.lua")(T)
local Road=dofile("mods/luanttd_core/openttd/yapf_road_follow.lua")
local req={kind="rail",owner="track",track=0,railtype=0}
local road={kind="road",owner="road",road_owner="road",roadtype=0,road_bits=4,slope=7,base=2,town=2}
local c,why=C.quote(road,req);assert(c,why)
assert(c.road_axis==1 and c.rail_axis==0 and c.road_bits==5)
assert(c.road_owner=="road" and c.rail_owner=="track" and c.town==2)
assert(c.cost==195 and c.road_pieces_added==1 and c.rail_pieces_added==2 and c.top==3 and c.foundation=="flattened")
assert(road.road_bits==4 and road.kind=="road" and not c.barred and not c.reserved)
assert(T.status(C.rail_view(c))==0x101 and Road.status(C.road_view(c))==0x202)
assert(not C.quote(road,req,{cash=194}))
local _,reason=C.quote(road,req,{crossing_with_competitor=false})
assert(reason=="OWNED_BY_ANOTHER")
road.disallowed=1
_,reason=C.quote(road,req)
assert(reason=="CROSSING_ON_ONEWAY_ROAD")
road.disallowed=nil;road.road_bits=6
_,reason=C.quote(road,req)
assert(reason=="FALLBACK_CLEAR")
road.road_bits=4;road.tram_bits=1;road.tramtype=1;road.tram_owner="another"
_,reason=C.quote(road,req)
assert(reason=="OWNED_BY_ANOTHER")
road.tram_owner="track"
assert(C.quote(road,req).cost==385)
local rail={kind="rail",owner="track",trackbits=2,railtype=0,reserved_bits=2}
local b=assert(C.quote(rail,{kind="road",owner="road",pieces=2,disallowed=1}))
assert(b.road_axis==0 and b.rail_axis==1 and b.road_bits==10 and b.cost==190 and b.reserved)
assert(b.rail_owner=="track" and b.road_owner=="road" and b.rail_pieces_added==1)
local tram=assert(C.quote(rail,{kind="tram",owner="road",pieces=2}))
assert(tram.tram_bits==10 and tram.road_bits==0 and tram.cost==380)
tram.barred=true;tram.tram_owner="tram"
local upgraded=assert(C.quote(tram,{kind="road",owner="road",pieces=8,town=3}))
assert(upgraded.road_owner=="road" and upgraded.road_bits==10 and upgraded.tram_owner=="tram"
  and upgraded.tram_bits==10 and upgraded.rail_pieces_added==0 and upgraded.town==3
  and upgraded.barred and upgraded.reserved)
_,reason=C.quote(upgraded,{kind="road",owner="road",pieces=8})
assert(reason=="ALREADY_BUILT")
_,reason=C.quote({kind="signals",slope=0}, {kind="road",owner="road",pieces=2})
assert(reason=="FALLBACK_CLEAR")
_,reason=C.quote(rail,{kind="road",owner="road",pieces=2},{rail_types={[0]={no_crossing=true}}})
assert(reason=="CROSSING_DISALLOWED_RAIL")

local w=8
local function id(x,y) return x+y*w end
local X,Y,Z=id(3,5),id(3,4),id(3,3)
local function make(a)
  return {kind="crossing",road_axis=a,rail_axis=1-a,roadtype=0,tramtype=1,railtype=0,rail_owner="train"}
end
local tiles={}
for j=0,7 do for i=0,7 do tiles[id(i,j)]={kind="rail"} end end
tiles[X],tiles[Y],tiles[Z]=make(1),make(1),make(1)
local board={tile=function(i)return tiles[i] end}
function board.adjacent(v,d)
  local x,y=v%w,math.floor(v/w)
  local nx,ny=x+({[0]=-1,0,1,0})[d],y+({[0]=0,1,0,-1})[d]
  if nx>=0 and nx<w and ny>=0 and ny<w then return id(nx,ny) end
end
local pool,claim={},{}
local ctx={vehicles_at=function(i)return pool[i] end,
  reserved=function(i) return claim[i] end,
  set_reservation=function(i,_,on)claim[i]=on or nil end,ambient=true}
local train={type="train",front=true,owner="train",compatible={[0]=true},tile=id(2,4),
  td=8,x=39,y=65,z=8}
local tail={type="train",owner="train",front=false,tile=id(2,4),x=34,y=65,z=8}
local road_car={type="road",tile=Y,x=46,y=65,z=8}
pool[train.tile]={train,tail};pool[Y]={road_car}
assert(C.train_approach(board,train,ctx)==Y and not C.train_approach(board,tail,ctx))
train.owner="foreign";assert(not C.train_approach(board,train,ctx))
train.owner="train";train.compatible={};assert(not C.train_approach(board,train,ctx))
train.compatible={[0]=true};train.crashed=true;assert(not C.train_approach(board,train,ctx))
train.crashed=false;train.trackbits=64;assert(not C.train_approach(board,train,ctx))
train.trackbits=nil
assert(C.should_bar(board,Y,ctx) and C.road_step(board,id(3,2),Z,1,false,3,ctx)) -- bars not yet recomputed
local change=C.maybe_bar(board,Y,ctx)
assert(claim[Y] and #change==3 and change[1].tile==Y and change[2].tile==X and change[3].tile==Z)
for _,e in ipairs(change) do assert(e.barred and e.sound) end
assert(not C.road_step(board,id(3,2),Z,1,false,3,ctx))
assert(C.road_step(board,Y,Y,1,false,3,ctx),"Do not stop a road vehicle at a same-tile pixel")
assert(C.road_step(board,Z,Y,1,false,3,ctx),"With both adjacent bars set and no train on this tile, stock red mask clears")
assert(#C.maybe_bar(board,Y,ctx)==0)

-- An already admitted road vehicle does not veto the source rail claim.
-- Head enters, then leaves, but a wagon (even crashed) holds the bars.
train.tile=Y;pool[id(2,4)]={tail};pool[Y]={train,road_car}
assert(C.road_step(board,Z,Y,1,false,3,ctx)==false)
assert(C.stock_collision(board,{road_car},function()return {train} end)==false)
train.x=42
assert(C.stock_collision(board,{road_car},function()return {train} end))
train.z=15
assert(not C.stock_collision(board,{road_car},function()return {train} end))
train.tile=id(4,4);pool[Y]={tail,road_car};tail.tile=Y;tail.crashed=true
local ok,events=C.unreserve(board,Y,0,ctx)
assert(ok and not claim[Y] and #events==0 and tiles[Z].barred)
pool[Y]={road_car};tail.tile=id(4,4)
events=C.tail_left(board,Y,ctx)
assert(#events==3 and not tiles[Y].barred and not events[1].sound)
assert(C.road_step(board,Z,Y,1,false,3,ctx))
ok,events=C.try_reserve(board,Y,0,ctx)
assert(ok and #events==3 and not events[1].sound)
assert(not C.try_reserve(board,Y,0,ctx))
assert(not C.try_reserve(board,Y,1,ctx))
print("PASS: stock crossing quotes/axes, road permissions, grouped bars, reservations, real wagon tail and collision probe")
