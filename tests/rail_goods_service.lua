-- SPDX-License-Identifier: GPL-2.0-only
-- One authentic forest/sawmill clock, one real mixed Goods queue allocation,
-- one paid #32 and ordinary #138 crate truck, with snapshots mid-loading.
local root="mods/bayline/"
local function m(n)return dofile(root..n..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local P,Rate,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local Catch=m("openttd/station_catchment")(P,Rate)
local Coal=m("openttd/coal_industry")(P,Rate,Catch,Income)
local Rules=m("openttd/timber_industry")(P,Catch,Rate,Income,Coal,m("openttd/town_goods"))
local Roster,Timing,Factory=m("openttd/rail_roster"),m("openttd/loading_timing"),m("road_loading_runtime")
local Station=m("station_rating_runtime")(Sim,Rate,P)
local RailStation=m("rail_coal_service")(Sim,Coal,Catch,Roster,P,Rate,Station,Income,Factory,Timing)
local Goods=m("rail_goods_service")(Sim,Rules,Catch,Roster,RailStation,P,Rate,Station,Factory,Timing)
local Pipeline=m("timber_industry_runtime")(Rules,Catch)
local Road=m("road_timber_service")(Sim,Rules,Pipeline,P,Income,Rate,Station)
local Load=Factory(Timing,P)
local house=m("openttd/town_passengers")
local id=Sim.id
local w=Sim.new(1751)
w.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
w.stock_timber_industries={
  [10]=Rules.new("forest",10,4,4,{completed=true,original=true,counter=1,economy_year=1950}),
  [13]=Rules.new("sawmill",13,16,9,{completed=true,original=true,counter=1,economy_year=1950}),
}
w.rail=Goods.new();w.clock=house.new_clock(6,6)
local function copy(t)
  if type(t)~="table" then return t end
  local b={};for k,v in pairs(t) do b[k]=copy(v) end;return b
end
local function road(num,x,z,town)
  w.stations[num]={id=num,tile=id(x,z),owner="Road",town=town,mode="road",stop_type="truck",loading_order={}}
end
road(1,8,9,1);road(2,20,11,1);road(3,31,14,2)
w.stock_rail_stations={}
local function platform(i,x,z)
  local st={id=i,owner="Rail",axis=0,tiles={}}
  w.stock_rail_stations[i]=st
  for j=0,2 do
    local t=id(x+j,z)
    w.tiles[t]={owner=st.owner,rail_tracks=1,rail_station_id=i,rail_station_axis=0}
    st.tiles[#st.tiles+1]=t
  end
end
platform(1,17,14);platform(2,27,14)
local src_head,src_wagon,dst_head,dst_wagon=id(17,14),id(18,14),id(29,14),id(28,14)
local events,scans,B,b={},{},nil,nil
local function rebind()
  B=Road.bind(w,{random_u32=function() return 4294967295 end,
    house_at=function(x,z)
      if (x==29 or x==30) and z==12 then return {id=0,town=2} end
    end,
    station_union=function(views,open,scan,rating)
      return Goods.bind(w,w.rail,{roles={[1]="load",[2]="unload"},road_stations=views,
        town=function() return 2 end,pipeline=open,rating=rating,
        emit=function(e) events[#events+1]=e end,
        post_scan=function(s) scans[#scans+1]=s;return scan(s) end})
    end})
  b=B.rail
end
local function stock(vid,eng,cargo)
  w.fleet[vid]={id=vid,owner="Road",engine=eng,cargo=cargo,bought=0,units=0,
    delivered=0,revenue=0,batches={},cargo_age_counter=1}
end
stock(8,"wood_truck","wood");stock(9,"goods_truck","goods")
local function attempt(st,cargo)
  local g=Rules.goods(st,cargo)
  Rate.observe_loading(g,48,0,25);g.rating=255
end
rebind()
assert(#b.stations==5 and #B.stations==3,"Road only scans road, while allocation sees both modes")
assert(b.report(1).sources[1]==13 and not b.report(1).accepts)
assert(b.report(2).accepts and b.report(2).always_accepted and #b.report(2).sources==0)
assert(B.report(w.stations[3],"goods").accepts)
assert(Goods.mass(25)==33 and Goods.mass(25,3)==58 and Goods.mass(0)==21)
local sk=assert(Roster.entry(32))
assert(sk.stock_id==32 and sk.cargo_id==5 and sk.capacity==25 and sk.image_index==38 and sk.purchase_enabled==false)
assert(Roster.purchase_price(32)==1484 and Roster.stats({0,{stock_id=32,cargo_count=25}}).weight==80)
assert(not Roster.quote({kind="depot",owner="Rail",railtype=0,id=2},"Rail",{0,32},{roster_preview=true}))
assert(not b.vehicle({wagon=30,length=16,id=7,built=1950,speed=64,owner="Rail"}))
assert(b.vehicle({wagon=32,length=16,id=7,built=1950,speed=64,owner="Rail"}))
attempt(w.stations[1],"wood")
local function road_arrive(vid,station,full)
  local st=w.stations[station];local v=w.fleet[vid]
  v.road_stop_pose={0,0,0,st.tile}
  local o=B.ops(w.clock.counter)
  o.xy=Sim.xy
  o.slice=B.timing(v)
  v.load_state=Load.begin(st,v,vid==8 and 20 or 14,{full=full,no_load=not full},o)
  v.load_state.arrived_tick=w.clock.counter
end
Sim.company(w,"Rail")
local restored_loading=false
local rail_ready
local function tick(move)
  house.advance(w.clock,1,function(flat,t) B.tile_visit(flat%64,math.floor(flat/64),t) end)
  local t=w.clock.counter
  local ok,ready=b.loading_tick(t);assert(ok,ready);rail_ready=ready
  for _,st in ipairs(B.stations) do
    local s=w.stations[st.id]
    if #s.loading_order>0 then
      local o=B.ops(t)
      o.xy=Sim.xy
      local _,leave=Load.tick(s,w.fleet,o)
      for _,v in ipairs(leave) do Load.leave(s,w.fleet[v],o) end
      o.station_done(s)
    end
  end
  if move then move(t) end
  assert(b.after_motion(t) and not b.after_motion(t))
  Load.age_vehicle(w.fleet[8],1,185);Load.age_vehicle(w.fleet[9],1,185)
  B.after_vehicle_tick(t)
  local v=w.rail.vehicle
  if not restored_loading and v.visit==1 and v.load_state and v.units>0 and v.units<25 then
    w=copy(w);rebind();restored_loading=true
  end
end
local function until_true(predicate)
  for i=1,4000 do if predicate() then return end; tick() end
  error("Never reached required service phase.")
end

-- Produce actual forest wood and physically load/unload three #144 truck
-- receipts. Do not seed converted Goods or fabricate rail packet payout.
-- Two staged Goods outlets are added before the actual Sawmill release.
for cycle=1,3 do
  until_true(function() return #Rules.queue(B.stations[1],"wood")>0 end)
  tick(function() road_arrive(8,1,true) end)
  until_true(function() return not w.fleet[8].load_state end)
  assert(w.fleet[8].units==20)
  for _=1,230 do tick() end
  tick(function() road_arrive(8,2,false) end)
  until_true(function() return not w.fleet[8].load_state end)
  -- Genuine prior rounds reached the sawmill as wood; no waiting
  -- Goods allocation has occurred until the outlets attempt service.
  assert(w.fleet[8].delivered==cycle*20 and w.stock_timber_industries[13].wood_received==cycle*20)
end
assert(w.stock_timber_industries[13].produced.current.production+w.stock_timber_industries[13].produced.waiting==60)
-- Earlier unserviced offers have already been released and not allocated;
-- run three fresh source trips with both outlets now actively served.
local function rail_arrive(st,visit,head,wagon)
  tick(function(t) assert(b.arrive(st,visit,t,head,wagon)) end)
end
attempt(w.stations[2],"goods")
attempt(w.rail.stations[0x4001],"goods")
rail_arrive(1,1,src_head,src_wagon)
tick(function() road_arrive(9,2,true) end)
for cycle=4,6 do
  until_true(function() return #Rules.queue(B.stations[1],"wood")>0 end)
  tick(function() road_arrive(8,1,true) end)
  until_true(function() return not w.fleet[8].load_state end)
  for _=1,230 do tick() end
  tick(function() road_arrive(8,2,false) end)
  until_true(function() return not w.fleet[8].load_state end)
  assert(w.stock_timber_industries[13].wood_received==cycle*20)
end
until_true(function() return rail_ready and not w.fleet[9].load_state end)
assert(restored_loading and w.rail.vehicle.units==25 and w.fleet[9].units==14)
-- Mixed output was allocated once. There is no second Sawmill clock or
-- second Goods payment. Queue totals reconcile both physical cargoes.
local served=w.stock_timber_industries[13].produced.current.transported
local ra,ro=b.report(1).available,B.display_waiting(w.stations[2],"goods")
assert(served==25+14+ra+ro and served>=39 and served<=120)
tick(function(t) if rail_ready then assert(b.leave(1,t)) end end)
-- The source only grants departure on a matching station phase.
until_true(function()
  if not w.rail.vehicle.load_state then return true end
  if rail_ready then tick(function(t) assert(b.leave(1,t)) end) end
  return not w.rail.vehicle.load_state
end)
for _=1,240 do tick() end
tick(function(t) assert(b.arrive(2,2,t,dst_head,dst_wagon));road_arrive(9,3,false) end)
tick()
assert(w.rail.vehicle.units==20 and w.fleet[9].units==9)
w=copy(w);rebind()
local done=false
for _=1,350 do
  tick(function(t)
    if rail_ready and not done then assert(b.leave(2,t));done=true end
  end)
  if done and not w.fleet[9].load_state then break end
end
assert(done and w.rail.vehicle.delivered==25 and w.fleet[9].delivered==14)
assert(w.sites[2].received.goods==39,"The canonical town receipt ran exactly once per delivered crate")
assert(w.companies.Rail.paid_units==25 and w.companies.Rail.revenue==w.rail.vehicle.revenue)
local per_tick,expected,paid={},0,0
for _,e in ipairs(events) do
  if e.kind=="deliver" then
    assert(e.distance==10 and e.tile==dst_wagon and e.source_industry==13 and e.age>0)
    per_tick[e.tick]=(per_tick[e.tick] or 0)+e.units
    expected=expected+Income.regular(e.units,e.distance,e.age,6144,5,28)
  elseif e.kind=="fare" then paid=paid+e.amount end
end
local all={}
for t,n in pairs(per_tick) do assert(n==5);all[#all+1]=t end
table.sort(all)
assert(#all==5 and all[5]-all[1]==160 and expected==paid and paid>0)
print(("PASS #32 stock rail Goods %d/$%d and road %d/$%d; one forest/sawmill offer and town receipt across restore")
  :format(w.rail.vehicle.delivered,paid,w.fleet[9].delivered,w.fleet[9].revenue))
