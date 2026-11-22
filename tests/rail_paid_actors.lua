-- SPDX-License-Identifier: GPL-2.0-only
-- Same stock station clock, two independently persisted carried rows.
local function mod(path) return dofile("mods/bayline/"..path..".lua") end
local P,Income,Rating=mod("openttd/passengers"),mod("openttd/income"),mod("openttd/station_rating")
local Queue=mod("station_rating_runtime")(nil,Rating,P)
local Catchment=mod("openttd/station_catchment")(P,Rating,
  mod("road_station_service")().house_passenger_acceptance,mod("road_mail_runtime")().house_acceptance)
local S=mod("passenger_station_service")(Catchment,P,Income,Rating,Queue,
  mod("road_loading_runtime"),mod("openttd/loading_timing"))
local function key(x) return 0x4000+x end
local Actors=mod("rail_paid_actors")(S,key)
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local d={}
  for k,v in pairs(t) do d[k]=clone(v) end
  return d
end
local state={service=S.new(1751),rail_serial=key(7)}
local A={id=1,fleet_id=41,owner="Coast",paid_clock=7,paid_build_year=1950,
  max_track_speed=64,total_length=16,station=1,paired={first=1,second=2,arrivals=1}}
local B={id=2,fleet_id=52,owner="Coast",paid_clock=9,paid_build_year=1950,
  max_track_speed=64,total_length=16,station=1,paired={first=1,second=3,arrivals=1}}
local function at(x,y) return y*64+x end
local ctx={select_goods=false,width=64,height=16,xy=function(i)return i%64,math.floor(i/64)end,year=function()return 1950 end}
function ctx.house_at(x,y)
  if (x==4 or x==21 or x==41) and y==4 then return {id=0,town=x,completed=true} end
end
for i,x in ipairs({4,21,41}) do
  local tiles={}
  for dx=0,3 do tiles[#tiles+1]={x=x+dx,y=5,kind="rail"} end
  S.station(state.service,{id=key(i),town=x,owner="Coast",tiles=tiles},ctx)
end
S.vehicle(state.service,{id=key(7),owner=A.owner,mode="rail",length=16,speed=64,built=1950})
S.vehicle(state.service,{id=63,owner=A.owner,mode="ship",speed=64,built=1950})
local t,fare,boarded,delivered=0,{},{},{}
local function step(actors,action)
  t=t+1
  Actors.controls(state,actors)
  local ready,events=S.pre_motion_tick(state.service,t,ctx)
  local mark={}
  for _,id in ipairs(ready) do mark[id]=true end
  local api=Actors.callbacks(state,mark,ctx,t,events)
  if action then action(api) end
  for _,r in ipairs(actors) do
    if api.leave(r) then assert(not api.leave(r)) end
  end
  assert(S.post_motion_tick(state.service,t))
  for _,e in ipairs(events) do
    if e.kind=="fare" then fare[e.vehicle]=(fare[e.vehicle] or 0)+e.amount end
    if e.kind=="board" then boarded[e.vehicle]=(boarded[e.vehicle] or 0)+e.units end
    if e.kind=="deliver" then delivered[e.vehicle]=(delivered[e.vehicle] or 0)+e.units end
  end
end
local function improve_queues()
  assert(S.produce(state.service,4,4,128,4,ctx)>80)
  assert(S.produce(state.service,21,4,100,21,ctx)>0)
  assert(S.produce(state.service,41,4,100,41,ctx)>0)
end
-- Existing singleton owns a live loading row when the code is upgraded.
do
  t=1
  local _,events=S.pre_motion_tick(state.service,t,ctx)
  improve_queues()
  assert(S.begin(state.service,key(7),key(1),1,at(5,5),{platform_tiles=2},t,ctx,events))
  assert(S.post_motion_tick(state.service,t))
end
local row=state.service.vehicles[key(7)]
local function build(r)return r.paid_build_year end
local function no_withdraw() error("An active paid train or unrelated transport was removed") end
Actors.reconcile(state,{A,B},ctx,t+1,build,no_withdraw)
assert(state.rail_serial==key(7) and state.rail_serials[key(7)] and state.rail_serials[key(9)])
assert(state.service.vehicles[key(7)]==row and row.visit==1 and row.load_state)
step({A,B},function(api)
  assert(api.arrive(B,at(7,5),2))
  assert(api.arrive(B,at(7,5),2)) -- duplicated callback is idempotent
end)
local origin=state.service.stations[key(1)]
assert(table.concat(origin.loading_order,",")==key(7)..","..key(9))
local reloaded=false
for _=1,1300 do
  step({A,B})
  local a,b=state.service.vehicles[key(7)],state.service.vehicles[key(9)]
  if not reloaded and a.load_state and b.load_state and a.units>0 and b.units>0 then
    reloaded=true;state=clone(state)
    Actors.reconcile(state,{A,B},ctx,t+1,build,no_withdraw)
    assert(a.units==state.service.vehicles[key(7)].units and b.units==state.service.vehicles[key(9)].units)
  end
  if not a.load_state and not b.load_state then break end
end
assert(reloaded and boarded[key(7)]==40 and boarded[key(9)]==40)
A.station,B.station=2,3
A.paired.arrivals,B.paired.arrivals=2,2
step({A,B},function(api)
  assert(api.cargo_count(A)==40 and api.cargo_count(B)==40)
  assert(api.arrive(A,at(22,5),2))
  assert(api.arrive(B,at(42,5),2))
end)
for _=1,900 do
  step({A,B})
  local a,b=state.service.vehicles[key(7)],state.service.vehicles[key(9)]
  if not a.load_state and not b.load_state then break end
end
assert(delivered[key(7)]==40 and delivered[key(9)]==40 and fare[key(7)]>0 and fare[key(9)]>fare[key(7)])
assert(state.service.vehicles[key(7)].units==0 and state.service.vehicles[key(9)].units==0)
assert(S.waiting(state.service,key(2))>0 and S.waiting(state.service,key(3))>0) -- did not reload at terminal
local withdrawn=0
Actors.reconcile(state,{B},ctx,t+1,build,function(events,owner)
  assert(#events==0 and owner=="Coast");withdrawn=withdrawn+1
end)
assert(withdrawn==1 and not state.service.vehicles[key(7)] and state.service.vehicles[key(9)] and state.service.vehicles[63])
print(("PASS: two real stock coaches and paid rows (40/$%d and 40/$%d), singleton migration, shared queue and independent reload"):
  format(fare[key(7)],fare[key(9)]))
