-- Direct same-execution numeric comparison. Does not read an OpenTTD save.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local F=dofile("tests/lib/stock_active_bus_fixture.lua")
local sample=dofile("tests/fixtures/rc1-mixed-town.lua")
local ref=sample.start
local S=F.Sim
local s,towns,bus,owner=F.open(ref,true)
local T=m("openttd/rail_track")
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
s.road_mail,s.road_junction_clearance=true,true
local runtime=m("campaign_authority_runtime")(S,mod,s,cap)
local A=m("campaign_authority_endpoint")(S,runtime)
s.stock_economy_subsidies.duration=0 -- actual reference settings section, no monthly offer draw
local revision
local function check(r,where) revision=r.revision;return assert(r.ok,where..": "..tostring(r.why)),r.value end
local function command(key,c)
  c.kind,c.revision=key,revision
  local _,v=check(A.command(owner,c),key);return v
end
local function rail(req)
  local _,q=check(A.rail_quote(owner,req),req.tool)
  return command("rail_commit",{token=q.token})
end
local L,R,D=2257,2261,2263  -- one-based native IDs of original western/eastern stations and depot
rail({tool="track",first=L,last=D-1,track=T.X})
rail({tool="depot",first=D,direction=T.NE})
for _,id in ipairs({L,R}) do
  rail({tool="station",first=id,last=id,axis=0,length=1,tracks=1,separate=true,drag=true})
end
local function at_yard(op,stock)
  local _,q=check(A.rail_assembly(owner,D),"assembly "..op)
  command("rail_assembly",{token=q.token,operation=op,stock=stock})
end
at_yard("engine",0)
at_yard("wagon",27)
local _,q=check(A.rail_assembly(owner,D),"assembled consist")
local train
for id,u in pairs(q.units) do if #u.stocks==2 and u.stocks[1]==0 and u.stocks[2]==27 then train=id end end
local west,east=s.tiles[L].rail_station_id,s.tiles[R].rail_station_id
command("transport_start",{mode="rail",vehicle=assert(train),first=west,second=east})
s.stock_rail_stations[west].stock_station_pool_id=2
s.stock_rail_stations[east].stock_station_pool_id=3
local run=assert(s.stock_rail_dispatch.runs[1])
-- Source was saved in ordinary motion after visiting the east station.
local state=s.stock_rail_dispatch
local b=runtime.network.lab.board(s)
local Follow=runtime.network.follow
local PBS=m("openttd/rail_reservation")(T,Follow,runtime.network.cost)
local Life=m("openttd/rail_consist_reservation")(T,Follow,PBS)
local Motion=m("openttd/rail_motion")(T)
local Cm=m("openttd/rail_consist_motion")(T,Motion,Follow,Life)
local parts={}
for k,p in ipairs(ref.train) do
  local id=p.tile+1
  local x,y=p.x_pos+16,p.y_pos+16
  local td
  for i,node in ipairs(run.route) do
    if node.tile==id then td=node.td;if k==1 then run.index=i end;break end
  end
  parts[k]={tile=id,length=8,pose={x=x,y=y,tx=math.floor(x/16),ty=math.floor(y/16),
    td=assert(td),direction=p.direction}}
end
run.consist=assert(Cm.place(b,owner,parts))
state.life=Life.new()
assert(Life.register(b,state.life,run.id,owner,{
  {tile=parts[1].tile,td=parts[1].pose.td,unreserved=true},
  {tile=parts[2].tile,td=parts[2].pose.td,unreserved=true}}))
local lead=ref.train[1]
run.phase,run.speed,run.subspeed,run.progress,run.direction,run.z="running",lead.cur_speed,lead.subspeed,lead.progress,lead.direction,lead.z_pos
run.shuttle.arrivals,run.shuttle.reversals=1,1
run.vehicle_ticks,run.ticks=lead.tick_counter,lead.tick_counter
run.running_ticks_total=lead.running_ticks
run.stock_pool_id=1
run.stock_breakdowns=1
local h={}
for _,key in ipairs({"age","max_age","reliability","reliability_spd_dec","breakdown_chance","breakdown_ctr",
    "breakdown_delay","breakdowns_since_last_service","date_of_last_service","date_of_last_service_newgrf","tick_counter"}) do
  h[key]=assert(lead[key])
end
run.stock_fault=h
run.stock_fault_engine=ref.train_engine
run.stock_train_service_opts=ref.train_service
run.stock_random_parts={}
for i,p in ipairs(ref.train) do
  run.stock_random_parts[i]={stock_waiting_random_triggers=p.waiting_triggers,stock_vehicle_random_bits=p.random_bits}
end
local c=s.companies[owner]
c.cash,c.loan,c.stock_money_fraction=ref.cash,ref.loan,ref.day_state[1]
c.stock_quarter={income=ref.quarter[1],expenses=ref.quarter[2],delivered={passenger=ref.quarter[3]}}
s.passenger_rating_rng={ref.clock[4],ref.clock[5]}
local calendar=s.stock_bus_market.models[116]
for k,v in pairs(ref.engine) do calendar[k]=v end
calendar.expiry_age=calendar.phase1+calendar.phase2+calendar.phase3
local function hash(h,...)
  for i=1,select("#",...) do h=(h*65599+(select(i,...)))%2147483647 end
  return h
end
local function eq(tag,a,b) assert(a==b,("%s: LuanTTD %s vs RC1 %s"):format(tag,tostring(a),tostring(b))) end
local hashes={1,1,1,1}
local observations,checkpoints,services=0,0,0
local function observe(tick)
  observations=observations+1
  local front,tail=run.consist.parts[1],run.consist.parts[2]
  local f=s.fleet[1]
  local frame=S.road_motion_frame(s,f)
  local motion=f.road_speed_state or f.road_stop_motion
  local service=s.stock_ship_commercial.service
  local actor=assert(service.vehicles[16384+run.paid_clock])
  if tick==1503 then
    -- Preloaded numerical service state at the original save opening.
    -- This first tick draws no rating/cargo work for these two platforms.
    for i,id in ipairs({west,east}) do
      local g=ref.train_goods[i+1]
      local station=assert(service.stations[16384+id])
      station.time_since_load,station.time_since_unload,station.rating_phase=g[1],g[2],(g[9]+1)%185
      local rate=station.passenger_rating_state
      rate.rating,rate.last_age,rate.last_speed,rate.time_since_pickup=g[3],g[4],g[5],g[6]
      station.passenger_fraction=g[7]
      rate.has_rating=math.floor(g[8]/2)%2==1
    end
    actor.cargo_age_counter=ref.train[2].cargo_age_counter-1
  end
  hashes[1]=hash(hashes[1],tick,unpack(s.passenger_rating_rng))
  if frame then
    hashes[2]=hash(hashes[2],tick,frame[4]-1,frame[1]-16,frame[2]-16,S.stock_road_frame_z(s,frame),frame[3],
      motion.progress,f.road_speed_state and motion.speed or 0,motion.subspeed)
  else
    assert(motion.depot and f.depot and f.last_depot_entry_tick==tick)
    hashes[2]=hash(hashes[2],tick,f.depot-1,-1,-1,-1,-1,motion.progress,0,motion.subspeed)
  end
  if run.pending_depot_entry_tick==run.vehicle_ticks then
    services=services+1
    eq("stock automatic train depot arrival",tick,sample.services[services])
    assert(front.hidden and tail.hidden and h.breakdown_chance==0)
  end
  hashes[3]=hash(hashes[3],tick,front.tile-1,front.pose.x-16,front.pose.y-16,run.speed,run.subspeed,run.progress,
    h.reliability,h.breakdown_ctr,h.breakdown_chance,actor.units,
    tail.tile-1,tail.pose.x-16,tail.pose.y-16)
  for n,station in ipairs({s.stations[1],s.stations[2],service.stations[16384+west],service.stations[16384+east]}) do
    local wait=0
    for _,packet in ipairs(station.stock.passenger or {}) do wait=wait+packet.units end
    hashes[4]=hash(hashes[4],tick,n-1,wait,station.passenger_fraction or 0,station.passenger_rating_state.rating)
  end
  local expected=sample.digest[tick]
  if expected then
    for i,want in ipairs(expected) do eq("mixed baseline digest "..i.." at "..tick,hashes[i],want) end
  end
end
local Rebuild=m("openttd/town_rebuild")
local function check_town(tick)
  local expected=sample.checks[tick]
  if not expected then return end
  checkpoints=checkpoints+1
  local t=s.stock_town_growth.towns[1]
  for i,key in ipairs({"grow_counter","growth_rate","time_until_rebuild"}) do eq(key,t[key],expected.town[i]) end
  for id,name in pairs({[0]="passenger",[2]="mail"}) do
    for i,k in ipairs({"new_max","new_act","old_max","old_act"}) do eq(name.." "..k,t.supplied[name][k],expected.supply[id][i]) end
  end
  local map=1
  for id,tile in ipairs(s.tiles) do
    if tile.source_house then
      local house=tile.source_house
      map=hash(map,id-1,3,house.id,house.completed and 1 or 0,house.stage,house.counter,Rebuild.age(house,S.date(s)),
        assert(house.random_bits))
    elseif tile.road_bits and tile.build~="road_depot" and not tile.station then
      map=hash(map,id-1,2,tile.road_bits,(tile.road_town or 1)-1)
    end
  end
  eq("town houses/roads at "..tick,map,expected.map)
  local carrier=s.stock_ship_commercial.service.vehicles[16384+run.paid_clock]
  local paid=(s.companies[owner].paid_units or 0)
  local pending=s.fleet[1].load_state
  if pending and pending.payment then paid=paid+pending.payment.delivered end
  pending=carrier.load_state
  if pending and pending.payment then paid=paid+pending.payment.delivered end
  eq("accounted passenger deliveries at "..tick,paid,expected.paid)
end
for day=1,362 do
  if day==29 or day==88 or day==154 or day==312 then
    s=F.reopen(s,true,ref.service_options)
    m("campaign_authority_runtime")(S,mod,s,cap)
    run=assert(s.stock_rail_dispatch.runs[1]);h=assert(run.stock_fault)
  end
  S.daily(s,nil,observe)
  check_town(s.passenger_house_clock.counter)
end
assert(observations==26788 and checkpoints==12 and services==2)
print("PASS RC1 operating bus and train town, 26,788 ticks, twelve monthly observations, two returns to depot and four packed reopens")
