-- SPDX-License-Identifier: GPL-2.0-only
local dir="mods/bayline/openttd/"
local Packets=dofile(dir.."passengers.lua")
local Rating=dofile(dir.."station_rating.lua")
local Catchment=dofile(dir.."station_catchment.lua")(Packets,Rating)
local Income=dofile(dir.."income.lua")
local RatingRuntime=dofile("mods/bayline/station_rating_runtime.lua")({},Rating,Packets)
local C=dofile(dir.."coal_industry.lua")(Packets,Rating,Catchment,Income)
local function station(id,x,z,kind,owner)
  return {id=id,tile=z*64+x,x=x,z=z,town=4,owner=owner or 1,tiles={{x=x,y=z,kind=kind}}}
end
local function cover(s) return Catchment.build(s,64,64) end
local function xy(i) return i%64,math.floor(i/64) end
local m=C.new("coal_mine",3,8,9,{counter=256,completed=true})
local g=C.new("power_station",4,26,9,{generating_world=true})
local fresh=C.new("coal_mine",5,2,2)
assert(#m.tiles==6 and #g.tiles==8 and not g.tiles[1].completed and g.tiles[1].stage==2)
assert(not fresh.tiles[1].completed and fresh.tiles[1].stage==0)
for i=1,11 do assert(C.tile_loop(fresh,fresh.tiles[1],{})==0 and not fresh.tiles[1].completed) end
assert(C.tile_loop(fresh,fresh.tiles[1],{})==0 and fresh.tiles[1].completed)
assert(C.tile_loop(g,g.tiles[1],{})==0 and g.tiles[1].completed)
assert(C.new("coal_mine",5,2,2,{production_random=0}).produced.rate==7)
assert(C.new("coal_mine",5,2,2,{production_random=4294967295}).produced.rate==22)
assert(C.new("coal_mine",5,2,2,{original=true,production_random=0}).produced.rate==15)
assert(C.new("coal_mine",5,2,2,{original=true,generating_world=true}).produced.last.production==120)
local ambient=0
local opts={ambient_rng=function() ambient=ambient+1 end}
for i=1,255 do assert(C.production_tick(m,opts)==0) end
assert(C.production_tick(m,opts)==15 and ambient==4 and m.counter==0)
assert(C.production_tick(m,{editor=true})==0 and m.counter==0)
assert(C.production_tick(m,opts)==0 and m.counter==65535 and ambient==5)
local source=station(20,7,9,"truck")
local far=station(21,0,0,"truck")
local bus=station(22,7,9,"bus")
local company=station(23,7,10,"rail",2)
local sinks_only_ordinary=station(29,23,9,"truck")
local sink=station(30,25,10,"truck")
local bus_sink=station(31,25,10,"bus")
local no_accept=C.acceptance(sinks_only_ordinary,cover(sinks_only_ordinary),{g})
assert(not no_accept.accepts and no_accept.raw_eighths==0 and #no_accept.near==1)
local accepts=C.acceptance(sink,cover(sink),{g})
assert(accepts.accepts and accepts.eighths==16 and #accepts.near==1 and accepts.near[1].distance==1)
local bus_accepts=C.acceptance(bus_sink,cover(bus_sink),{g})
assert(not bus_accepts.accepts and bus_accepts.raw_eighths==16)
local stations={source,far,bus}
local covers={[20]=cover(source),[21]=cover(far),[22]=cover(bus),[23]=cover(company)}
local function offer(ind,n) return C.distribute(ind,n,stations,covers,{day=2}) end
local amount,moved=C.tile_loop(m,m.tiles[1],{},offer)
assert(amount==15 and moved==0 and m.produced.waiting==0)
for _,s in ipairs(stations) do C.observe_loading(s,{build_year=1935},20,1935) end
C.observe_loading(company,{build_year=1937,mode="rail",max_speed=100},0,1940)
local company_goods=C.goods(company)
assert(company_goods.last_speed==100 and company_goods.last_age==3 and company_goods.time_since_pickup==255)
local locked=select(1,C.distribute(m,15,{company},covers,{town_rights=function() return {exclusive_counter=1,exclusivity=1} end}))
assert(locked==0)
m.exclusive_consumer=1
assert(C.distribute(m,15,{company},covers)==0)
m.exclusive_consumer=nil
assert(C.distribute(m,15,{source},covers,{packet_allocatable=function() return false end})==0)
assert(C.goods(source).amount_fract==nil)
m.produced.waiting=5
assert(C.tile_loop(m,m.tiles[2],{},offer)==0 and m.produced.waiting==5)
m.produced.waiting=15
amount,moved=C.tile_loop(m,m.tiles[2],{},offer)
assert(amount==15 and moved==10 and C.waiting(source)==10 and C.goods(source).amount_fract==80)
assert(C.goods(source).has_rating and C.waiting(bus)==0 and C.waiting(far)==0)
m.produced.waiting=513
amount,moved=C.tile_loop(m,m.tiles[1],{recession=true},offer)
assert(amount==128 and moved==88 and m.produced.waiting==258 and C.waiting(source)==98)
assert(m.produced.current.production==158 and m.produced.current.transported==98)
local packets,load=C.pickup(source,C.truck.capacity,xy)
assert(#packets==2 and load==20 and C.waiting(source)==78)
local first=packets[1]
assert(first.units==10 and first.origin_station==20 and first.source==3 and first.source_type=="industry")
assert(C.delivery(source,{accepts=true,near={{ind=g}}},first,{xy=xy}).accepted==0)
assert(C.delivery(sink,accepts,first,{xy=xy,transfer=true}).payment==0)
assert(C.delivery(sink,accepts,first,{xy=xy,no_unload=true}).payment==0)
local g2=C.new("power_station",6,25,12,{completed=true})
local many=C.acceptance(sink,cover(sink),{g2,g})
assert(#many.near==2 and many.near[1].ind==g)
g.accepted.waiting=65533
local delivered=C.delivery(sink,many,first,{xy=xy,date=123})
assert(delivered.accepted==10 and delivered.remaining==0 and delivered.payment==Income.regular(10,19,0,5916,7,255))
assert(delivered.plants[1].amount==2 and delivered.plants[2].amount==8)
assert(g.accepted.last_accepted==123 and C.goods(sink).ever_accepted)
C.trigger_delivery(delivered)
assert(g.accepted.waiting==0 and g.was_cargo_delivered and not g.produced and g2.accepted.waiting==0)
local excluding=C.new("power_station",3,25,10,{completed=true})
local no_payment=C.delivery(sink,C.acceptance(sink,cover(sink),{excluding}),first,{xy=xy})
assert(no_payment.accepted==0 and no_payment.remaining==10 and no_payment.payment==0)
assert(C.month(m,1935,{frozen=true})==nil and m.produced.last.production==158 and m.produced.current.production==0)
assert(C.month(g,1935,{})==nil and not g.removed)
m.produced.rate=1
assert(C.production_change(m,{monthly=true,random_u32=function() return 4294967295 end})=="closure")
assert(C.month(m,1936,{})=="removed" and m.removed)
local only=C.new("coal_mine",10,4,4,{completed=true})
only.produced.rate=1
assert(not C.production_change(only,{monthly=true,industry_count=1,random_u32=function() return 4294967295 end}))
assert(only.prod_level==16)
local sg=C.goods(source)
sg.time_since_pickup=254
local rated=C.rating_tick(source,{truncate=RatingRuntime.truncate})
assert(rated.expire and not sg.has_rating and sg.last_speed==0 and C.waiting(source)==0)
assert(C.distribute(m,15,{source},covers)==0)
local cursor={tick=0,cursor=1}
local visited={}
for tick=0,255 do
  cursor.tick=tick
  C.landscape_tick(cursor,6,6,function(tile)
    assert(not visited[tile],"Tile repeated before end of landscape cycle")
    visited[tile]=true
  end)
end
assert(cursor.cursor==1)
for i=0,4095 do assert(visited[i]) end
print("PASS stock coal mine → freight station → Balogh Coal Truck → coal power plant economy")
