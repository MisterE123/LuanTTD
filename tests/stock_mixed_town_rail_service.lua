local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,H,P,I,K,R=m("sim"),m("openttd/town_passengers"),m("openttd/passengers"),m("openttd/income"),m("openttd/station_rating"),m("openttd/rail_roster")
local Queue=m("station_rating_runtime")(Sim,K,P)
local Mail=m("road_mail_runtime")(Sim,H,P,I,K,Queue)
local C=m("openttd/station_catchment")(P,K,function()return 8 end,Mail.house_acceptance)
local S=m("passenger_station_service")(C,P,I,K,Queue,m("road_loading_runtime"),m("openttd/loading_timing"))
local Order=m("openttd/rail_order_cargo")
assert(R.mixed_town_consist({0,27,28}) and R.mixed_town_consist({0,28,27,28}))
assert(not R.mixed_town_consist({0,27,27}) and not R.mixed_town_consist({0,28,28}) and not R.mixed_town_consist({0,27,28,29}))
assert(not R.mixed_town_consist({0,8,27,28}) and not R.mixed_town_consist({11,27,28})
  and not R.mixed_town_consist({22,27,28}) and not R.mixed_town_consist({0,27,28,27,28}))

-- Production scan, not a fixture switch: ordinary stock art grants
-- supported engines; disabled or absent art cannot activate the service.
local Art=m("rail_dispatch_manifest")
local ordinary=Art.scan(root,false,false)
assert(ordinary.ready.mail_van and ordinary.mixed_town_engines[0])
assert(not ordinary.mixed_town_engines[11] and not ordinary.mixed_town_engines[22]
  and not ordinary.mixed_town_engines[23])
local f=io.open
local function without(suffix)
  io.open=function(path,...)
    if path:sub(-#suffix)==suffix then return nil end
    return f(path,...)
  end
  local result=Art.scan(root,false,false)
  io.open=f
  return result
end
assert(not without("bl_rail_kirby_paul_tank.obj").mixed_town_engines[0])
assert(not next(without("bl_rail_passenger_wagon.obj").mixed_town_engines))
assert(not next(without("bl_rail_mail_van.png").mixed_town_engines))
local live={rail_paid_service=true,rail_owned_service=true,road_stock_house_supply=true,corner_grid={}}
Sim.mount_rail_mail(live,true,ordinary.mixed_town_engines)
assert(live.rail_mail_service and live.rail_mixed_town_service)
Sim.mount_rail_mail(live,true,{})
assert(live.rail_mail_service and not live.rail_mixed_town_service)
live.road_stock_house_supply=false
Sim.mount_rail_mail(live,true,ordinary.mixed_town_engines)
assert(not live.rail_mail_service and not live.rail_mixed_town_service)
local yard={kind="depot",owner="Postal",railtype=0}
assert(not R.quote(yard,yard.owner,{0,27,28},{roster_preview=true,mount_mail_wagon=true}))
assert(not R.quote(yard,yard.owner,{0,27,28},{roster_preview=true,mount_mixed_town=true}))
assert(R.quote(yard,yard.owner,{0,27,28},{roster_preview=true,mount_mail_wagon=true,mount_mixed_town=true}))
local function cell(x,z)return z*64+x+1 end
local function xy(id)return (id-1)%64,math.floor((id-1)/64) end
local ctx={width=64,height=64,xy=xy,year=function()return 1950 end,feeder_percent=75,
  house_at=function(x,z) if z==8 and (x==10 or x==11 or x==30 or x==31) then return {id=4} end end}
local west_tile,east_tile=cell(10,10),cell(30,10)
local function setup(stocks)
  local state=S.new(1)
  local function station(id,x)
    local st=S.station(state,{id=id,town=id,owner="Postal",tiles={{x=x,y=10,kind="rail"},{x=x+1,y=10,kind="rail"}}},ctx)
    st.mail_enabled=true
    S.refresh_mail_acceptance(state,id,ctx)
    assert(st.mail_acceptance>=8)
    return st
  end
  local a,b=station(1,10),station(2,30)
  local parts={}
  for i,id in ipairs(stocks) do parts[i]={stock=id,index=i+1,body_id=900+i} end
  local v=S.vehicle(state,{id=77,mode="rail",length=8+#parts*8,speed=64,built=1947,owner="Postal",cargo="mixed",town_parts=parts})
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
  flags=flags or {};flags.platform_tiles=2;flags.cargo_tiles={}
  for i=1,#v.carrying_parts do flags.cargo_tiles[i]=st.id==1 and west_tile or east_tile end
  S.pre_motion_tick(state,t,ctx)
  assert(S.begin(state,v.id,st.id,visit,flags.cargo_tiles[1],flags,t,ctx,{}))
  S.post_motion_tick(state,t,ctx)
end
local function full(load_type,stocks)
  local s,a,_,v=setup(stocks or {27,27,28})
  fill_body(v.carrying_parts[1],40)
  fill_body(v.carrying_parts[2],5)
  begin(s,a,v,1,1,Order.arrival({load_type=load_type},{}))
  assert(#a.loading_order==1 and a.loading_order[1]==v.id)
  for k=2,70 do
    assert(#tick(s,k)==0,"A single full passenger coach cannot satisfy the whole passenger cargo type")
  end
  a.stock.mail={packet(1,west_tile,30)}
  local left
  for k=71,450 do
    local ready=S.pre_motion_tick(s,k,ctx)
    if ready[1] then left=k;assert(S.leave(s,v.id,1,k,ctx));end
    S.post_motion_tick(s,k,ctx)
    if left then break end
  end
  assert(v.carrying_parts[1].units==40 and v.carrying_parts[2].units==5 and v.carrying_parts[3].units==30)
  return left,s,v
end
assert(full(3),"A full Mail cargo type is sufficient under Full load any")
assert(not full(2),"Full load all must wait for every passenger and Mail body")
local function last_full(stocks,pq,mq,expected)
  local s,a,_,v=setup(stocks)
  begin(s,a,v,1,1)
  a.stock.passenger={packet(1,west_tile,pq)}
  a.stock.mail={packet(1,west_tile,mq)}
  for k=2,49 do
    tick(s,k)
    if (v.boarded or 0)>0 then
      assert(v.load_state.stop_loading==expected)
      assert(v.load_state.ticks==40)
      return
    end
  end
  error("No normal loading scan")
end
last_full({27,28},5,2,false) -- Mail partial cannot clear the last full passenger slice.
last_full({27,27,28},8,2,true) -- The second attempted coach did clear the passenger bit.

local function transfer(no_unload)
  local s,_,b,v=setup({28,27,28})
  for i,body in ipairs(v.carrying_parts) do fill_body(body,i+2) end
  begin(s,b,v,1,1,{transfer=true,no_load=true,no_unload=no_unload})
  for k=2,520 do
    local departures,events=S.pre_motion_tick(s,k,ctx)
    for _,e in ipairs(events) do assert(e.kind~="fare") end
    if departures[1] then assert(S.leave(s,v.id,1,k,ctx,events));end
    S.post_motion_tick(s,k,ctx)
    if departures[1] then break end
  end
  assert(not v.load_state and not v.delivered and not next(s.companies))
  local p,m=S.waiting(s,b.id,"passenger"),S.waiting(s,b.id,"mail")
  if no_unload then
    assert(p==0 and m==0 and v.units==12)
  else
    assert(p==4 and m==8 and v.units==0)
    assert(v.cargo_totals.passenger.transfer>0 and v.cargo_totals.mail.transfer>0)
    assert(v.visual_profit==v.cargo_totals.passenger.transfer+v.cargo_totals.mail.transfer)
    for _,q in pairs(b.stock) do
      for _,r in ipairs(q) do assert(r.feeder_share>0 and r.origin_station==1) end
    end
  end
end
transfer(false);transfer(true)
print("PASS mixed town RC1 full masks, independent per-body reserves, transfers/feeder shares, and one 40-tick station pulse")
