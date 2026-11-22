-- SPDX-License-Identifier: GPL-2.0-only
-- A #30 leg and road Goods wagon share a single industry/station ledger.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local P,Rate,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local Catch=m("openttd/station_catchment")(P,Rate)
local Coal=m("openttd/coal_industry")(P,Rate,Catch,Income)
local Timber=m("openttd/timber_industry")(P,Catch,Rate,Income,Coal,m("openttd/town_goods"))
local Oil=m("openttd/oil_industry")(m("openttd/farm_factory_industry"),P,Catch,Rate,Income,Coal,Timber)
local Roster,Timing,Factory=m("openttd/rail_roster"),m("openttd/loading_timing"),m("road_loading_runtime")
local Station=m("station_rating_runtime")(Sim,Rate,P)
local RailStation=m("rail_coal_service")(Sim,Coal,Catch,Roster,P,Rate,Station,Income,Factory,Timing)
local Service=m("rail_oil_service")(Sim,Oil,Catch,Roster,RailStation,P,Rate,Station,Factory,Timing)
local Pipeline=m("oil_industry_runtime")(Oil,m("timber_industry_runtime"),Catch)
local RoadLoader=Factory(Timing,P)
local id=Sim.id
local w=Sim.new(1751)
w.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
local function copy(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local y={};for k,v in pairs(x) do y[k]=copy(v) end;return y
end
local function road(num,x,z,owner)
  return {id=num,owner=owner,town=1,x=x-1,z=z-1,tile=id(x,z),
    loading_order={},tiles={{x=x-1,y=z-1,kind="truck"}},stock={}}
end
w.oil_store=Pipeline.new()
w.rail=Service.new()
w.road_views={road(1,9,8,"Rival"),road(2,26,9,"Rail"),road(3,42,9,"Rail")}
w.industries={[0x3000]=Oil.new("oil_well",0x3000,9,4,{completed=true,original=true,counter=1}),
  [0x3001]=Oil.new("oil_refinery",0x3001,26,4,{completed=true,original=true,counter=1})}
w.stock_rail_stations={}
local function station(i,x,z)
  local st={id=i,owner="Rail",axis=0,tiles={}}
  w.stock_rail_stations[i]=st
  for j=0,2 do
    local t=id(x+j,z)
    w.tiles[t]={owner=st.owner,rail_tracks=1,rail_station_id=i,rail_station_axis=0}
    st.tiles[#st.tiles+1]=t
  end
end
station(1,10,9);station(2,27,9)
local src_head,src_wagon,dst_head,dst_wagon=id(10,9),id(11,9),id(29,9),id(28,9)
w.clock={cursor=1,tick=0}
w.farm_town=1
local b,refs,events,conversions=nil,nil,{},{}
local function rebind()
  refs={}
  for _,ind in pairs(w.industries) do for _,t in ipairs(ind.tiles) do refs[t.z*64+t.x]=true end end
  b=Service.bind(w,w.rail,{roles={[1]="load",[2]="unload"},road_stations=w.road_views,
    emit=function(e) events[#events+1]=e end,
    post_scan=function(x) conversions[#conversions+1]=x end,
    pipeline=function(st,covers)
      return Pipeline.bind(w,w.oil_store,{width=Sim.W,height=Sim.H,xy=Sim.xy,coverage=covers,
        stations=st,industries=w.industries,house_at=function(x,z)
          if (x==40 and z==8) or (x==41 and z==9) then return {id=0,town=1} end
        end})
    end})
end
rebind()
assert(#b.stations==5 and b.stations[4]==w.rail.stations[0x4001])
assert(b.stations[1]==w.road_views[1] and not b.report(1).accepts and b.report(2).accepts)
assert(b.pipeline.report(3,"goods").accepts and not b.pipeline.report(2,"goods").accepts)
assert(Service.mass(0)==24 and Service.mass(30)==54 and Service.mass(30,3)==114)
-- A single source offer sees both modes in the same owner/rating
-- allocation: rating 127 produces eight units total, not eight each.
do
  local list={copy(b.stations[1]),copy(b.stations[4])}
  for _,st in ipairs(list) do
    local g=Oil.goods(st,"oil");g.rating=127;g.last_speed=48
  end
  local moved=Oil.distribute(w.industries[0x3000],"oil",16,list,b.coverage,{})
  assert(moved==8 and list[1].stock.oil[1].units==4 and list[2].stock.oil[1].units==4)
  assert(list[2].stock.oil[1].origin_tile==nil)
end
assert(not b.vehicle({wagon=29,length=16,id=7,built=1950,speed=64,owner="Rail"}))
assert(b.vehicle({wagon=30,length=16,id=7,built=1950,speed=64,owner="Rail"}))
local view=w.rail.stations[0x4001]
Oil.goods(view,"oil").rating=255
-- The only competing real Oil queue is a distinct truck interface to
-- the same source. It does not get a second population/production timer.
local rival=Oil.goods(w.road_views[1],"oil")
rival.rating,rival.last_speed=127,48
local goods=Oil.goods(w.road_views[2],"goods")
goods.rating=255
w.cargo_road={id=8,owner="Rail",cargo="goods",batches={},units=0,
  cargo_age_counter=1,revenue=0,delivered=0,cargo_tile=w.road_views[2].tile}
local function road_ops(tick)
  local pipe=b.pipeline
  local r=w.cargo_road
  local seq=0
  local staged=false
  local o={slice=5,gradual=true,xy=Sim.xy,
    queue=function(st) return Oil.queue(st,"goods") end,
    accepts=function(st) return pipe.report(st.id,"goods").accepts end,
    attempt=function(st,v,left) Catch.observe_loading(Oil.goods(st,"goods"),"road",96,1950,1950,left) end,
    pickup=function(st,_,p) P.pickup(p,{id=st.id,tile=r.cargo_tile},Sim.xy) end,
    deliver=function(st,_,p)
      seq=seq+1
      local out=assert(pipe.stage(st.id,tick,"road_goods:"..r.visit..":"..tick..":"..seq,p,r.cargo_tile))
      staged=true
      assert(out.units==p.units and out.distance==16 and out.town==1)
      return out.payment
    end,
    payment=function(_,v,p)
      if p.delivered==0 then return end
      local c=Sim.company(w,v.owner)
      c.cash,c.revenue,c.units,c.paid_units=c.cash+p.route,c.revenue+p.route,c.units+p.delivered,c.paid_units+p.delivered
      v.revenue,v.delivered=v.revenue+p.route,v.delivered+p.delivered
    end}
  function o.finish(st) if staged then assert(pipe.finish(st.id,tick)) end end
  return o
end
local function road_begin(st,visit,full)
  local v=w.cargo_road
  v.visit,v.cargo_tile=visit,st.tile
  return RoadLoader.begin(st,v,14,{full=full,no_load=not full},road_ops(w.clock.tick))
end
local rail_ready,road_ready
local function step(callback)
  w.clock.tick=w.clock.tick+1
  local tick=w.clock.tick
  Coal.landscape_tick(w.clock,6,6,function(flat)
    if refs[flat] then b.pipeline.tile_visit(flat%64,math.floor(flat/64),tick) end
  end)
  local ok,ready=b.loading_tick(tick)
  assert(ok,ready);rail_ready=ready
  assert(not b.loading_tick(tick))
  local v=w.cargo_road
  road_ready=false
  if v.load_state then
    local st=w.road_views[v.load_state.station]
    local o=road_ops(tick)
    local _,r=RoadLoader.tick(st,{[v.id]=v},o)
    o.finish(st);road_ready=#r>0
  end
  if callback then callback(tick) end
  assert(b.after_motion(tick) and not b.after_motion(tick))
  RoadLoader.age_vehicle(v,1,185)
  b.pipeline.produce(0x3000,tick);b.pipeline.produce(0x3001,tick)
end
local function wait(test,callback,n)
  for _=1,n or 4000 do
    if test() then return end
    step(callback)
  end
  assert(test(),"Source freight failed to complete")
end
step(function(t)
  local wrong,why=b.arrive(1,1,t,src_head,id(15,9))
  assert(not wrong and why=="ACTUAL_WAGON_PLATFORM_TILE_REQUIRED")
  local ok=assert(b.arrive(1,1,t,src_head,src_wagon))
  assert(ok==b.arrive(1,1,t,src_head,src_wagon))
  assert(ok.full and ok.platform_tiles==3)
  road_begin(w.road_views[2],1,true)
end)
wait(function() return w.rail.vehicle.units>=5 end)
local _,payload=Service.mass(w.rail.vehicle.units)
assert(payload==5 and not rail_ready)
local stable=w
w=copy(w)
w.tiles[src_head].rail_station_id=nil
rebind()
local ok,reason=b.loading_tick(w.clock.tick+1)
assert(not ok and reason=="OIL_RAIL_PLATFORM_LOST" and w.rail.vehicle.units==5)
w=stable
local before=w.rail.vehicle.load_state.ticks
w=copy(w);rebind()
assert(w.rail.vehicle.load_state.ticks==before and w.rail.vehicle.cargo_tile==src_wagon)
local function depart(t)
  if rail_ready then assert(b.leave(1,t) and not b.leave(1,t)) end
end
wait(function() return not w.rail.vehicle.load_state end,depart)
assert(w.rail.vehicle.units==30 and w.rail.vehicle.batches[1].origin_tile==src_wagon)
for _=1,520 do step() end -- between actual physical platform endpoints
step(function(t)
  local l=assert(b.arrive(2,2,t,dst_head,dst_wagon))
  assert(l.no_load and l.unload_units==30)
end)
wait(function() return w.rail.vehicle.units==25 end)
assert(w.rail.vehicle.delivered==0,"Source accumulated unload must not settle early")
assert(conversions[1].conversion[1].produced==5 and conversions[1].conversion[1].consumed==5)
assert(w.industries[0x3001].produced[1].waiting==5)
w=copy(w);rebind()
local depart_train,depart_road=false,false
wait(function() return depart_train and depart_road end,function(t)
  if rail_ready then assert(b.leave(2,t));depart_train=true end
  if road_ready then
    RoadLoader.leave(w.road_views[2],w.cargo_road,road_ops(t))
    depart_road=true
  end
end)
assert(w.rail.vehicle.delivered==30 and w.cargo_road.units==14)
local boarded,delivered,fare,previous,settles=0,0,0,nil,0
local by_tick={}
for _,e in ipairs(events) do
  if e.kind=="board" then
    assert(e.units>0 and e.units<=5 and e.tile==src_wagon)
    boarded=boarded+e.units
  elseif e.kind=="deliver" then
    assert(e.units>0 and e.units<=5 and e.tile==dst_wagon and e.distance==Sim.distance(src_wagon,dst_wagon) and e.age>=2)
    if not by_tick[e.tick] then
      if previous then assert(e.tick-previous==40) end
      previous=e.tick
    end
    by_tick[e.tick]=(by_tick[e.tick] or 0)+e.units;delivered=delivered+e.units
  elseif e.kind=="fare" then
    assert(e.units==30 and e.amount>0);fare=fare+e.amount;settles=settles+1
  end
end
assert(boarded==30 and delivered==30 and settles==1 and fare==w.rail.vehicle.revenue)
for _,n in pairs(by_tick) do assert(n==5) end
local goods_at_refinery=0
for _,p in ipairs(Oil.queue(w.road_views[2],"goods")) do goods_at_refinery=goods_at_refinery+p.units end
assert(goods_at_refinery+w.industries[0x3001].produced[1].waiting==16)
assert(#conversions==6)
for _,scan in ipairs(conversions) do assert(scan.conversion[1].produced==5 and scan.conversion[1].consumed==5) end
for _=1,210 do step() end
step(function() road_begin(w.road_views[3],2,false) end)
local parked=false
wait(function() return parked end,function(t)
  if road_ready then
    RoadLoader.leave(w.road_views[3],w.cargo_road,road_ops(t))
    parked=true
  end
end,300)
assert(w.cargo_road.delivered==14 and fare==270 and w.cargo_road.revenue==165)
assert(#w.road_views[1].stock.oil>0)
local c=Sim.company(w,"Rail")
assert(c.paid_units==44 and c.revenue==fare+w.cargo_road.revenue and c.cash==100000+c.revenue)
assert(w.industries[0x3001].was_cargo_delivered and w.industries[0x3001].accepted[1].waiting==0)
print(("PASS: rail tanker 30,000 L, 54t loaded, six true wagon pulses; rail $%d and road Goods $%d, two restores, one well/refinery"):format(fare,w.cargo_road.revenue))
