-- SPDX-License-Identifier: GPL-2.0-only
local function mod(path) return dofile("mods/luanttd_core/"..path..".lua") end
local Sim=mod("sim")
local P=mod("openttd/passengers")
local H=mod("openttd/town_passengers")
local Income=mod("openttd/income")
local Rating=mod("openttd/station_rating")
local Roads=mod("station_rating_runtime")(Sim,Rating,P)
local Catchment=mod("openttd/station_catchment")(P,Rating,
  mod("road_station_service")().house_passenger_acceptance,mod("road_mail_runtime")().house_acceptance)
local Service=mod("passenger_station_service")(Catchment,P,Income,Rating,Roads,
  mod("road_loading_runtime"),mod("openttd/loading_timing"))
local Cross=mod("passenger_supply_mux")(Sim,Catchment,P,Roads,Rating)
local mail_events=0
local mail_tap={
  stops=function() return {} end,
  from_house=function(_,amount)
    assert(amount>0)
    mail_events=mail_events+1
  end,
  step_rating=function() end,
}
local Town=mod("town_passenger_runtime")(Sim,H,P,Roads,mail_tap)

local function dump(v)
  if type(v)=="table" then
    local fields={}
    for k,data in pairs(v) do fields[#fields+1]="["..dump(k).."]="..dump(data) end
    table.sort(fields)
    return "{"..table.concat(fields,",").."}"
  elseif type(v)=="string" then return string.format("%q",v)
  else return tostring(v) end
end
local function clone(t) return assert(loadstring("return "..dump(t)))() end
local function exact(a,b) assert(dump(a)==dump(b),"Snapshot differs") end
local function st(x,y,kind,id) return {x=x,y=y,kind=kind,station=id} end
local x,y=9,9
local house={town=99,id=7,completed=true}
local ctx={width=48,height=36,year=function()return 1950 end,house_at=function()end,
  xy=Sim.xy,station_id=function(kind,s) return kind=="road" and s.id or s.id+10 end}
local function setup()
  local s={stations={
    [1]={id=1,owner="a",site=11,tile=Sim.id(11,11),mode="road",stock={},last_service={}},
    [2]={id=2,owner="a",site=13,tile=Sim.id(11,12),mode="road",stop_type="truck",stock={},last_service={}},
    [3]={id=3,owner="a",site=14,tile=Sim.id(10,10),mode="road",stock={},last_service={}},
    [4]={id=4,owner="a",site=11,tile=Sim.id(15,10),mode="road",stock={},last_service={}},
  },day=0,seed=91}
  local a=Service.new(91)
  local rail=Service.station(a,{id=1,town=11,owner="a",tiles={st(13,9,"rail",1)}},ctx)
  local ferry=Service.station(a,{id=2,town=12,owner="b",tiles={st(13,9,"dock",2),st(14,9,"dock",2)}},ctx)
  for _,id in ipairs({1,2,4}) do
    local road=s.stations[id]
    Roads.status(s,road)
    Rating.observe_loading(road.passenger_rating_state,50,0,30)
    road.passenger_rating_state.rating=200
  end
  Rating.observe_loading(rail.passenger_rating_state,80,0,40)
  Rating.observe_loading(ferry.passenger_rating_state,64,0,100)
  rail.passenger_rating_state.rating=100
  ferry.passenger_rating_state.rating=100
  return s,a
end

local s,a=setup()
local function sums()
  return P.waiting(s.stations[1]),P.waiting(a.stations[1]),P.waiting(a.stations[2])
end
assert(Cross.capture(s,5,x,y,house,44) and not Cross.capture(s,5,x,y,house,44))
assert(not pcall(Cross.capture,s,6,x,y,house,44))
assert(Cross.consume(s,a,43,ctx)==0)
local snapshot=clone({road=s,commercial=a});s,a=snapshot.road,snapshot.commercial
local moved,allocation=Cross.consume(s,a,44,ctx)
assert(moved==2 and #allocation==3)
-- 5*(200+1)=1005 units in fixed point shared across all modes. Same
-- owner splits its portion across bus and train before any rounding.
exact(allocation,{
  {station=1,kind="road",local_id=1,fixed=447,units=1},
  {station=11,kind="service",local_id=1,fixed=223,units=0},
  {station=12,kind="service",local_id=2,fixed=335,units=1},
})
local again=clone({road=s,commercial=a});s,a=again.road,again.commercial
assert(Cross.consume(s,a,44,ctx)==0 and not Cross.capture(s,5,x,y,house,44))
assert(not pcall(Cross.capture,s,9,x,y,house,44))
assert(Cross.capture(s,5,x,y,house,45))
moved=Cross.consume(s,a,45,ctx)
assert(moved==4)
local bus,train,ferry=sums()
assert(bus==3 and train==1 and ferry==2)
assert(s.stations[1].passenger_fraction==126 and a.stations[1].passenger_fraction==190
  and a.stations[2].passenger_fraction==158)
assert(P.waiting(s.stations[2])==0 and P.waiting(s.stations[3])==0 and P.waiting(s.stations[4])==0)
for _,owner in ipairs({s.stations[1],a.stations[1],a.stations[2]}) do
  local p=owner.stock.passenger[1]
  assert(p.source==99 and p.origin_station==owner.id and p.origin_tile==nil and p.source_type=="town")
end

-- Exclusive rights protect the station's associated town, not the
-- source house's town. Rights can remove both company-a modes at once.
ctx.town_rights=function(id)
  if id==11 then return {exclusive_counter=3,exclusivity="b"} end
end
assert(Cross.capture(s,8,x,y,house,46))
moved,allocation=Cross.consume(s,a,46,ctx)
assert(#allocation==1 and allocation[1].station==12 and allocation[1].fixed==808)
local first,second,third=sums()
assert(first==bus and second==train and third>ferry)
ctx.town_rights=nil
assert(Cross.capture(s,1,47,35,house,47))
assert(Cross.consume(s,a,47,ctx)==0)
assert(not Cross.capture(s,1,47,35,house,47))

-- A physical road part of an already-shared station must use the same
-- canonical queue/rating/loading allocation. Do not silently ignore
-- collisions or claim that a split runtime already shares a station.
s,a=setup()
local road,shared=s.stations[1],a.stations[1]
local sharedctx={width=48,height=36,year=ctx.year,house_at=ctx.house_at,index_passenger_catchments=true,
  station_id=function(_,st_) return st_.id end,
  road_alias=function(st_) if st_==road then return 1 end end}
assert(Cross.capture(s,10,x,y,house,1))
assert(not pcall(Cross.consume,s,a,1,sharedctx))
Service.footprint(a,1,{st(13,9,"rail",1),st(10,10,"bus",1)},sharedctx)
road.stock,road.passenger_rating_state,road.loading_order=shared.stock,shared.passenger_rating_state,shared.loading_order
-- Prevent the unrelated fixture's truck/no-service terminals from
-- colliding by choosing a new unique ID for the standalone ferry.
a.stations[2]=nil
assert(Cross.consume(s,a,1,sharedctx)==3)
assert(P.waiting(road)==3 and P.waiting(shared)==3 and #shared.stock.passenger==1)

-- Real Town.day 74-tick loop with an actual stock HouseID. Capture calls
-- replace, rather than accompany, the road-only event. Also verify using
-- the real service's production slot before its loading pass.
s,a=setup()
local authored=Sim.new(1751)
for _,tile in ipairs(authored.tiles) do tile.house=nil end
local src=Sim.id(x+1,y+1)
authored.tiles[src].house=true
authored.tiles[src].variant=2
authored.tiles[src].parcel="shop"
authored.stations=s.stations
s=authored
s.road_mail=true
local emits,moved_sum=0,0
local fixed_parts=0
local hooks={passenger=function(world,amount,u,v,rec,tick)
  assert(u==x and v==y and Cross.town_hooks.passenger(world,amount,u,v,rec,tick))
  emits=emits+1
end}
ctx.production=function(service,tick)
  local n,shares=Cross.consume(s,service,tick,ctx)
  moved_sum=moved_sum+n
  for _,result in ipairs(shares) do fixed_parts=fixed_parts+result.fixed end
end
for day=1,100 do
  s.day=day
  -- Model regular successful loading attempts without consuming packets;
  -- this conservation fixture must not conflate rating decay with dual output.
  for _,g in ipairs({s.stations[1].passenger_rating_state,
       a.stations[1].passenger_rating_state,a.stations[2].passenger_rating_state}) do
    Rating.observe_loading(g,90,0,30)
  end
  Town.day(s,function(tick)
    Service.pre_motion_tick(a,tick,ctx)
    Service.post_motion_tick(a,tick)
  end,hooks)
end
bus,train,ferry=sums()
assert(emits>0 and bus>0 and train>0 and ferry>0 and mail_events>0)
assert(s.passenger_house_clock.counter==a.tick and a.tick==100*74)
assert(bus+train+ferry==moved_sum)
assert(moved_sum*256+s.stations[1].passenger_fraction+a.stations[1].passenger_fraction+a.stations[2].passenger_fraction==fixed_parts)
assert(s.stock_passenger_mux.pending==nil and s.stock_passenger_mux.consumed.town==s.tiles[src].source_house.town)
print(string.format("PASS: %d real house emissions through one cross-mode contest: road %d, rail %d, ferry %d",
  emits,bus,train,ferry))

-- Multiple different houses emit on the same stock tick. This order is
-- intentionally neither town ID nor coordinate order. Earlier recipients
-- own rounding carry; no duplicate emits update either queue on replay.
s,a=setup()
a.stations={};s.stations[2]=nil;s.stations[3]=nil;s.stations[4]=nil
local bus_only=s.stations[1]
local h1,h2,h3={town=90},{town=20},{town=40}
assert(Cross.capture(s,3,10,9,h1,79))
assert(Cross.capture(s,3,9,9,h2,79))
assert(Cross.capture(s,3,8,9,h3,79))
assert(not pcall(Cross.capture,s,4,10,9,h1,79))
assert(not Cross.capture(s,3,10,9,h1,79))
assert(not pcall(Cross.capture,s,3,7,9,h2,80))
s=clone(s)
local calls=0
local fault={width=ctx.width,height=ctx.height,station_id=ctx.station_id,
  station_town=function(_,st)
    calls=calls+1
    -- First house commits, then consumption is interrupted before the
    -- second station contest begins. A saved retry must not re-credit it.
    if calls==2 then error("test interruption") end
    return st.site
  end}
assert(not pcall(Cross.consume,s,a,79,fault))
assert(P.waiting(s.stations[1])==2 and s.stock_passenger_mux.pending.next==2)
s=clone(s)
assert(not Cross.capture(s,3,10,9,h1,79))
assert(Cross.consume(s,a,79,ctx)==5)
bus_only=s.stations[1]
assert(P.waiting(bus_only)==7 and bus_only.passenger_fraction==17)
for i,town in ipairs({90,20,40}) do
  assert(bus_only.stock.passenger[i].source==town)
  assert(bus_only.stock.passenger[i].units==(i==3 and 3 or 2))
end
assert(Cross.consume(s,a,79,ctx)==0)
s=clone(s)
assert(not Cross.capture(s,3,10,9,h1,79) and not Cross.capture(s,3,9,9,h2,79))
assert(not Cross.capture(s,3,8,9,h3,79))
assert(not pcall(Cross.capture,s,3,7,9,h2,79))
assert(Cross.capture(s,3,10,9,h1,80))
assert(not Cross.capture(s,3,8,9,h3,79))
assert(Cross.consume(s,a,80,ctx)==2 and P.waiting(s.stations[1])==9)

-- Load a real v1-format set of source acknowledgement/pending receipts:
-- preserve the acknowledged house, then append another event to the
-- pending tick before service continues.
s,a=setup()
a.stations={};s.stations[2]=nil;s.stations[3]=nil;s.stations[4]=nil
s.stock_passenger_mux={version=1,
  consumed={tick=51,x=9,y=9,amount=3,town=20},
  pending={tick=52,x=8,y=9,amount=3,town=40}}
assert(not Cross.capture(s,3,9,9,h2,51))
assert(not Cross.capture(s,3,8,9,h3,52))
assert(Cross.capture(s,3,10,9,h1,52))
assert(Cross.consume(s,a,52,ctx)==4 and s.stock_passenger_mux.version==2)
assert(s.stations[1].stock.passenger[1].source==40 and s.stations[1].stock.passenger[2].source==90)
print("PASS: ordered same-tick emission batches, interrupted partial and v1 save migration, all replay receipts")


-- Use two neighboring sectors and change the physical map between events.
-- The candidate list cannot duplicate a station spanning the seam, carry
-- an obsolete stop to the new revision, or change allocation rounding.
do
  local old_r,old_s=setup()
  old_r.topology=10
  local new_r,new_s=clone(old_r),clone(old_s)
  local indexed={}
  for k,v in pairs(ctx) do indexed[k]=v end
  indexed.index_passenger_catchments=true
  local function event(tick)
    local h={town=99,area=2}
    assert(Cross.capture(old_r,16,15,9,h,tick))
    assert(Cross.capture(new_r,16,15,9,h,tick))
    local a,b=Cross.consume(old_r,old_s,tick,ctx)
    local c,d=Cross.consume(new_r,new_s,tick,indexed)
    assert(a==c)
    exact(b,d)
    exact(old_r,new_r)
    exact(old_s,new_s)
    return b
  end
  local function has(rows,id)
    for _,row in ipairs(rows) do if row.station==id then return true end end
    return false
  end
  local initial=event(800)
  assert(has(initial,11) and has(initial,12))
  Service.footprint(old_s,1,{st(42,32,"rail",1)},ctx)
  Service.footprint(new_s,1,{st(42,32,"rail",1)},indexed)
  old_r.topology,new_r.topology=11,11
  local moved=event(801)
  assert(not has(moved,11) and has(moved,12))
  old_s.stations[2],new_s.stations[2]=nil,nil
  old_r.topology,new_r.topology=12,12
  assert(not has(event(802),12))
end
print("PASS indexed catchments match every allocation across a sector seam and rebuild on topology edits")
