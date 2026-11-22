-- Seeds actual game roads, stops, companies, authored houses and vans/buses.
-- A test-only movement handoff checks one routed leg and supplies its
-- arrival, since road_speed_runtime's shared clock is integrated separately.
local root="mods/bayline/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local H=dofile(root.."openttd/town_passengers.lua")
local P=dofile(root.."openttd/passengers.lua")
local I=dofile(root.."openttd/income.lua")
local K=dofile(root.."openttd/station_rating.lua")
local R=dofile(root.."station_rating_runtime.lua")(Sim,K,P)
local Mail=dofile(root.."road_mail_runtime.lua")(Sim,H,P,I,K,R)
local Timing=dofile(root.."openttd/loading_timing.lua")
local L=dofile(root.."road_loading_runtime.lua")(Timing,P)
local Factory=dofile(root.."road_station_service.lua")
local function simple_copy(x)
  if type(x)~="table" then return x end
  local out={}
  for k,v in pairs(x) do out[k]=simple_copy(v) end
  return out
end
local function ck(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end

local function run(cargo)
  local mail=cargo=="mail"
  local s=Sim.new(1751)
  dofile(root.."town_layout.lua")(Sim,s)
  s.corner_grid=dofile(root.."terrain_preview.lua")(Sim,Terrain,s)
  s.road_economy=true;s.road_stock_clock=true;s.road_stock_house_supply=true
  s.road_mail=true;s.road_stock_loading=true
  local company=cargo.." test"
  local a,b=Sim.id(11,12),Sim.id(17,12)
  assert(Sim.build(s,company,"road",Sim.line(a,b)))
  if mail then
    assert(Sim.build_truck_stop(s,company,a) and Sim.build_truck_stop(s,company,b))
  else
    assert(Sim.build(s,company,"road_station",{a,b}))
  end
  local sa,sb=s.tiles[a].station,s.tiles[b].station
  local first,second=s.stations[sa],s.stations[sb]
  local vid=assert(Sim.purchase(s,company,mail and "mail_van" or "bus",cargo,sa))
  local v=s.fleet[vid]
  assert(Sim.add_order(s,company,vid,sb))
  assert(Sim.toggle(s,company,vid))
  local api=Factory(Sim,L,P,I,R,Mail,{
    news=function(state,msg) state.news[#state.news+1]=msg end
  })
  assert(api.handles(s,v))
  local phase,leave_tick,fare_tick,received_tick="start"
  local events={}
  local function after_game_tick(tick)
    local depart,rounds=api.tick(s,tick)
    for _,round in ipairs(rounds) do if round.delivered>0 then received_tick=tick end end
    if depart[1] then
      assert(depart[1]==vid)
      api.leave(s,v,tick)
      if phase=="start" then
        leave_tick=tick
        assert(v.units==Sim.vehicles[v.engine].capacity)
        local course,_,_,frames=Sim.path(s,s.stations[sa],s.stations[sb],"road",company,nil,v)
        assert(course and #course>=2 and frames and #frames>8)
        v.station=nil;v.route=course;v.progress=1
        phase="moving"
      elseif phase=="arrival" then
        fare_tick=tick
        phase="done"
        v.running=false
      end
    end
    if phase=="moving" and tick==leave_tick+121 then
      v.station=sb;v.route=nil;v.index=2
      api.begin(s,s.stations[sb],v,{no_load=true},tick)
      phase="arrival"
    end
    api.age_vehicle(s,v,tick)
    local age=v.cargo_age_counter
    api.age_vehicle(s,v,tick)
    ck(v.cargo_age_counter,age)
    local dup,rounds=api.tick(s,tick)
    ck(#dup,0);ck(#rounds,0)
  end
  local shared=setmetatable({},{__index=H})
  -- Existing town allocator and exact rating scheduler are used unchanged.
  -- This wrapper exposes the after-landscape slot to the fixture driver.
  function shared.advance_houses(clock,ticks,house,settings,random,emit,before)
    for _=1,ticks do
      H.advance_houses(clock,1,house,settings,random,emit,before)
      after_game_tick(clock.counter)
    end
  end
  local Town=dofile(root.."town_passenger_runtime.lua")(Sim,shared,P,R,Mail)
  Town.start(s)
  assert(api.acceptance(s,first,cargo)>=8 and api.acceptance(s,second,cargo)>=8)
  api.begin(s,first,v,{action="full"},0)
  assert(not v.last_board and not v.last_fare)
  if mail then assert(not Mail.offer(first))
  else assert(not R.offer(s,first)) end
  local restarted=false
  for day=1,500 do
    s.day=day
    Town.day(s)
    for _,effect in ipairs(api.take_effects(s)) do events[#events+1]=effect end
    if phase=="start" and v.units>0 and not restarted then
      local prev=v.units
      s=simple_copy(s);v=s.fleet[vid]
      ck(v.units,prev)
      ck(#api.take_effects(s),0)
      restarted=true
    end
    if phase=="done" then break end
  end
  assert(restarted and phase=="done" and leave_tick and received_tick and fare_tick)
  assert(leave_tick<received_tick and received_tick<fare_tick)
  local comp=s.companies[company]
  ck(comp.paid_units,Sim.vehicles[v.engine].capacity)
  ck(comp.units,v.delivered)
  ck(comp.revenue,v.last_fare.amount)
  ck(comp.month_rev,v.last_fare.amount)
  ck(v.stock_profit_with_feeders,v.revenue)
  assert(v.last_fare.amount>0 and v.last_board.tile==a and v.last_fare.tile==b)
  local board,fare,arrive=0,0,0
  for _,e in ipairs(events) do
    ck(e.cargo,cargo);ck(e.vehicle,vid)
    if e.kind=="board" then ck(e.data.tile,a);board=board+e.data.units
    elseif e.kind=="fare" then ck(e.data.tile,b);fare=fare+e.data.units
    elseif e.kind=="arrival" then arrive=arrive+1 end
  end
  ck(board,v.delivered);ck(fare,v.delivered)
  ck(arrive,mail and 0 or 2)
  ck(s.stock_load_tick,s.passenger_house_clock.counter)
  ck(#api.take_effects(s),0)
  local def=Sim.vehicles[v.engine]
  print(("%s: %d units from real houses; positive fare %d after loaded tick %d and settlement tick %d")
    :format(cargo,def.capacity,v.last_fare.amount,leave_tick,fare_tick))
end

run("passenger")
run("mail")

-- Reservation must stay visible until a physical boarding slice. A saved
-- parked vehicle pauses its loading economy counter, not its age clock.
local s=Sim.new(2)
s.road_economy=true;s.road_stock_loading=true
local st={id=1,tile=Sim.id(9,9),mode="road",owner="x",site=1,served={1},
  stock={passenger={{units=30,source=1,origin_station=1,age=0}}},last_service={}}
s.stations[1]=st
local id=assert(Sim.purchase(s,"x","bus","passenger",1))
local v=s.fleet[id]
v.running=true
local api=Factory(Sim,L,P,I,R,Mail)
api.begin(s,st,v,{action="full"},0)
api.tick(s,1)
ck(P.waiting(st),0)
ck(api.display_waiting(s,st,"passenger"),22)
ck(v.last_board.units,8)
v.running=false
local delay=v.load_state.ticks
for t=2,32 do
  api.tick(s,t);api.age_vehicle(s,v,t)
end
ck(v.load_state.ticks,delay)
ck(v.units,8)
ck(api.display_waiting(s,st,"passenger"),22)
api.leave(s,v,32)
ck(P.waiting(st),22)
ck(api.display_waiting(s,st,"passenger"),22)
print("PASS: seeded passenger and mail station service, save restart, fare attribution, exact age, and visible reserve/board separation")
