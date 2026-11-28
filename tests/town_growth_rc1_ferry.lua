-- A fresh RC1 port, not an imported save: use production world generation
-- and the ordinary worker's quote, buy, order and company commands.
local four=arg[1]=="hub-four"
local compound=arg[1]=="hub-compound"
local demolition=compound or arg[1]=="hub-house"
local advertising=arg[1]=="hub-advertising"
local rotary=four or demolition or advertising or arg[1]=="hub-air"
local hub=rotary or arg[1]=="hub"
local mixed=hub or arg[1]=="mixed"
local ref=dofile("tests/fixtures/"..(advertising and "rc1-active-coastal-town-advertising-year" or compound and "rc1-active-coastal-compound-clear-town-year" or demolition and "rc1-active-coastal-house-clear-town-year" or four and "rc1-active-coastal-four-town-year" or rotary and "rc1-active-coastal-helicopter-town-year" or hub and "rc1-active-coastal-hub-town-year" or mixed and "rc1-active-bus-dock-town-year" or "rc1-active-ferry-town-year")..".lua")
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local S,T,Rebuild=m("sim"),m("openttd/terrain"),m("openttd/town_rebuild")
local native_files={settings={get=function() return nil end},get_dir_list=function(path)
  local list={}
  local stream=assert(io.popen("ls -1 "..path))
  for name in stream:lines() do list[#list+1]=name end
  stream:close()
  return list
end}
local s=m("campaign_generation")(native_files,mod,S,m("world_setup")).run({
  width=256,depth=256,year=1985,seed=1751,relief=0,sea=0,coast=0,rivers=2,trees=2,
  towns=3,larger_towns=4,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
})
local cap={road={start_year=1985,breakdowns=1,service_interval=150,foster=true},ferry={[207]=true},air={},oil_tanker=true}
s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
s.ship_paid_service=true
if hub then
  local assets,city,heli,ground,expansion=m("airport_manifest")(native_files,mod)
  cap.city_airport,cap.heliport,cap.ground_rotary,cap.expansion_airports=city,heli,ground,expansion
  assert(ground.helidepot)
  for id in pairs(assets) do cap.air[id]=true end
  cap.rail=m("rail_dispatch_manifest").scan(mod,false,false)
  s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
end
local Mount,Endpoint,Codec=m("campaign_authority_runtime"),m("campaign_authority_endpoint"),m("packed_campaign")
local N=Mount(S,mod,s,cap)
local A=Endpoint(S,N)
local revision
local owner="Stock comparison"
local id_bus
local function checked(r)
  assert(r.ok,r.why)
  revision=r.revision
  return r.value
end
local function action(kind,request)
  request=request or {}
  request.kind,request.revision=kind,revision
  return checked(A.command(owner,request))
end
local function transport(request)
  local quote=checked(A.transport_quote(owner,request))
  return action("transport_commit",{token=quote.token})
end
local function build()
  action("company_open")
  s.companies[owner].cash=80000000
  if mixed then
    local function cell(x,y) return S.id(x+1,y+1) end
    local function road(req)
      local quote=checked(A.road_quote(owner,req))
      return action("road_commit",{request=req,quote=quote})
    end
    road({tool="drag",first=cell(52,115),last=cell(58,115),axis=0,start_half=false,end_half=true})
    local depot=cell(59,115)
    road({tool="stock_terminal",first=depot,kind="depot",direction=0})
    road({tool="stock_terminal",first=cell(53,115),kind="bus",direction=0,through=true})
    road({tool="stock_terminal",first=cell(57,115),kind="bus",direction=0,through=true})
    local rb,lb=s.tiles[cell(53,115)].station,s.tiles[cell(57,115)].station
    assert(s.stations[rb].stock_station_id==0 and s.stations[lb].stock_station_id==1)
    local panel=checked(A.depot(owner,"road",depot))
    local bus
    for _,offer in ipairs(panel.offers) do
      if offer.request.engine=="leopard_bus" then bus=action("road_buy",offer.request);break end
    end
    assert(bus and s.fleet[bus].stock_pool_id==12);id_bus=bus
    action("road_order_add",{vehicle=bus,station=lb});action("road_order_add",{vehicle=bus,station=rb})
    action("road_toggle",{vehicle=bus})
  end
  local request={mode="ship",operation="build",kind="dock",tile=29757,adjacent=true}
  if mixed then
    local picker=checked(A.dock_join_choices(owner,request))
    for _,choice in ipairs(picker.choices) do
      if choice.id==0x4000 then request.join=choice.id end
    end
    assert(request.join)
  end
  local a=transport(request).id
  local b=transport({mode="ship",operation="build",kind="dock",tile=31026,adjacent=true}).id
  assert(s.stock_ship_stations[a].stock_station_id==0 and s.stock_ship_stations[b].stock_station_id==(mixed and 2 or 1))
  if hub then
    local function cell(x,y) return S.id(x+1,y+1) end
    local field={mode="air",operation="build",tile=cell(53,106),layout="helidepot",air_join=0,separate=false}
    local ap=checked(A.airport_join_choices(owner,field))
    local offered
    for _,choice in ipairs(ap.choices) do if choice.id==0 then offered=true end end
    assert(offered)
    local airport=transport(field).id
    assert(s.stock_small_airports[airport].stock_station_id==0)
    local req={tool="station",first=cell(53,109),last=cell(53,109),axis=0,length=1,tracks=1,separate=true,drag=true}
    local options=checked(A.rail_quote(owner,req,"road_join_choices"))
    offered=false
    for _,choice in ipairs(options.choices) do if choice.id==0 then offered=true end end
    assert(offered)
    req.road_station_id=0
    local rq=checked(A.rail_quote(owner,req))
    action("rail_commit",{token=rq.token})
    assert(s.stock_joined_stations[0].facilities==29)
  end
  local d=transport({mode="ship",operation="build",kind="depot",tile=29760,axis=0}).id
  assert(transport({mode="ship",operation="buy",depot=d,engine=207}).id=="ferry")
  assert(s.stock_owned_ferry.stock_pool_id==(mixed and 13 or 12))
  action("transport_start",{mode="ship",vehicle="ferry",depot=d,first=a,second=b})
end

local function start_air()
  local home=assert(s.stock_joined_stations[0].members.air)
  local away=transport({mode="air",operation="build",tile=S.id(46,91),layout="helidepot",separate=true}).id
  local aircraft=transport({mode="air",operation="buy",depot=home,engine=253}).id
  action("transport_start",{mode="air",first=away,second=home,vehicle=aircraft})
  return aircraft
end

local function start_train()
  local track=m("openttd/rail_track")
  local function cell(x,y) return S.id(x+1,y+1) end
  local function rail(r)
    local q=checked(A.rail_quote(owner,r))
    return action("rail_commit",{token=q.token})
  end
  rail({tool="track",first=cell(52,109),last=cell(52,109),track=track.X})
  rail({tool="track",first=cell(54,109),last=cell(59,109),track=track.X})
  rail({tool="station",first=cell(57,109),last=cell(57,109),axis=0,length=1,tracks=1,separate=true,drag=true})
  local depot=cell(60,109)
  rail({tool="depot",first=depot,direction=track.NE})
  local function assemble(operation,stock)
    local q=checked(A.rail_assembly(owner,depot))
    action("rail_assembly",{token=q.token,operation=operation,stock=stock})
  end
  assemble("engine",15)
  assemble("wagon",27)
  local q=checked(A.rail_assembly(owner,depot))
  local train
  for id,u in pairs(q.units) do if #u.stocks==2 and u.stocks[1]==15 and u.stocks[2]==27 then train=id end end
  assert(train)
  local home=s.stock_joined_stations[0].members.rail
  local other=assert(s.tiles[cell(57,109)].rail_station_id)
  action("transport_start",{mode="rail",vehicle=train,first=home,second=other})
end

local function clear_house()
  local expected=ref.house_clear
  local id=S.id((expected.x or 49)+1,(expected.z or 109)+1)
  local tile=assert(s.tiles[id])
  local house=assert(tile.source_house)
  local owner_id=house.town
  local town=assert(s.stock_town_growth.towns[owner_id])
  assert(house.id==(expected.house or 6) and (town.stock_id or owner_id-1)==(expected.town or 17))
  local c=assert(s.companies[owner])
  local ratings=assert(c.stock_town_authority_ratings)
  local saved_rating=ratings[owner_id]
  assert((saved_rating or 500)==expected.before)
  local request={operation="bulldoze",first=id}
  -- Test actual command refusal and quote, then restore the original
  -- published 1985 world condition before executing the deliberate edit.
  ratings[owner_id]=(expected.gate or 80)-1
  local denied=A.terrain_quote(owner,request)
  assert(not denied.ok and denied.why:find("refuses demolition",1,true))
  local policy=s.stock_road_town_policy
  local tolerance=policy.tolerance
  policy.tolerance=3
  assert(checked(A.terrain_quote(owner,request)).cost==expected.cost)
  policy.tolerance=tolerance
  ratings[owner_id]=saved_rating
  local quote=checked(A.terrain_quote(owner,request))
  assert(quote.cost==expected.cost and ratings[owner_id]==saved_rating)
  local cash=c.cash
  action("terrain_commit",{token=quote.token})
  for _,part in ipairs(expected.footprint or {id-1}) do
    assert(not s.tiles[part+1].house and not s.tiles[part+1].source_house)
  end
  assert(ratings[owner_id]==expected.after)
  assert(town.population==expected.population and town.num_houses==expected.houses and c.cash==cash-expected.cost)
end

local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local function same(tick,label,value,expected)
  assert(#value==#expected)
  for i,v in ipairs(expected) do
    assert(value[i]==v,("RC1 ferry tick %d %s field %d: got %s; expected %s"):format(
      tick,label,i,tostring(value[i]),tostring(v)))
  end
end
local function advertise(t,expected)
  local group=assert(s.stock_joined_stations[0])
  local town=assert(group.town)
  local st=assert(s.stock_ship_commercial.service.stations[group.service_station_id])
  local company=s.companies[owner]
  local offer=checked(A.town_authority(owner,town)).advertising[expected[1]]
  assert(town-1==17 and offer.affordable)
  local before,cash=st.passenger_rating_state.rating,company.cash
  local result=action("town_advertise",{town=town,cost=offer.cost,size=offer.key})
  same(t,"council advertising",{expected[1],result.cost,before,st.passenger_rating_state.rating,result.affected_cargos},expected)
  assert(company.cash==cash-offer.cost and st.mail_rating_state.rating==175)
end

local function snapshot(tick,expected)
  local corners,houses,towns=1,1,1
  local year=S.date(s)
  local book=s.stock_town_growth.towns
  for id,t in ipairs(s.tiles) do
    local x,y=S.xy(id)
    corners=fold(corners,T.corner(s.corner_grid,x,y))
    local h=t.source_house
    if h then houses=fold(houses,id-1,h.id,(book[h.town].stock_id or h.town-1),h.completed and 1 or 0,h.stage,h.counter,
      Rebuild.age(h,year),h.random_bits) end
  end
  for _,id in ipairs(s.stock_town_growth.order) do
    local town,site=book[id],s.sites[id]
    local p,m=town.supplied.passenger,town.supplied.mail
    towns=fold(towns,town.stock_id or id-1,site.tile-1,town.population,town.num_houses,town.grow_counter,
      town.growth_rate,town.time_until_rebuild,p.new_max or 0,p.new_act or 0,p.old_max or 0,p.old_act or 0,
      m.new_max or 0,m.new_act or 0,m.old_max or 0,m.old_act or 0)
  end
  same(tick,"ground, housing and town state",{corners,houses,towns},expected)
end

local digest,motion,ticks,poses,snapshots=1,1,0,0,0
local bus_hash,bus_count,joint_hash,joint_count,queue_hash,queue_count,both=1,0,1,0,1,0,0
local air_hash,air_count,three=1,0,0
local rail_hash,rail_count=1,0
local aircraft_id
local function joint(t)
  local service=s.stock_ship_commercial.service
  local group=assert(s.stock_joined_stations[0])
  local st=assert(service.stations[group.service_station_id])
  local road=assert(s.stations[group.members.road])
  if hub then
    assert(st.host_mode=="air" and group.members.rail and group.members.dock)
    local same_id=0
    for _,candidate in pairs(service.stations) do
      if candidate.stock_station_id==0 then same_id=same_id+1 end
    end
    assert(same_id==1)
  end
  assert(group.facilities==(hub and 29 or 20) and #st.tiles==(hub and 8 or 3) and st.stock==road.stock and st.passenger_rating_state==road.passenger_rating_state)
  local bus=s.fleet[id_bus]
  local motion=bus.road_speed_state or bus.road_stop_motion or {}
  local point=S.road_motion_frame(s,bus) or bus.road_stop_pose
  if point then
    bus_hash=fold(bus_hash,t,12,point[4]-1,point[1]-16,point[2]-16,motion.speed or 0,motion.subspeed or 0,motion.progress or 0)
    bus_count=bus_count+1
  end
  local waiting,order=0,{}
  for _,p in ipairs(st.stock.passenger or {}) do waiting=waiting+p.units end
  for _,id in ipairs(road.loading_order or {}) do
    local v=s.fleet[id]
    order[#order+1]={v.load_state.arrived_tick,v.stock_pool_id,1}
    waiting=waiting+v.load_state.reserved_units
  end
  for _,id in ipairs(st.loading_order or {}) do
    local v=service.vehicles[id]
    local layout=({rail=0,ship=2,air=3})[v.mode]
    order[#order+1]={v.load_state.arrived_tick,v.stock_station_physical_vehicle,layout}
    if v.carrying_parts then
      for _,body in ipairs(v.carrying_parts) do
        if body.cargo=="passenger" then waiting=waiting+body.load_state.reserved_units end
      end
    elseif v.cargo=="passenger" then
      waiting=waiting+v.load_state.reserved_units
    end
  end
  joint_hash=fold(joint_hash,t,group.tile-1,group.facilities,st.rating_phase,st.time_since_load,st.time_since_unload,
    waiting,st.passenger_rating_state.rating)
  joint_count=joint_count+1
  if #order>0 then
    table.sort(order,function(a,b) return a[1]==b[1] and a[2]<b[2] or a[1]<b[1] end)
    queue_hash=fold(queue_hash,t,#order)
    for _,r in ipairs(order) do queue_hash=fold(queue_hash,r[2],r[3]) end
    queue_count=queue_count+1
    if #order==3 then three=three+1 end
    if #order==2 then
      if both==0 then assert(t==ref.both_first and order[1][2]==12 and order[2][2]==13) end
      both=both+1
    end
  end
end
local function tick(t)
  if t==ref.first then same(t,"startup",{#s.stock_town_growth.order,unpack(s.passenger_rating_rng)},ref.startup) end
  if t==ref.build then build() end
  if rotary then
    if t==ref.air_build then aircraft_id=start_air() end
    if t>=ref.air_build then
      local p=assert(s.airport_owned_runs[aircraft_id])
      assert(p.phase~="blocked",p.failure)
      local v,air=p.vehicle,s.stock_owned_air_fleet[aircraft_id]
      local carrier=s.stock_ship_commercial.service.vehicles[0xC000+aircraft_id]
      local body=carrier and carrier.carrying_parts and carrier.carrying_parts[1]
      air_hash=fold(air_hash,t,air.stock_pool_ids[1],v.x-16,v.z-16,v.y,v.speed,v.subspeed,v.progress,v.direction,
        v.state,v.pos,s.stock_small_airports[p.target].stock_station_id,body and body.units or 0,
        v.loading and 1 or 0,v.hidden and 1 or 0)
      air_count=air_count+1
    end
  end
  if four then
    if t==ref.rail_build then start_train() end
    if t>=ref.rail_build then
      local r=assert(s.stock_rail_dispatch.runs[1])
      assert(not r.failure,r.failure)
      local parts=r.consist.parts
      local p=parts[r.consist.driving_backwards and #parts or 1]
      local cargo=s.stock_ship_commercial.service.vehicles[0x4000+r.paid_clock]
      rail_hash=fold(rail_hash,t,r.stock_pool_id,p.tile-1,p.pose.x-16,p.pose.y-16,r.z,r.speed,r.subspeed,
        r.progress,p.pose.direction,r.phase=="dwell" and 1 or 0,p.hidden and 1 or 0,cargo and cargo.units or 0)
      rail_count=rail_count+1
    end
  end
  if demolition and t==ref.clear_tick then clear_house() end
  if advertising and ref.campaigns[t] then advertise(t,ref.campaigns[t]) end
  digest=fold(digest,t,unpack(s.passenger_rating_rng));ticks=ticks+1
  if ref.towns[t] then snapshot(t,ref.towns[t]);snapshots=snapshots+1 end
  if t<=ref.build then return end
  local p,u=assert(s.ship_pilot),s.stock_owned_ferry
  assert(p.phase~="blocked",p.failure)
  local v=p.vehicle
  local c=s.stock_ship_commercial
  local cargo=c and c.service.vehicles[p.paid_clock]
  local row={u.stock_pool_id,v.tile-1,v.x-16,v.y-16,v.z,v.speed,v.subspeed or 0,v.progress,v.direction,
    cargo and cargo.units or 0,v.loading and 1 or 0,v.hidden and 1 or 0}
  motion=fold(motion,t,unpack(row));poses=poses+1
  if mixed then joint(t);return end
  if ref.sample[t] then same(t,"ferry pose and cargo",row,ref.sample[t]) end
  if ref.health[t] then same(t,"physical economy phase",
    {u.stock_pool_id,u.stock_fault.reliability,u.stock_fault.breakdown_chance},ref.health[t]) end
end

for day=1,365 do
  if day==51 or day==111 or day==233 then
    s=assert(Codec.decode(Codec.encode(s)))
    N=Mount(S,mod,s,cap)
    A=Endpoint(S,N)
    revision=s.authority_revision or 0
  end
  N.day(tick)
end
same(ref.last,"year end",{ticks,digest,poses,motion,snapshots},{ref.last-ref.first+1,ref.rng,ref.last-ref.build,ref.motion,6})
local p=s.ship_pilot
local freight=s.stock_ship_commercial.service.vehicles[p.paid_clock]
assert((freight.boarded or 0)>0 and freight.units>0 and s.stock_owned_ferry.price>0)
if mixed then
  same(ref.last,"bus, station and queues",{bus_hash,bus_count,joint_hash,joint_count,queue_hash,queue_count,both},
    {ref.bus,ref.bus_count,ref.station,ref.station_count,ref.loading,ref.loading_count,ref.both})
  if rotary then
    same(ref.last,"helicopter pose, orders and cargo",{air_hash,air_count,three},{ref.air,ref.air_count,ref.three})
    assert(s.airport_owned_runs[aircraft_id].arrivals>8)
    print(("PASS RC1 hub helicopter: %d exact aircraft frames across three packed reloads"):format(air_count))
  end
  if advertising then print("PASS RC1 small, medium and large town campaigns and the resulting town year") end
  if demolition then print("PASS RC1 company demolition: exact quote, signed authority and following town year") end
  if four then
    same(ref.last,"physical passenger engine and coach cargo",{rail_hash,rail_count},{ref.rail,ref.rail_count})
    print(("PASS RC1 four-mode hub: %d exact rail poses and coach cargo frames"):format(rail_count))
  end
  print(("PASS RC1 %s: %d world RNG ticks, %d ship poses, %d bus frames, %d shared queue frames and six town snapshots")
    :format(four and "hub with bus, ferry, rail and helicopter" or rotary and "hub with bus, ferry and helicopter" or hub and "hub with bus and ferry" or "bus + ferry",
      ticks,poses,bus_count,queue_count))
  return
end
-- This seeded two-dock route generates passengers but neither dock
-- has the eight acceptance eighths required to collect a fare.
assert((s.companies[owner].paid_units or 0)==0)
print(("PASS RC1 owned ferry: %d world RNG ticks, %d ship pose/cargo ticks, six snapshots of 51 towns and three packed reloads")
  :format(ticks,poses))
