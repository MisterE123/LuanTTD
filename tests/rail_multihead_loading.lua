-- SPDX-License-Identifier: GPL-2.0-only
-- Two genuine packet lists, one stock station visit. Includes full-load
-- reservation and replay independent of the real native order fixture.
local function m(path) return dofile("mods/luanttd_core/"..path..".lua") end
local P,Income,Rating=m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating")
local Queue=m("station_rating_runtime")(nil,Rating,P)
local Catch=m("openttd/station_catchment")(P,Rating,
  m("road_station_service")().house_passenger_acceptance,m("road_mail_runtime")().house_acceptance)
local S=m("passenger_station_service")(Catch,P,Income,Rating,Queue,m("road_loading_runtime"),m("openttd/loading_timing"))
local function copy(t)
  if type(t)~="table" then return t end
  local b={};for k,v in pairs(t) do b[k]=copy(v) end
  return b
end
local function tile(x) return 5*64+x end
local ctx={width=64,height=16,xy=function(i)return i%64,math.floor(i/64)end,year=function()return 1960 end,
  house_at=function(x,y)
    if y==4 and (x==4 or x==24) then return {id=0,town=x,completed=true} end
  end}
local state=S.new(1751)
local with_coach=arg[1]=="coach"
local bodies=with_coach and 3 or 2
local capacity=with_coach and 116 or 76
local initial=with_coach and 100 or 65
local leave_tick=with_coach and 482 or 442
for id,x in ipairs{4,24} do
  S.station(state,{id=id,owner="A",town=x,tiles={{x=x,y=5,kind="rail"},{x=x+1,y=5,kind="rail"}}},ctx)
end
local function enqueue(n)
  table.insert(state.stations[1].stock.passenger,{origin_station=1,age=0,units=n,source_type="town",source=4})
end
local function v() return state.vehicles[17] end
S.vehicle(state,{id=17,owner="A",mode="rail",engine=11,length=with_coach and 24 or 16,coach=with_coach,built=1960,speed=112})
local t,results=0,{}
local function step(fn)
  t=t+1
  local leaves,events=S.pre_motion_tick(state,t,ctx)
  if fn then fn(events) end
  for _,id in ipairs(leaves) do assert(id==17 and S.leave(state,id,v().visit,t,ctx,events)) end
  for _,e in ipairs(events) do results[#results+1]=e end
  assert(S.post_motion_tick(state,t,ctx))
  assert(not S.post_motion_tick(state,t,ctx))
end
local function begin(place,visit,front,rear,order,events)
  order.platform_tiles=2
  local bad,why=S.begin(state,17,place,visit,front,order,t,ctx,events)
  assert(not bad and why=="ACTUAL_RAIL_BODY_TILES_REQUIRED")
  order.cargo_tiles=with_coach and {front,(front+rear)/2,rear} or {front,rear}
  local l=assert(S.begin(state,17,place,visit,front,order,t,ctx,events))
  assert(S.begin(state,17,place,visit,front,order,t,ctx,events)==l)
  if with_coach then
    order.cargo_tiles[2]=rear
    local no,err=S.begin(state,17,place,visit,front,order,t,ctx,events)
    assert(not no and err=="DUPLICATE_OR_STALE_VISIT")
  end
  assert(#state.stations[place].loading_order==1)
end
enqueue(initial)
step(function(events) begin(1,1,tile(4),tile(3+bodies),{full=true},events) end)
step()
local a,b=v().carrying_parts[1],v().carrying_parts[bodies]
assert(a.units==5 and b.units==5 and a.load_state.reserved_units==33 and b.load_state.reserved_units==(with_coach and 33 or 22))
local remaining=initial-5*bodies
assert(v().load_state.reserved_units==remaining and S.waiting(state,1)==remaining and select(2,S.waiting(state,1))==0)
assert(a.batches[1].origin_tile==tile(4) and b.batches[1].origin_tile==tile(3+bodies))
if with_coach then
  local c=v().carrying_parts[2]
  assert(c.units==5 and c.load_state.reserved_units==19,"Source reserves the linked rear before the interposed coach")
  assert(results[#results-2].part==1 and results[#results-1].part==2 and results[#results].part==3,
    "Source loading scans physical order even though reservation uses linked order")
end
state=copy(state)
for _=1,318 do step() end
assert(v().load_state and not v().load_state.finished and v().units==initial)
assert(v().carrying_parts[1].units==38 and v().carrying_parts[bodies].units==(with_coach and 38 or 27))
enqueue(capacity-initial)
while v().load_state do assert(t<700);step() end
assert(v().units==capacity and v().boarded==capacity and S.waiting(state,1)==0 and t==leave_tick)
a,b=v().carrying_parts[1],v().carrying_parts[bodies]
assert(a.units==38 and b.units==38 and a.cargo_age_counter==b.cargo_age_counter)
for _,body in ipairs(v().carrying_parts) do
  for _,p in ipairs(body.batches) do assert(p.origin_tile==tile(3+body.part) and p.age>=1) end
end
for _=1,200 do step() end
step(function(events) begin(2,2,tile(23+bodies),tile(24),{action="unload"},events) end)
step()
assert(v().units==capacity-5*bodies and v().carrying_parts[1].units==33 and v().carrying_parts[bodies].units==33)
if with_coach then assert(v().carrying_parts[2].units==35) end
assert(not state.companies.A,"No separate body can settle the shared visit prematurely")
state=copy(state)
while v().load_state do assert(t<1200);step() end
local chunks,units,desired,fares={},0,0,0
for _,e in ipairs(results) do
  if e.kind=="deliver" then
    local d=21+bodies-2*e.part
    assert(e.distance==d and e.age>0 and e.tile==tile(24+bodies-e.part))
    local payment=Income.regular(e.units,d,e.age,unpack(Income.temperate.passenger))
    assert(e.amount==payment)
    desired=desired+payment;units=units+e.units
    chunks[e.tick]=(chunks[e.tick] or 0)+e.units
  elseif e.kind=="fare" then
    fares=fares+1
    assert(e.amount==desired and e.units==capacity and not e.part)
  end
end
assert(units==capacity and fares==1 and v().delivered==capacity and v().route_profit==desired and v().units==0)
assert(state.companies.A.units==capacity and state.companies.A.revenue==desired and state.towns[24]==capacity)
for i=0,7 do assert(chunks[leave_tick+202+40*i]==(i==7 and (capacity-35*bodies) or 5*bodies)) end
print(("PASS: full-load %d cargo stores, all %d tickets/distance/age, distinct origins, midscan copies and one fare $%d")
  :format(bodies,capacity,desired))
