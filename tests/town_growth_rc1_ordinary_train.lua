-- New, ordinary generated board. No fixture seeding of train ID, cargo,
-- reliability, countdown, pose, order, public road, tree or RNG.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local file_host={
  settings={get=function() return nil end},
  get_dir_list=function(path)
    local names={}
    local p=assert(io.popen("ls -1 "..path))
    for n in p:lines() do names[#names+1]=n end
    p:close();return names
  end,
}
local G=m("campaign_generation")(file_host,mod,Sim,m("world_setup"))
local s=G.run({width=64,depth=64,seed=1751,relief=0,sea=0,coast=0,rivers=0,towns=4,custom_towns=2})
assert(s.stock_engine_startup_seed and s.stock_pool_authority and s.passenger_house_clock)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
s.road_mail,s.road_junction_clearance=true,true
local owner="Ordinary service QA"
Sim.company(s,owner)
local R=m("campaign_authority_runtime")(Sim,mod,s,cap)
local A=m("campaign_authority_endpoint")(Sim,R)
local revision
local function check(r,where) revision=r.revision;return assert(r.ok,where..": "..tostring(r.why)),r.value end
local function command(key,c)
  c.kind,c.revision=key,revision
  local _,v=check(A.command(owner,c),key)
  return v
end
local function rail(req)
  local _,q=check(A.rail_quote(owner,req),req.tool)
  return command("rail_commit",{token=q.token})
end
local T=m("openttd/rail_track")
local L,B,D=Sim.id(44,56),Sim.id(48,56),Sim.id(50,56)
rail({tool="track",first=Sim.id(43,56),last=D-1,track=T.X})
rail({tool="depot",first=D,direction=T.NE})
for _,id in ipairs({L,B}) do
  rail({tool="station",first=id,last=id,axis=0,length=1,tracks=1,separate=true,drag=true})
end
local roe=Sim.id(12,42)
assert(Sim.build(s,owner,"road_depot",{roe}))
local function purchase_road()
  return command("road_buy",{engine="bus",cargo="passenger",depot=roe,cost=Sim.vehicle_offer(s,"bus").cost})
end
local function at_yard(op,stock)
  local _,q=check(A.rail_assembly(owner,D),"assembly "..op)
  command("rail_assembly",{token=q.token,operation=op,stock=stock})
end
local w,e=s.tiles[L].rail_station_id,s.tiles[B].rail_station_id
local first,second=s.stock_rail_stations[w],s.stock_rail_stations[e]
assert(first.stock_station_id~=nil and second.stock_station_id==first.stock_station_id+1)
local rng={passenger_rating_rng={unpack(s.passenger_rating_rng)}}
local engine_bits=Sim.stock_random_u32(rng)%65536
at_yard("engine",0)
local road_bits=Sim.stock_random_u32(rng)%65536
local bus=assert(purchase_road())
local wagon_bits=Sim.stock_random_u32(rng)%65536
at_yard("wagon",27)
assert(s.passenger_rating_rng[1]==rng.passenger_rating_rng[1] and s.passenger_rating_rng[2]==rng.passenger_rating_rng[2])
local id,ownership=next(s.stock_rail_fleet.units)
local physical=ownership.parts
assert(#physical==2 and physical[1].stock_id==0 and physical[2].stock_id==27)
assert(physical[1].stock_pool_id==0 and physical[2].stock_pool_id==2 and s.fleet[bus].stock_pool_id==1)
assert(physical[1].stock_vehicle_random_bits==engine_bits and physical[2].stock_vehicle_random_bits==wagon_bits and
  s.fleet[bus].stock_vehicle_random_bits==road_bits)
assert(Sim.sell(s,owner,bus))
local rebought=purchase_road()
assert(rebought~=bus and s.fleet[rebought].stock_pool_id==1)
for _=1,2 do R.day() end
assert(physical[1].stock_fault.age==2 and physical[1].stock_fault.reliability<physical[1].reliability)
command("transport_start",{mode="rail",vehicle=id,first=w,second=e})
local run=assert(s.stock_rail_dispatch.runs[1])
assert(run.stock_fault and run.stock_pool_id==0 and run.stock_live_procurement and run.stock_train_service_opts.interval==150)
local arrival,departure
local function observe(tick)
  if run.pending_depot_entry_tick==run.vehicle_ticks then
    assert(not arrival and run.consist.parts[1].hidden and run.consist.parts[2].hidden)
    assert(run.stock_fault.breakdown_chance==0 and run.stock_fault.date_of_last_service>Sim.engine_calendar.date(1950,6,1))
    arrival=tick
  elseif arrival and not departure and run.phase=="running" then departure=tick end
end
local Codec=m("packed_campaign")
local function reopen()
  s=Codec.decode(Codec.encode(s));R=m("campaign_authority_runtime")(Sim,mod,s,cap)
  run=assert(s.stock_rail_dispatch.runs[1])
end
local checked_inbound
for day=1,190 do
  R.day(observe)
  assert(not run.failure, tostring(run.failure))
  if run.service_depot and not checked_inbound then reopen();checked_inbound=true end
  if departure then break end
end
assert(arrival and departure and checked_inbound)
assert(run.stock_random_parts[1].stock_waiting_random_triggers%4>=2)
assert(run.stock_random_parts[2].stock_waiting_random_triggers%4>=2)
assert((s.companies[owner].paid_units or 0)>0)
print(("PASS original world, paid ordinary train: shared purchase slots 0/1/2, real cargo/depot draws, servicing tick %d, departed %d, %d passengers")
  :format(arrival,departure,s.companies[owner].paid_units))
