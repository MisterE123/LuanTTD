-- Source stock stations and actual ShipMotion/YAPF across an ordinary
-- route, one original mine offer clock and competing truck/rail queues.
local root="mods/bayline/"
local function mod(n) return dofile(root..n..".lua") end
local S,Terrain,Track=mod("sim"),mod("openttd/terrain"),mod("openttd/rail_track")
local Water=mod("openttd/ship_follow")(Track)
local Facilities=mod("openttd/ship_facilities")(Track,Water)
local Network=mod("ship_network")(S,Terrain,Water,Facilities)
local Y=mod("openttd/ship_yapf")(Track,Water,mod("openttd/yapf_road_search"))
local Move=mod("openttd/ship_motion")(Track,Water)
local Run=mod("ship_preview_run")(Network,Track,Water,Y,Move,mod("openttd/ship_regions"),
  {width=S.W,height=S.H,x0=1,z0=1})
local P,Income,Rating=mod("openttd/passengers"),mod("openttd/income"),mod("openttd/station_rating")
local Catch=mod("openttd/station_catchment")(P,Rating)
local Coal=mod("openttd/coal_industry")(P,Rating,Catch,Income)
local Station,Timing,Loading=mod("station_rating_runtime")(S,Rating,P),mod("openttd/loading_timing"),mod("road_loading_runtime")
local Rail=mod("rail_coal_service")(S,Coal,Catch,mod("openttd/rail_roster"),P,Rating,Station,Income,Loading,Timing)
local R=mod("openttd/ship_roster")
local Service=mod("ship_coal_service")(S,Coal,Catch,R,P,Rating,Station,Income,Loading,Timing)
assert(R.quote(1).capacity==160 and R.quote(1).total==33007 and R.quote(5).refit==0)
assert(not R.quote(0) and not R.quote(3))
local s=S.new(1751)
local function terrain()
  s.corner_grid=Terrain.new(S.W,S.H,function(x) return x<9 and 1 or 0 end)
  for i,t in ipairs(s.tiles) do
    local x=S.xy(i)
    t.site=nil;t.owner=nil;t.wood=nil;t.house=nil;t.build=nil
    t.terrain=x>=9 and "water" or "grass"
  end
end
terrain()
s.ship_paid_service,s.road_stock_house_supply=true,true
local from=assert(Network.build(s,"Port", "dock", S.id(8,9)))
local to=assert(Network.build(s,"Port", "dock", S.id(8,27)))
local depot=assert(Network.build(s,"Port", "depot", S.id(12,10),0))
local foreign=assert(Network.build(s,"Rival", "dock", S.id(8,36)))
local built=S.date(s)
local state=Service.new()
local events,paid,received,charges,tick={},0,0,0,0
local mine,power=Coal.new("coal_mine",1,2,7,{original=true,completed=true}),
  Coal.new("power_station",2,2,25,{original=true,completed=true})
s.stock_coal_industries={[1]=mine,[2]=power}
local function clone(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local t={};for k,v in pairs(x) do t[k]=clone(v) end;return t
end
local road={id=1,tile=S.id(4,9),mode="road",owner="Port",tiles={{x=3,y=8,kind="truck"}},stock={coal={}}}
local rail={id=0x4001,tile=S.id(4,8),mode="rail",owner="Rival",tiles={{x=3,y=7,kind="rail"}},stock={coal={}}}
local function extend(b,st)
  local covers={}
  for _,v in ipairs(st) do covers[v.id]=Catch.build(v,S.W,S.H) end
  b.extend(st,covers)
  return st,covers
end
local b,where
local function bind()
  where={}
  for _,ind in pairs(s.stock_coal_industries) do for _,t in ipairs(ind.tiles) do where[64*t.z+t.x]={ind,t} end end
  mine,power=s.stock_coal_industries[1],s.stock_coal_industries[2]
  b=Service.bind(s,state,{board=Network.board(s),emit=function(e) events[#events+1]=e end,
    credit=function(_,who,m,n) assert(who=="Port" and n>0);paid=paid+m end,
    received=function(_,plant,n) assert(plant==power);received=received+n end,
    charge_fixed=function(_,who,n) assert(who=="Port");charges=charges+n end})
end
bind()
assert(not b.vehicle({engine=206,cargo=1,id=3,built=built,owner="Port"}))
assert(not b.vehicle({engine=211,cargo=5,id=3,built=built,owner="Port"}))
assert(b.vehicle({engine=211,cargo=1,id=3,built=built,owner="Port"}))
assert(not b.report(from.id).accepts and b.report(to.id).accepts and not b.report(foreign.id).accepts)
-- Competitors in one authoritative allocation and road/rail/dock names
-- live in non-overlapping ordinary StationIDs. Preview this without
-- modifying the actual cargo ledgers of the voyage.
do
  local test=Service.bind(s,Service.new(),{board=Network.board(s)})
  local t,c=extend(test,{clone(road),clone(rail)})
  for _,v in ipairs(t) do
    local g=Coal.goods(v);g.rating=127;Coal.observe_loading(v,{mode=v.mode,max_speed=96,build_year=built},10,built)
  end
  local total=Rail.distribute(mine,16,t,c,{})
  assert(total==8 and Coal.waiting(t[1])==2 and Coal.waiting(t[2])==4 and Coal.waiting(t[3])==2)
  assert(t[3].stock.coal[1].origin_tile==nil)
end
-- Configure a fresh local instance of the real stock boat controller with
-- the #211 engine for QA. Existing passenger singleton stays untouched.
Run.engine=R
assert(Run.start(s,"Port",depot.id,from.id,to.id))
assert(Run.current(s).vehicle.max_speed==48)
local landscape={cursor=1,tick=0}
local function step()
  tick=tick+1
  if tick%74==1 then
    local n=b.economy_day(tick)
    assert(n==0 or n==R.running_fixed(74))
    assert(b.economy_day(tick)==0)
  end
  assert(b.loading_tick(tick))
  assert(not b.loading_tick(tick))
  local p=Run.advance_paid(s,{
    leave=function(run) return b.leave(run.arrivals,tick) end,
    arrive=function(run)
      local local_id=run.last_dock
      assert(not b.arrive(local_id,run.arrivals,tick,s.stock_ship_stations[local_id].water,"no_load"))
      local order=local_id==from.id and "full" or "no_load"
      local ok,why=b.arrive(local_id,run.arrivals,tick,run.last_berth,order)
      assert(ok,why)
      assert(b.arrive(local_id,run.arrivals,tick,run.last_berth,order)==ok)
      return true
    end,
  })
  assert(p.phase~="blocked",p.failure)
  assert(b.after_motion(tick));assert(not b.after_motion(tick))
  for _,st in ipairs(b.stations) do
    if tick%185==0 then Rating.increment_station_timers(st);b.rating(st,tick) end
    if tick%250==0 then b.update_acceptance(st) end
  end
  landscape.tick=tick
  Coal.landscape_tick(landscape,6,6,function(tile)
    local ref=where[tile]
    if not ref then return end
    Coal.tile_loop(ref[1],ref[2],{},function(ind,n)
      local st,c=extend(b,{road,rail})
      return Rail.distribute(ind,n,st,c,{})
    end)
  end)
  Coal.production_tick(mine,{})
  Coal.production_tick(power,{})
end
local function await(f,n)
  for _=1,n do if f() then return end;step() end
  assert(f(),"timeout "..tick.." phase "..Run.current(s).phase)
end
await(function() return Run.current(s).arrivals==1 end,2500)
assert(Run.current(s).last_berth~=from.water and state.vehicle.units==0)
local loading=state.vehicle.load_state
assert(loading.full)
for _=1,30 do step() end
assert(state.vehicle.units==0 and state.vehicle.load_state,"departed before first real mine offer")
-- Introduce a real road and rail service loading observation so the
-- shared industry starts splitting despite only one moving ship here.
Coal.observe_loading(road,{mode="road",max_speed=96,build_year=built},20,built)
Coal.observe_loading(rail,{mode="rail",max_speed=64,build_year=built},30,built)
await(function() return state.vehicle.units>=10 end,10000)
assert(state.vehicle.units<160 and state.vehicle.load_state and state.vehicle.load_state.ticks<=10)
do
  local lost,ledger=clone(s),clone(state)
  lost.tiles[from.water].ship=nil
  local missing=Service.bind(lost,ledger,{board=Network.board(lost),credit=function() error("Ghost payment") end})
  assert(not missing.report(from.id))
  local ok,why=missing.loading_tick(tick+1)
  assert(ok==nil and why=="COAL_SHIP_BERTH_LOST")
  assert(ledger.loading_tick==tick and ledger.vehicle.units==state.vehicle.units and ledger.vehicle.load_state)
end
s,state=clone(s),clone(state);bind()
await(function() return received>=10 end,24000)
assert(state.vehicle.load_state.no_load and state.vehicle.units==150 and paid==0)
assert(Run.current(s).last_berth~=to.water)
s,state=clone(s),clone(state);bind()
await(function() return state.vehicle.delivered==160 end,5000)
await(function() return Run.current(s).arrivals==3 end,5000)
-- Reaching the real berth ends pathfinding, not movement. The next
-- within-tile stock step loads instead of triggering a reverse/replan.
assert(received==160 and state.vehicle.revenue==paid and paid==1769 and charges==474006)
assert(tick==15284)
assert(power.accepted.waiting==0 and power.was_cargo_delivered and state.vehicle.load_state.full)
assert(Coal.waiting(road)>0 and Coal.waiting(rail)>0)
local board,payout,deliver,distance,older=0,0,0,nil,0
for _,e in ipairs(events) do
  if e.visit==1 and e.kind=="board" then assert(e.units<=10);board=board+e.units end
  if e.kind=="fare" then assert(e.visit==2);payout=payout+1 end
  if e.kind=="deliver" then
    assert(e.visit==2 and e.units<=10 and e.station_local==to.id)
    distance=distance or e.distance;assert(e.distance==distance)
    older=math.max(older,e.age);deliver=deliver+e.units
  end
end
local start,finish
for _,e in ipairs(events) do
  if e.kind=="arrive" and e.visit==1 then start=e.tile end
  if e.kind=="arrive" and e.visit==2 then finish=e.tile end
end
assert(board==160 and deliver==160 and payout==1 and older==70)
assert(distance==S.distance(start,finish) and distance==18)
print(string.format("PASS: #211 true full-load/no-load stock-berth voyage with one mine clock, competing road/rail queues, two restores; %dt $%d over %d berth tiles, age up to %d, running %d/256",deliver,paid,distance,older,charges))
