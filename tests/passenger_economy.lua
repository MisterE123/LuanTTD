local M=dofile("mods/bayline/sim.lua")
local T=dofile("mods/bayline/openttd/terrain.lua")
local P=dofile("mods/bayline/openttd/passengers.lua")
local I=dofile("mods/bayline/openttd/income.lua")
local function id(x,z) return M.id(x,z) end
local function new()
  local s=M.new(1751)
  s.corner_grid=T.new(M.W,M.H)
  s.road_economy=true
  for z=9,11 do for x=6,12 do
    local t=s.tiles[id(x,z)]
    t.terrain="grass";t.h=0;t.house=nil;t.site=nil;t.wood=nil
  end end
  local a,b,c=id(6,10),id(9,10),id(12,10)
  assert(M.build(s,"A","road",M.line(a,c)))
  assert(M.build(s,"A","road_station",{a,b,c}))
  return s,s.stations[s.tiles[a].station],s.stations[s.tiles[b].station],s.stations[s.tiles[c].station]
end
local function until_true(s,p)
  local d=0
  repeat
    M.daily(s);d=d+1
    assert(d<40,"Timed out waiting for transport event")
  until p()
  return d
end
local function stock_fare(units,dist,age)
  return I.regular(units,dist,age,unpack(I.temperate.passenger))
end

local s,a,b,c=new()
assert(a.site==1 and b.site==1 and c.site==1 and a.id~=c.id)
for _=1,4 do M.daily(s) end
assert(M.waiting_passengers(s,a)==0 and not a.passenger_service_day)
assert(M.waiting_passengers(s,c)==0 and not c.passenger_service_day)
local depot=id(7,11)
assert(not M.build(s,"A","road_depot",{id(6,11)}),"A bay may not acquire a second entrance")
assert(M.build(s,"A","road_depot",{depot}))
local vid=assert(M.purchase(s,"A","bus","passenger",nil,depot))
assert(M.add_order(s,"A",vid,a.id))
assert(M.add_order(s,"A",vid,c.id))
assert(M.toggle(s,"A",vid))
local bus=s.fleet[vid]
local days_from_dispatch=until_true(s,function() return a.passenger_service_day end)
assert(bus.last_arrival.first and bus.last_arrival.tile==a.tile and bus.last_arrival.day==s.day)
assert(M.waiting_passengers(s,a)==0 and not bus.last_board)
M.daily(s);days_from_dispatch=days_from_dispatch+1
assert(bus.last_board.units>0 and bus.last_board.day==s.day and bus.last_board.tile==a.tile and bus.route)
assert(M.waiting_passengers(s,c)==0)
local packet=bus.batches[1]
local original_units,start_age,phase=packet.units,packet.age,bus.passenger_age_ticks
assert(packet.source==1 and packet.origin_tile==a.tile and packet.origin_station==a.id and start_age==0)
local transit_days=until_true(s,function() return bus.last_fare end)
local expected_age=start_age+math.floor((phase+transit_days*74)/185)
assert(bus.last_fare.amount==stock_fare(original_units,6,expected_age))
assert(bus.last_fare.amount>0 and bus.last_fare.units==original_units)
assert(bus.last_fare.tile==c.tile and c.passenger_service_day==s.day and bus.last_arrival.first)
assert(s.sites[1].received.passenger==original_units and s.companies.A.revenue==bus.last_fare.amount)
assert(b.passenger_service_day==nil and M.waiting_passengers(s,b)==0)
print(("same-town first fare: %d simulated days from route start"):format(days_from_dispatch+transit_days))

-- Genuine between-bus transfer: age pauses on the station platform, then
-- resumes on the second vehicle. Different stops can serve the same town.
s,a,b,c=new()
vid=assert(M.purchase(s,"A","bus","passenger",a.id))
assert(M.add_order(s,"A",vid,b.id,"transfer"))
assert(M.toggle(s,"A",vid))
local original=s.fleet[vid]
until_true(s,function() return M.waiting_passengers(s,b)>0 end)
assert(not b.passenger_service_day and not original.last_fare and s.companies.A.revenue==0)
local waiting=b.stock.passenger[1]
local age_before=waiting.age
assert(waiting.origin_station==a.id and waiting.origin_tile==a.tile)
assert(waiting.travel_x==-3 and waiting.travel_z==0)
assert(M.toggle(s,"A",vid))
for _=1,8 do M.daily(s) end
assert(b.stock.passenger[1]==waiting and waiting.age==age_before)
local fin=assert(M.purchase(s,"A","bus","passenger",b.id))
assert(M.add_order(s,"A",fin,c.id))
assert(M.toggle(s,"A",fin))
local finishing=s.fleet[fin]
M.daily(s)
assert(b.passenger_service_day==s.day and finishing.last_board.units==waiting.units)
assert(finishing.batches[1].origin_station==a.id and finishing.batches[1].origin_tile==a.tile)
assert(finishing.batches[1].age==age_before)
phase=finishing.passenger_age_ticks
transit_days=until_true(s,function() return finishing.last_fare end)
expected_age=age_before+math.floor((phase+transit_days*74)/185)
assert(finishing.last_fare.amount==stock_fare(waiting.units,6,expected_age))
assert(finishing.last_fare.units==waiting.units and original.revenue==0)

-- Check stock distance accounting when transfer moves cargo for free
-- between disjoint platforms; do not pay for the untravelled portion.
local p={units=9}
P.pickup(p,{id=200,tile=id(3,10)},M.xy)
assert(not P.accept_at(p,{id=200}) and P.accept_at(p,{id=800}))
P.drop(p,{tile=id(5,10)},M.xy)
P.pickup(p,{id=300,tile=id(7,10)},M.xy)
assert(P.distance(p,id(11,10),M.xy)==6)
local q={units=9}
P.pickup(q,{id=200,tile=id(3,10)},M.xy)
P.drop(q,{tile=id(7,10)},M.xy)
P.pickup(q,{id=900,tile=id(1,10)},M.xy)
assert(P.distance(q,id(4,10),M.xy)==1) -- clamp to actual first to final tile

-- Remaining packet identity survives a partial load, while age saturates.
p.age=65535
local split=P.split(p,3)
assert(split.units==3 and p.units==6 and split.origin_station==p.origin_station and split.travel_x==p.travel_x)
local v={batches={p},passenger_age_ticks=160}
P.age_vehicle(v,2)
assert(p.age==65535 and v.passenger_age_ticks==123)

-- MoveGoodsToStation fractional allocation and same-company split.
local fs={{st={id=1,owner="A"},rating=80},{st={id=2,owner="A"},rating=40},{st={id=3,owner="B"},rating=100}}
P.allocate(10,fs)
assert(fs[1].st.id==3 and fs[1].fixed==562 and fs[2].fixed==299 and fs[3].fixed==149)
local st={}
assert(P.whole_units(st,299)==1 and st.passenger_fraction==43)
assert(P.whole_units(st,213)==1 and st.passenger_fraction==0)
print("PASS: selective passenger pickup, same-town packet fares, transfer age and origin, and station allocation")
