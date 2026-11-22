-- Stock host clock/ledger integration. Only Run's motion is substituted;
-- rail depot/route mechanics have independent native probes. Physical rail
-- records and the road depot, Goods truck and rail station ledger are real.
local mod="mods/luanttd_core/"
local function m(name) return dofile(mod..name..".lua") end
local Sim,Terrain,Roster=m("sim"),m("openttd/terrain"),m("openttd/rail_roster")
local s=Sim.new(1751)
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_oil,s.road_junction_clearance,s.rail_owned_service=true,true,true
s.stock_rail_fleet={}
m("town_layout")(Sim,s)
s.corner_grid=m("terrain_preview")(Sim,Terrain,s)
local World=assert(Sim.mount_oil_world(s,Terrain,true))
assert(World.default_1751(s))
local at=Sim.id
local function platform(id,x,z)
  local raw={id=id,axis=0,owner="Rail",tiles={}}
  for dx=0,2 do
    local tile=at(x+dx,z)
    local t=s.tiles[tile]
    assert(not t.site and not t.stock_industry)
    raw.tiles[#raw.tiles+1]=tile
    t.rail_station_id,t.rail_station_axis,t.owner,t.rail_tracks=id,0,raw.owner,1
  end
  return raw
end
s.stock_rail_stations={[1]=platform(1,10,5),[2]=platform(2,11,17)}
local Run={}
function Run.current(w) return w.fixture end
function Run.current_paid(w,id)
  local r=w.fixture and w.fixture.runs[1]
  if r and (not id or id==r.fleet_id) then return r end
end
function Run.sample(r,part)
  local tile=r.consist.parts[part].tile
  return tile,tile,0,0
end
function Run.block_oil(w,why)
  local r=Run.current_paid(w)
  r.failure,r.phase,r.stopped=why,"blocked",true
  return {{kind="blocked",why=why}}
end
function Run.advance_paid(w,io)
  local r=Run.current_paid(w)
  if r.stopped then return {} end
  r.running_ticks_total=r.running_ticks_total+1
  r.cargo_onboard=io.cargo_count()
  if r.phase=="travel" then
    r.travel=r.travel-1
    if r.travel>0 then return {} end
    local parts=w.stock_rail_stations[r.station].tiles
    r.consist.parts={{tile=parts[2]},{tile=parts[3]}}
    r.freight.visits=r.freight.visits+1
    assert(io.arrive(r,parts[3]))
    r.phase="dwell"
    return {{kind="arrive",tile=parts[2]}}
  elseif r.phase=="dwell" and io.leave(r) then
    if r.station==r.freight.mine then r.station,r.phase,r.travel=r.freight.power,"travel",224
    else r.phase,r.stopped,r.freight.complete,r.freight.cycles="freight_complete",true,true,1 end
    return {{kind="leave",tile=r.consist.parts[1].tile}}
  end
  return {}
end
Sim.mount_paid_rail(s,Run)
assert(not Sim.rail_oil_active(s) and not Sim.rail_oil_stop_status(s,1))
s.rail_oil_service=true
s.stock_oil_frozen=true
assert(Sim.rail_oil_active(s))
assert(Sim.rail_oil_stop_status(s,1).sources[1]==World.BASE)
assert(Sim.rail_oil_stop_status(s,2).accepts and not Sim.rail_oil_stop_status(s,2).role)
assert(not Sim.rail_oil_designate(s,"Rail",1,"unload"))
assert(not Sim.rail_oil_designate(s,"Road",1,"load"))
s.stock_rail_stations[1].coal_role="load"
assert(not Sim.rail_oil_designate(s,"Rail",1,"load"))
s.stock_rail_stations[1].coal_role=nil
assert(Sim.rail_oil_designate(s,"Rail",1,"load"))
assert(Sim.rail_oil_designate(s,"Rail",2,"unload"))
assert(not Sim.rail_oil_validate(s,"Rail",2,1))
assert(Sim.rail_oil_validate(s,"Rail",1,2))
local roads={
  {{15,8},{12,8},{12,14},{14,14},{14,16},{18,16}},
  {{15,8},{15,12},{12,12}},{{18,16},{18,15},{14,15}},
}
for _,route in ipairs(roads) do for i=2,#route do
 assert(Sim.build(s,"Road","road",Sim.line(at(unpack(route[i-1])),at(unpack(route[i])))))
end end
local depot=at(11,12)
assert(Sim.build(s,"Road","road_depot",{depot}))
local intake,shop=at(16,16),at(14,8)
for _,tile in ipairs{intake,shop} do assert(Sim.build_truck_stop(s,"Road",tile)) end
local truck=assert(Sim.purchase(s,"Road","goods_truck","goods",nil,depot))
assert(Sim.add_order(s,"Road",truck,s.tiles[intake].station))
assert(Sim.add_order(s,"Road",truck,s.tiles[shop].station))
assert(Sim.toggle(s,"Road",truck))
local source=s.stock_rail_stations[1].tiles
local r={fleet_id=15,owner="Rail",stock_wagon=30,stock_engine=0,total_length=16,max_track_speed=64,
  paid_build_year=Sim.date(s),running_ticks_total=0,running_year_fp=1200000,
  freight={cargo="oil",mine=1,power=2,visits=0},phase="travel",travel=1,station=1,
  consist={parts={{tile=source[2]},{tile=source[3]}}}}
s.fixture={runs={r}}
s.rail_coal_service=true
local function copy(t)
  if type(t)~="table" then return t end
  local b={};for k,v in pairs(t) do b[k]=copy(v) end
  return b
end
local function attach(w)
  Sim.mount_paid_rail(w,Run)
  assert(Sim.mount_oil_world(w,Terrain,true))
end
local function day(w)
  Sim.daily(w)
  assert(w.passenger_house_clock.counter==w.stock_load_tick)
  if w.rail_oil_service then assert(w.stock_rail_oil.aged_tick==w.stock_load_tick) end
  assert(not Sim.rail_coal_status(w) and not Sim.rail_paid_status(w))
end
local function until_status(w,p)
  for _=1,350 do
    day(w)
    local z=assert(Sim.rail_oil_status(w))
    if p(z) then return z end
  end
  error("Never reached oil status")
end
local partial=until_status(s,function(q) return q.onboard>0 and q.onboard<30 and q.loading end)
assert(partial.boarded==partial.onboard and partial.fare==0 and partial.cargo_tile==source[3])
assert(select(1,Sim.rail_paid_pose(s,2,1,15))==source[3])
assert(not Sim.rail_paid_pose(s,2,1,77))
assert(#Sim.rail_paid_motion_events(s)==1)
local fault=copy(s)
attach(fault)
fault.stock_oil_industries[World.BASE+1].removed=true
day(fault)
local stopped=assert(Sim.rail_oil_status(fault))
assert(stopped.phase=="blocked" and stopped.onboard==partial.onboard and stopped.fare==0)
assert(#Sim.rail_oil_loading_events(fault)==0 and #Sim.rail_paid_motion_events(fault)==1)
s=copy(s);attach(s)
s.rail_oil_service=false
day(s)
local paused=Sim.rail_oil_status(s)
assert(paused.paused and paused.onboard==partial.onboard and paused.tick==partial.tick)
s.rail_oil_service=true
local done=until_status(s,function(q) return q.finished end)
local ledger=s.stock_oil_industries[World.BASE+1]
assert(done.delivered==30 and done.fare>0 and done.boarded==30 and done.onboard==0 and done.cycles==1)
assert(ledger.received.oil==30 and s.sites[ledger.site].received.oil==30)
assert(s.companies.Rail.paid_units==30 and s.companies.Rail.revenue==done.fare)
local amount,biggest=0,0
local ticks,by_tick={},{}
for _,e in ipairs(Sim.rail_oil_loading_events(s)) do
  if e.kind=="deliver" then
    assert(e.distance==13 and e.tile==s.stock_rail_stations[2].tiles[3])
    amount=amount+e.units
    if not by_tick[e.tick] then ticks[#ticks+1]=e.tick end
    by_tick[e.tick]=(by_tick[e.tick] or 0)+e.units
    biggest=math.max(biggest,by_tick[e.tick])
  end
end
assert(amount==30 and biggest==5 and #ticks==6)
for i=2,#ticks do assert(ticks[i]-ticks[i-1]==40) end
for _=1,25 do if s.fleet[truck].delivered>0 then break end;day(s) end
assert(s.fleet[truck].delivered>0 and s.fleet[truck].delivered<=30 and s.fleet[truck].revenue>0)
assert(ledger.received.oil==30 and s.companies.Rail.paid_units==30)
print(("PASS shared Sim clock/reload: 30,000 L by rail for $%d in six physical pulses; %d Goods delivered by road for $%d")
  :format(done.fare,s.fleet[truck].delivered,s.fleet[truck].revenue))
