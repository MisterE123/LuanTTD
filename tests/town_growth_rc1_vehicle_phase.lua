-- Native generated crossing with ordinary purchased stock. Implements
-- the RC1 Vehicle::Iterate order, not a road-first simulation pass.
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
local cross=Sim.id(47,56)
local north,south=Sim.id(47,54),Sim.id(47,57)
assert(Sim.build(s,owner,"road",Sim.line(north,Sim.id(47,58))))
assert(Sim.build(s,owner,"road_station",{north}))
assert(Sim.build(s,owner,"road_station",{south}))
local home=Sim.id(46,55)
assert(Sim.build(s,owner,"road_depot",{home}))
local west_road,east_road=Sim.id(41,58),Sim.id(45,58)
assert(Sim.build(s,owner,"road",Sim.line(west_road,east_road)))
local other_yard=Sim.id(43,59)
assert(Sim.build(s,owner,"road_depot",{other_yard}))
assert(Sim.build(s,owner,"road_station",{west_road}))
assert(Sim.build(s,owner,"road_station",{east_road}))
rail({tool="track",first=Sim.id(43,56),last=cross-1,track=T.X})
rail({tool="track",first=cross+1,last=D-1,track=T.X})
rail({tool="crossing",first=cross})
rail({tool="depot",first=D,direction=T.NE})
for _,id in ipairs({L,B}) do
  rail({tool="station",first=id,last=id,axis=0,length=1,tracks=1,separate=true,drag=true})
end
local function buy_bus(at)
  return assert(command("road_buy",{engine="bus",cargo="passenger",depot=at,cost=Sim.vehicle_offer(s,"bus").cost}))
end
local function at_yard(op,stock)
  local _,q=check(A.rail_assembly(owner,D),"assembly "..op)
  command("rail_assembly",{token=q.token,operation=op,stock=stock})
end
local expected,slot={},0
while #expected<4 do
  if not (s.stock_effect_vehicles and s.stock_effect_vehicles[slot]) then expected[#expected+1]=slot end
  slot=slot+1
end
local low=buy_bus(home)
at_yard("engine",0)
local high=buy_bus(other_yard)
at_yard("wagon",27)
local id,unit=next(s.stock_rail_fleet.units)
assert(unit.parts[1].stock_pool_id==expected[2] and unit.parts[2].stock_pool_id==expected[4])
assert(s.fleet[low].stock_pool_id==expected[1] and s.fleet[high].stock_pool_id==expected[3])
local a,b=assert(s.tiles[north].station),assert(s.tiles[south].station)
assert(s.stations[a].stock_station_id==0 and s.stations[b].stock_station_id==1)
for _,route in ipairs({{low,a,b},{high,assert(s.tiles[west_road].station),assert(s.tiles[east_road].station)}}) do
  local bus,first,second=unpack(route)
  assert(Sim.add_order(s,owner,bus,first,"normal"))
  assert(Sim.add_order(s,owner,bus,second,"normal"))
  assert(Sim.toggle(s,owner,bus))
end
local w,e=s.tiles[L].rail_station_id,s.tiles[B].rail_station_id
command("transport_start",{mode="rail",vehicle=id,first=w,second=e})
local rail_run=assert(s.stock_rail_dispatch.runs[1])
local proof,road_cross,rail_cross,high_moves,gate_wait=0,0,0,0,0
local before,after
local engine=R.rail.run
local advance=engine.advance_services
engine.advance_services=function(world,handlers,road_until)
  assert(world==s and road_until,"Real world should interleave road with rail")
  local first,last=s.fleet[low].road_fault,s.fleet[high].road_fault
  local early,late=first.tick_counter,last.tick_counter
  local train=rail_run.vehicle_ticks or rail_run.ticks
  before,after=early,late
  return advance(world,handlers,function(slot)
    assert(slot==expected[2] and (rail_run.vehicle_ticks or rail_run.ticks)==train)
    road_until(slot)
    assert(first.tick_counter==(early+1)%256 and last.tick_counter==late,
      "Low-slot bus advances before both train passes, high-slot bus waits")
    proof=proof+1
  end)
end
for _=1,65 do
  R.day(function()
    local early,late=s.fleet[low].road_fault,s.fleet[high].road_fault
    assert(early.tick_counter==(before+1)%256 and late.tick_counter==(after+1)%256)
    assert(not rail_run.failure,tostring(rail_run.failure))
    for _,bus in ipairs({low,high}) do
      local v=s.fleet[bus]
      local f=Sim.road_motion_frame(s,v)
      if f and f[4]==cross then road_cross=road_cross+1 end
      if v.road_speed_state and v.road_speed_state.waiting=="crossing" then gate_wait=gate_wait+1 end
    end
    if rail_run.consist.parts[1].tile==cross then rail_cross=rail_cross+1 end
    local bus=s.fleet[high]
    if bus.road_speed_state and bus.road_speed_state.speed>0 then high_moves=high_moves+1 end
  end)
end
assert(proof==65*74 and road_cross>0 and rail_cross>0 and high_moves>0 and gate_wait>0 and s.companies[owner].paid_units>0)
print(("PASS real mixed rail/road crossing, two buses bracketing train's physical ID on %d ticks, %d/%d road/rail samples on crossing, %d barrier waits")
  :format(proof,road_cross,rail_cross,gate_wait))
