-- SPDX-License-Identifier: GPL-2.0-only
local function mod(path) return dofile("mods/bayline/"..path..".lua") end
local Sim=mod("sim")
local P=mod("openttd/passengers")
local Income=mod("openttd/income")
local Rating=mod("openttd/station_rating")
local RoadRating=mod("station_rating_runtime")(Sim,Rating,P)
local Catchment=mod("openttd/station_catchment")(P,Rating)
local Coal=mod("openttd/coal_industry")(P,Rating,Catchment,Income)
local Service=mod("road_coal_service")(Sim,Coal,Catchment,P,Income,Rating,RoadRating)
local Loading=mod("road_loading_runtime")(mod("openttd/loading_timing"),P)
local House=mod("openttd/town_passengers")

local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t),"Only regular save records should persist")
  local o={}
  for k,v in pairs(t) do o[k]=clone(v) end
  return o
end
local s=Sim.new(1751)
s.day=1
s.coal_demo_house_clock=House.new_clock(6,6)
local source,sink=101,222
local function stop(id,x,z,kind,owner)
  return {id=id,mode="road",stop_type=kind,tile=Sim.id(x,z),owner=owner,town=id,
    stock={passenger={},mail={}}}
end
s.stations={
  [source]=stop(source,8,10,"truck","Miner"),
  [sink]=stop(sink,26,11,"truck","Miner"),
  [333]=stop(333,8,11,"bay","Miner"), -- bus only
}
s.stock_coal_industries={
  [50]=Coal.new("coal_mine",50,8,9,{counter=16,completed=true}),
  [91]=Coal.new("power_station",91,26,9,{completed=true}),
}
local v={id=1,engine="coal_tipper",cargo="coal",bought=0,owner="Miner",batches={},units=0,revenue=0,delivered=0}
s.fleet={[1]=v}
local function credit(c,n)
  c.cash,c.revenue,c.month_rev=c.cash+n,c.revenue+n,c.month_rev+n
end
local ctx={credit=credit,received=function(state,plant,n)
  state.power_received=(state.power_received or 0)+n
  assert(plant.id==91)
end}
local b=Service.bind(s,ctx)
local function mount(data)
  s=clone(data);v=s.fleet[1];b=Service.bind(s,ctx)
end
local money=Sim.company(s,"Miner").cash
assert(Service.truck.capacity==20 and Service.truck.load_amount==5 and Service.truck.cargo_age_ticks==185)
assert(b.report(s.stations[sink]).accepts and not b.report(s.stations[source]).accepts)
assert(not b.report(s.stations[333]).accepts and b.display_waiting(s.stations[source])==0)
assert(not Service.supported_vehicle({engine="coal_tipper",cargo="mail"}))
local pending,released,confirmed,boards,attempt_age={},0,{},0
local tick=0
local function emit(kind,station,tr,rec)
  assert(rec.owner=="Miner" and tr==v and rec.tick==tick and rec.station==station.id)
  if kind=="deliver" then
    assert(rec.source_industry==50 and rec.destination_industry==91 and rec.distance==19)
    pending[#pending+1]=rec
  elseif kind=="board" then
    assert(rec.units==5 and rec.tile==s.stations[source].tile)
    boards=boards+rec.units
    confirmed[#confirmed+1]=tick
  elseif kind=="fare" then
    assert(not s.fare_event,"Fare should settle once")
    s.fare_event={tick=tick,units=rec.units,amount=rec.amount}
  end
end
local function step()
  tick=tick+1;s.day=1+math.floor((tick-1)/74)
  House.advance(s.coal_demo_house_clock,1,function(k,time)
    local amount,shipped=b.tile_visit(k%64,math.floor(k/64),time)
    if amount>0 then assert(amount==15) end
    released=released+shipped
  end)
  local ops=b.ops(tick,emit)
  if v.load_state then
    local station=s.stations[v.load_state.station]
    local _,departures=Loading.tick(station,s.fleet,ops)
    ops.station_done()
    if #departures>0 then assert(departures[1]==1);Loading.leave(station,v,ops) end
  end
  Loading.age_vehicle(v,1,Service.truck.cargo_age_ticks)
  if tick%185==0 then
    for _,station in pairs(s.stations) do b.step_rating(station) end
  end
  b.after_vehicle_tick(tick)
end
local function start(st,order)
  local ops=b.ops(tick,emit)
  return Loading.begin(s.stations[st],v,Service.truck.capacity,order,ops)
end

step()
start(source,{full=true})
step()
assert(Coal.goods(s.stations[source]).last_speed==48 and v.load_state and v.units==0)
assert(s.stock_coal_industries[50].produced.waiting==0 and released==0)
for _=1,14 do step() end
assert(s.stock_coal_industries[50].produced.waiting==15 and released==0,
  "Industry tick fills its own waiting amount, not the truck queue")
local boarding_save
for _=1,2000 do
  step()
  if not boarding_save and v.units==5 then
    boarding_save={units=v.units,reserved=v.load_state.reserved_units}
    assert(b.display_waiting(s.stations[source])==Coal.waiting(s.stations[source])+boarding_save.reserved)
    mount(s)
    assert(v.units==boarding_save.units and v.load_state.reserved_units==boarding_save.reserved)
  end
  if not v.load_state then break end
end
assert(boarding_save and released>=20 and boards==20 and v.units==20 and not v.load_state)
assert(#confirmed==4)
for i=2,#confirmed do assert(confirmed[i]-confirmed[i-1]>=20) end -- unchanged 20-tick pulse, stock 5 tons
assert(Coal.waiting(s.stations[333])==0 and not s.stations[333].goods)
for _,p in ipairs(v.batches) do assert(p.source_type=="industry" and p.source==50 and p.origin_station==source) end
local departed=tick
for _=1,425 do step() end -- real elapsed stock journey ticks, not fare arithmetic
for _,p in ipairs(v.batches) do assert(p.age>1) end
assert(tick-departed==425 and Sim.company(s,"Miner").cash==money)
-- A nearly full plant physically receives only 2 tons of the first
-- 5-ton unloading pulse. It consumes its input at end of station pass.
s.stock_coal_industries[91].accepted.waiting=65533
start(sink,{})
step()
assert(v.units==15 and v.load_state.coal_accepted==2 and v.load_state.payment.delivered==5)
assert(s.stock_coal_industries[91].accepted.waiting==0 and s.stock_coal_industries[91].was_cargo_delivered)
assert(not s.fare_event and Sim.company(s,"Miner").paid_units==0)
mount(s)
assert(v.units==15 and v.load_state.coal_accepted==2 and not s.fare_event)
for _=1,150 do step();if not v.load_state then break end end
assert(not v.load_state and v.units==0 and s.power_received==17 and v.delivered==17)
local expected,sum=0,0
for _,p in ipairs(pending) do
  expected=expected+Income.regular(p.units,p.distance,p.age,5916,7,255)
  sum=sum+p.units
end
assert(sum==17 and s.fare_event.units==17 and s.fare_event.amount==expected and expected>0)
local company=Sim.company(s,"Miner")
assert(company.cash==money+expected and company.paid_units==17 and company.month_rev==expected
  and company.revenue==expected and v.revenue==expected)
mount(s)
step()
assert(s.fare_event.amount==expected and Sim.company(s,"Miner").cash==money+expected)
assert(not b.report(s.stations[333]).accepts and #s.stations[sink].stock.mail==0)
local industry=s.stock_coal_industries[50]
assert(industry.produced.current.production>0 and industry.produced.current.transported==released)
print(string.format("PASS: stock coal mine source, 5-ton truck pulses, reload-safe %d delivered/$%d and no payment for rejected tons",sum,expected))
