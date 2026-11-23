-- Freight weights, stock art/market gates and one actual station /
-- independent per-cargo loading/rating/credit on the production kernel.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local R,Art=m("openttd/rail_roster"),m("rail_dispatch_manifest")
local w=assert(R.entry(28))
assert(w.name=="Mail Van" and w.image_index==35 and w.capacity==30 and w.tare==21)
assert(w.cost_factor==228 and w.length==8 and w.load_amount==5 and w.cargo=="mail")
assert(w.climates==15 and w.base_intro==1827 and w.source_model_life==50 and R.purchase_price(28)==1781)
for units=0,30 do
  local stat=assert(R.stats({0,{stock_id=28,cargo_count=units}},{freight_trains=20}))
  assert(stat.weight==47+21+math.floor(units/4),stat.weight)
  assert(Art.wagon({stock_wagon=28},{},{})=="mail_van")
end
local depot={kind="depot",owner="Post",railtype=0}
assert(not R.quote(depot,"Post",{0,28},{roster_preview=true}))
assert(R.quote(depot,"Post",{0,28},{roster_preview=true,mount_mail_wagon=true}))
assert(not R.quote(depot,"Post",{0,27,28},{roster_preview=true,mount_mail_wagon=true}))
assert(not Art.scan("not-a-real-mod-path").ready.mail_van)

local Sim,H,P,I,K=m("sim"),m("openttd/town_passengers"),m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating")
local Queue=m("station_rating_runtime")(Sim,K,P)
local Mail=m("road_mail_runtime")(Sim,H,P,I,K,Queue)
local C=m("openttd/station_catchment")(P,K,function() return 8 end,Mail.house_acceptance)
local S=m("passenger_station_service")(C,P,I,K,Queue,m("road_loading_runtime"),m("openttd/loading_timing"))
local state=S.new(1751)
local houses={}
local function cell(x,z) return z*64+x+1 end
local function xy(id) return (id-1)%64,math.floor((id-1)/64) end
local ctx={width=64,height=64,xy=xy,year=function()return 1950 end,
  house_at=function(x,z) return houses[cell(x,z)] end}
houses[cell(11,11)]={id=4,town=1}
houses[cell(12,11)]={id=0,town=1}
houses[cell(42,11)]={id=4,town=2}
houses[cell(43,11)]={id=4,town=2}
local function stop(id,town,x)
  local st=S.station(state,{id=id,town=town,owner="Post",tiles={{x=x,y=10,kind="rail"},{x=x+1,y=10,kind="rail"}}},ctx)
  st.mail_enabled=true
  S.refresh_mail_acceptance(state,id,ctx)
  return st
end
local west,east=stop(0x4001,1,11),stop(0x4002,2,42)
assert(west.mail_acceptance==7 and east.mail_acceptance==8 and east.always_accept_mail and west.always_accept_mail)
houses[cell(13,11)]={id=6,town=1,completed=false}
assert(S.refresh_mail_acceptance(state,west.id,ctx).eighths==8,"Unfinished house accepts Mail although it produces none")
local pass=S.vehicle(state,{id=101,owner="Post",mode="rail",length=16,speed=112,built=1949})
local post=S.vehicle(state,{id=102,owner="Post",mode="rail",length=16,speed=64,built=1950,cargo="mail",wagon=28})
local truck={id=3,owner="Rival",town=1,mode="truck",tiles={{x=12,y=13,kind="truck"}},stock={}}
local allocator=Mail.shared_allocator(C,64,64,{west,east,truck})
local order={platform_tiles=2,full=true}
local origin,destination=cell(11,10),cell(43,10)
S.pre_motion_tick(state,1,ctx)
assert(S.begin(state,101,west.id,1,origin,order,1,ctx))
assert(S.begin(state,102,west.id,1,origin,order,1,ctx))
assert(west.loading_order[1]==101 and west.loading_order[2]==102 and #west.loading_order==2)
S.post_motion_tick(state,1,ctx)
local state_by_cargo={}
local emitted=false
local placed=0
for tick=2,700 do
  local ready=S.pre_motion_tick(state,tick,ctx)
  local pstate,mstate=west.passenger_rating_state,west.mail_rating_state
  if not emitted and K.has_tried_loading(pstate) and mstate and K.has_tried_loading(mstate) then
    allocator.loading(truck.id,"road",96,1950,1950,22)
    local amount=200
    local expected={{st=truck,rating=truck.mail_rating_state.rating},{st=west,rating=mstate.rating}}
    P.allocate(amount,expected)
    local a=allocator.offer(amount,12,11,houses[cell(12,11)])
    assert(a==math.floor(expected[1].fixed/256)+math.floor(expected[2].fixed/256))
    assert(Mail.waiting(truck)==math.floor(expected[1].fixed/256))
    assert(Mail.waiting(west)==math.floor(expected[2].fixed/256))
    placed=a
    S.produce(state,12,11,220,1,ctx)
    emitted=true
  end
  for _,id in ipairs(ready) do
    local v=state.vehicles[id]
    if not state_by_cargo[v.cargo] then
      assert(S.leave(state,id,1,tick,ctx))
      state_by_cargo[v.cargo]=v.units
    end
  end
  S.post_motion_tick(state,tick,ctx)
  if state_by_cargo.passenger and state_by_cargo.mail then break end
end
assert(emitted and placed>0 and state_by_cargo.mail==30 and state_by_cargo.passenger==40)
assert(west.mail_rating_state.last_speed==64 and west.passenger_rating_state.last_speed==112)
assert(west.mail_rating_state~=west.passenger_rating_state and not west.loading_order[1])
assert(post.batches[1].source_type=="town" and post.batches[1].origin_station==west.id)
assert(post.batches[1].origin_tile==origin)
assert(S.waiting(state,west.id,"mail")==Mail.waiting(west))
-- On visiting the origin again, even a producing/accepting platform
-- cannot pay for its own packets. Preserve bags across a normal stop.
local tick=state.tick+1
S.pre_motion_tick(state,tick,ctx)
assert(S.begin(state,102,west.id,2,origin,{platform_tiles=2,no_load=true},tick,ctx))
assert(post.load_state.unload_units==0)
assert(S.leave(state,102,2,tick,ctx,{},true))
S.post_motion_tick(state,tick,ctx)
tick=tick+185 -- travel, not a rating or cargo reset
for k=state.tick+1,tick-1 do S.pre_motion_tick(state,k,ctx);S.post_motion_tick(state,k,ctx) end
local _,events=S.pre_motion_tick(state,tick,ctx)
assert(S.begin(state,101,east.id,2,destination,{platform_tiles=2,no_load=true},tick,ctx))
assert(S.begin(state,102,east.id,3,destination,{platform_tiles=2,no_load=true},tick,ctx))
S.post_motion_tick(state,tick,ctx)
local mail_paid,mail_units=0,0
local fare,departures
for k=tick+1,tick+520 do
  departures,events=S.pre_motion_tick(state,k,ctx)
  for _,e in ipairs(events) do
    if e.kind=="deliver" and e.cargo=="mail" then
      assert(e.distance==32 and e.age>=1 and e.source==1 and e.tile==destination)
      assert(e.amount==I.regular(e.units,e.distance,e.age,unpack(I.temperate.mail)))
      mail_paid,mail_units=mail_paid+e.amount,mail_units+e.units
    end
  end
  for _,vid in ipairs(departures) do
    local v=state.vehicles[vid]
    assert(S.leave(state,vid,v.visit,k,ctx,events))
  end
  for _,e in ipairs(events) do if e.kind=="fare" and e.cargo=="mail" then fare=e end end
  S.post_motion_tick(state,k,ctx)
  if fare and pass.delivered then break end
end
assert(mail_paid>0 and mail_units==30 and fare.amount==mail_paid and fare.units==mail_units)
assert(state.towns[2]==40 and state.mail_towns[2]==30 and post.delivered==30 and pass.delivered==40)
assert(post.units==0 and pass.units==0 and post.route_profit==mail_paid)
print(("PASS stock #28 with separate waiting/rating at the exact same two platforms, one fixed-point house contest, 30 genuine bags / $%d"):format(mail_paid))
