local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,H,P,I,K,R=m("sim"),m("openttd/town_passengers"),m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating"),m("openttd/rail_roster")
local Queue=m("station_rating_runtime")(Sim,K,P)
local Mail=m("road_mail_runtime")(Sim,H,P,I,K,Queue)
local C=m("openttd/station_catchment")(P,K,function()return 8 end,Mail.house_acceptance)
local S=m("passenger_station_service")(C,P,I,K,Queue,m("road_loading_runtime"),m("openttd/loading_timing"))
local Order=m("openttd/rail_order_cargo")
local function cell(x,z)return z*64+x+1 end
local function xy(id)return (id-1)%64,math.floor((id-1)/64) end
local ctx={width=64,height=64,xy=xy,year=function()return 1950 end,feeder_percent=75,
  house_at=function(x,z) if z==8 and (x==10 or x==11 or x==30 or x==31) then return {id=4} end end}
local west_tile,east_tile=cell(10,10),cell(30,10)
local function setup(stock,mounted)
  local state=S.new(1)
  local function station(id,x)
    local st=S.station(state,{id=id,town=id,owner="Postal",tiles={{x=x,y=10,kind="airport"},{x=x+1,y=10,kind="airport"}}},ctx)
    st.mail_enabled=true
    S.refresh_mail_acceptance(state,id,ctx)
    assert(st.mail_acceptance>=8)
    return st
  end
  local a,b=station(1,10),station(2,30)
  local v=S.vehicle(state,{id=77,mode="air",engine=stock,speed=473,built=1947,owner="Postal",air_mail=mounted~=false})
  return state,a,b,v
end
local function tick(s,k)
  local ready,events=S.pre_motion_tick(s,k,ctx)
  S.post_motion_tick(s,k,ctx)
  return ready,events
end
local function packet(src,tile,n)
  return {source_type="town",source=src,origin_station=src,origin_tile=tile,units=n,age=0,
    travel_x=select(1,xy(tile)),travel_z=select(2,xy(tile))}
end
local function fill_body(body,n)
  body.batches=n>0 and {packet(1,west_tile,n)} or {}
  body.units=n
end
local function begin(state,st,v,visit,t,flags)
  S.pre_motion_tick(state,t,ctx)
  local tile=st.id==1 and west_tile or east_tile
  local visit_row=assert(S.begin(state,v.id,st.id,visit,tile,flags or {},t,ctx,{}))
  assert(S.begin(state,v.id,st.id,visit,tile,flags or {},t,ctx,{})==visit_row)
  assert(#st.loading_order==1)
  S.post_motion_tick(state,t,ctx)
end
local function departures(load_type,cabin,mail)
  local s,a,_,v=setup(215)
  local p,m=v.carrying_parts[1],v.carrying_parts[2]
  assert(p.capacity==25 and m.capacity==4 and p.slice==20 and m.slice==5)
  fill_body(p,cabin);fill_body(m,mail)
  v.units=cabin+mail
  begin(s,a,v,1,1,Order.arrival({load_type=load_type},{}))
  for t=2,85 do
    local ready=tick(s,t)
    if #ready>0 then assert(ready[1]==v.id);return true end
  end
  return false
end
assert(not departures(3,20,4),"Full Load Any must not leave with only Mail full")
assert(departures(3,25,1),"Full Load Any may leave with only passengers full")
assert(not departures(2,25,1),"Full Load All must wait for Mail after passengers fill")
assert(departures(2,25,4))

local s,a,b,v=setup(216)
local p,m=v.carrying_parts[1],v.carrying_parts[2]
assert(p.capacity==65 and m.capacity==8)
a.stock.passenger={packet(1,west_tile,65)}
a.stock.mail={packet(1,west_tile,8)}
begin(s,a,v,1,1,{full=true})
local saw=false
local ready_tick
for t=2,140 do
  local ready,events=S.pre_motion_tick(s,t,ctx)
  for _,e in ipairs(events) do
    if e.kind=="board" and not saw then
      assert(p.units==20 and m.units==5 and v.load_state.ticks==20)
      assert((p.cargo_tile==west_tile and m.cargo_tile==west_tile) and #a.loading_order==1)
      saw=true;break
    end
  end
  if #ready>0 then assert(S.leave(s,v.id,1,t,ctx,events));ready_tick=t end
  S.post_motion_tick(s,t,ctx)
  if ready_tick then break end
end
assert(saw and ready_tick and v.units==73)
begin(s,b,v,2,ready_tick+1,{no_load=true})
local paid,events=nil
for t=ready_tick+2,ready_tick+190 do
  _,events=tick(s,t)
  for _,e in ipairs(events) do
    if e.kind=="fare" then
      assert(not paid)
      paid=e
    end
  end
end
assert(paid and paid.units==73 and paid.by_cargo.passenger.delivered==65 and paid.by_cargo.mail.delivered==8)
assert(paid.amount==paid.by_cargo.passenger.route+paid.by_cargo.mail.route and s.companies.Postal.cash==paid.amount)
assert(s.towns[2]==65 and s.mail_towns[2]==8)
S.pre_motion_tick(s,s.tick+1,ctx)
assert(S.begin(s,v.id,b.id,1,east_tile,{},s.tick,ctx,{})==nil) -- stale visit; no second receipt

-- Rebinding a prior passenger-only aircraft while it has an active
-- loading receipt must neither lose its existing packet nor move that
-- receipt to a second visit. Only upgrade the idle cargo store.
local legacy,la,_,old=setup(215,false)
fill_body(old,13)
S.pre_motion_tick(legacy,1,ctx)
assert(S.begin(legacy,old.id,la.id,1,west_tile,{},1,ctx,{}))
assert(not S.mount_air_mail(old))
assert(S.leave(legacy,old.id,1,1,ctx,{},true))
local carry=assert(old.batches[1])
assert(S.mount_air_mail(old) and S.mount_air_mail(old))
assert(old.carrying_parts[1].units==13 and old.carrying_parts[1].batches[1]==carry and old.carrying_parts[2].units==0)
local transfer,_,dest,carrier=setup(215)
fill_body(carrier.carrying_parts[1],10);fill_body(carrier.carrying_parts[2],3)
carrier.units=13
begin(transfer,dest,carrier,1,1,{transfer=true,no_load=true})
for t=2,100 do
  local ready,events=S.pre_motion_tick(transfer,t,ctx)
  for _,e in ipairs(events) do assert(e.kind~="fare") end
  if ready[1] then assert(S.leave(transfer,carrier.id,1,t,ctx,events)) end
  S.post_motion_tick(transfer,t,ctx)
  if ready[1] then break end
end
assert(not carrier.load_state and not next(transfer.companies) and carrier.units==0)
assert(S.waiting(transfer,dest.id,"passenger")==10 and S.waiting(transfer,dest.id,"mail")==3)
for cargo,units in pairs({passenger=10,mail=3}) do
  local detail=assert(carrier.cargo_totals[cargo])
  local bag=assert(dest.stock[cargo][1])
  assert(detail.transfer>0 and detail.route==0 and detail.delivered==0)
  assert(bag.units==units and bag.feeder_share>0 and bag.origin_station==1)
end
print("PASS stock aircraft distinct cabin/hold, 20/5 slices, RC1 Full Load Any passenger exception, one 20-tick and payment, and safe legacy rebind")

-- CrashAirplane destroys onboard legs and unreserved station stock,
-- not the loading reservation on a second vehicle or a town delivery.
local crash,_,field,plane=setup(216)
fill_body(plane.carrying_parts[1],7)
fill_body(plane.carrying_parts[2],3)
plane.units=10
field.stock.passenger={packet(2,east_tile,11)}
field.stock.mail={packet(2,east_tile,4)}
local other=S.vehicle(crash,{id=78,mode="air",engine=216,speed=473,built=1950,owner="Postal",air_mail=true})
begin(crash,field,other,1,1,{full=true})
local people,mailbags=other.carrying_parts[1],other.carrying_parts[2]
local reserved_people,reserved_mail=people.load_state.reserved_units,mailbags.load_state.reserved_units
assert(S.crash_air(crash,plane.id,field.id)==9)
assert(plane.units==0 and plane.crashed and plane.stopped and not next(crash.companies))
assert(people.load_state.reserved_units==reserved_people and mailbags.load_state.reserved_units==reserved_mail)
assert(#field.stock.passenger==0 and #field.stock.mail==0)
assert(field.passenger_rating_state.rating==1 and field.mail_rating_state.rating==1)
print("PASS aircraft accident loses onboard and stored cargo, not another carrier's reservations")
