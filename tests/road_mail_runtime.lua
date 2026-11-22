local base="mods/luanttd_core/"
local Sim=dofile(base.."sim.lua")
local H=dofile(base.."openttd/town_passengers.lua")
local P=dofile(base.."openttd/passengers.lua")
local I=dofile(base.."openttd/income.lua")
local K=dofile(base.."openttd/station_rating.lua")
local R=dofile(base.."station_rating_runtime.lua")(Sim,K,P)
local Mail=dofile(base.."road_mail_runtime.lua")(Sim,H,P,I,K,R)
local function same(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local s=Sim.new(1963)
local function station(i,x,z,kind,owner)
  local st={mode="road",id=i,tile=Sim.id(x,z),stop_type=kind,owner=owner or "A",
    stock={},last_service={}}
  s.stations[i]=st
  return st
end
local a=station(1,8,10,"truck")
local b=station(2,18,10,"truck")
local pass=station(3,9,10,"bus")
local outside=station(4,13,10,"truck","B")
local put=function(x,z,id,finished)
  local tile=s.tiles[Sim.id(x,z)]
  tile.house=true
  tile.source_house={id=id,town=1,completed=finished~=false}
end
local v={id=17,cargo="mail",engine="mail_van",units=0,batches={},bought=s.day}
assert(Mail.supported_vehicle(v))
assert(not Mail.supported_vehicle({cargo="mail",engine="truck"}))
same(Mail.engine.id,126);same(Mail.engine.road_model,10)
same(Mail.engine.capacity,22);same(Mail.engine.max_speed,96)
same(Mail.engine.cargo_aging_ticks,185)
same(Mail.cargo.id,2);same(Mail.cargo.label,"MAIL")

-- Unknown/no-load visits and nearby bus stops do not attract mail.
put(5,7,0x06)
P.enqueue(pass,{units=6,origin_station=pass.id,age=0})
pass.passenger_fraction=233
same(Mail.from_house(s,4,4,6,{town=1}),0)
Mail.observe_loading(s,pass,v,22)
assert(not pass.mail_rating_state)
Mail.observe_loading(s,outside,v,22)
Mail.observe_loading(s,a,v,22)
same(Mail.offer(a),175)
same(Mail.offer(b),nil)
same(a.mail_rating_state.last_speed,48)
same(a.mail_rating_state.time_since_pickup,0)
same(Mail.from_house(s,4,4,6,{town=1}),2) -- exactly diagonal distance 3
same(Mail.waiting(a),2)
same(Mail.waiting(outside),0)
same(Mail.waiting(pass),0)
same(P.waiting(pass),6)
same(pass.passenger_fraction,233)
same(a.mail_fraction,192)
assert(a.mail_rating_state.has_rating and not a.passenger_rating_state)
same(a.stock.mail[1].source,1)
same(a.stock.mail[1].origin_station,a.id)

-- Branching house stock dates drive mail through the same stock clock, but
-- only local eligible truck stops receive it.
local clock=H.new_clock(6,6)
H.advance_houses(clock,1024,function(x,z)
  if x==4 and z==6 then return s.tiles[Sim.id(x+1,z+1)].source_house end
end,{},function() return 0xFFFFFFFF end,function(kind,amount,x,z,record)
  if kind=="mail" then Mail.from_house(s,amount,x,z,record) end
end)
same(Mail.waiting(a),4)
assert(a.mail_fraction~=0)
same(Mail.waiting(outside),0)

-- Real pickup gives an onboard packet with the correct origin/travel base.
Mail.enqueue(a,{units=25,source=1,origin_station=a.id,age=0})
same(Mail.load(s,a,v,Mail.engine.capacity),22)
same(v.units,22)
same(Mail.waiting(a),7)
local on=v.batches[1]
assert(on.origin_tile==a.tile and on.origin_station==a.id and on.travel_x==8)
same(a.time_since_load,0)
same(a.last_service.mail,s.day)
same(Mail.fare(s,a,on),nil)
a.mail_rating_state.time_since_pickup=7
Mail.observe_loading(s,a,v,0)
same(a.mail_rating_state.time_since_pickup,7)

-- Require eight eighths from actual tiles, not a town center or proximity
-- to a generating stop. Stock acceptance also counts unfinished buildings.
put(20,10,0x0E)
put(21,13,0x19)
same(Mail.acceptance(s,b),3)
assert(not Mail.accepts(s,b))
same(Mail.fare(s,b,on),nil)
for i=1,5 do put(15+i-1,7,0x06,i%2==0) end
same(Mail.acceptance(s,b),8)
assert(Mail.accepts(s,b))
local fare,distance=Mail.fare(s,b,on)
same(distance,10)
same(fare,I.regular(22,10,0,4550,20,90))
assert(fare>0)
Mail.age_vehicle(v,8)
same(on.age,4)
same(Mail.fare(s,b,on),fare) -- 20 stock packet periods before reduction

-- A transfer keeps origin and waiting age, refreshes station unload time,
-- but doesn't mark a mail loading attempt or start local production.
assert(Mail.transfer(s,b,on,v))
same(Mail.offer(b),nil)
assert(b.mail_rating_state.has_rating)
same(b.mail_rating_state.time_since_pickup,0)
same(b.time_since_unload,0)
same(on.travel_x,-10)
same(on.age,4)
local collector={id=25,cargo="mail",engine="mail_van",units=0,batches={},bought=s.day}
same(Mail.load(s,b,collector,22),22)
same(collector.batches[1].origin_tile,a.tile)
same(collector.batches[1].age,4)
same(collector.batches[1].travel_x,8)
assert(Mail.offer(b)>0)
same(Mail.fare(s,b,collector.batches[1]),fare)

-- Selectgoods expiry resets truck loading eligibility even if its history
-- records a successful pickup. Refresh must use this truck cargo again.
for _=1,255 do Mail.step_rating(s,a) end
same(Mail.waiting(a),0)
same(Mail.offer(a),nil)
assert(not a.mail_rating_state.has_rating and a.last_service.mail==s.day)
same(P.waiting(pass),6)
print("PASS: stock MPS mail capacity/fare, separate goods, house emission, exposure/acceptance, transfer age and expiry")
