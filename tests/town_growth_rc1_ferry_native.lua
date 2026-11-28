-- Two real Luanti authority-worker processes. Commands and cargo are
-- ordinary paid gameplay, not an imported stock save or seeded packets.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local owner="Stock Ferry QA"
local four=core.settings:get_bool("luanttd_qa_coastal_four",false)
local demolition=core.settings:get_bool("luanttd_qa_house_clear",false)
local rotary=four or demolition or core.settings:get_bool("luanttd_qa_coastal_air",false)
local hub=rotary or core.settings:get_bool("luanttd_qa_coastal_hub",false)
local mixed=hub or core.settings:get_bool("luanttd_qa_join_bus_dock",false)
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local previous=Checkpoint.read()
local client=m("campaign_authority_client")(core,mod)
local files={}
for _,kind in ipairs({"models","textures"}) do
  for _,name in ipairs(core.get_dir_list(mod.."/"..kind,false)) do files[name]=true end
end
local cap={road={start_year=1985,breakdowns=1,service_interval=150,foster=true},ferry={},air={},
  oil_tanker=true,durable_actions=true}
cap.ferry[207]=files["bl_ffp_passenger_ferry.obj"] and files["bl_harbor_ferry_palette.png"]
assert(cap.ferry[207])
if hub then
  local assets,city,heli,ground,expansion=m("airport_manifest")(core,mod)
  assert(ground.helidepot)
  for id in pairs(assets) do cap.air[id]=true end
  cap.city_airport,cap.heliport,cap.ground_rotary,cap.expansion_airports=city,heli,ground,expansion
  cap.rail=m("rail_dispatch_manifest").scan(mod,false,false)
end
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
if not previous then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=256,depth=256,year=1985,seed=1751,relief=0,sea=0,coast=0,rivers=2,trees=2,
    towns=3,larger_towns=4,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
  })
  s.ship_paid_service=true
  if hub then
    s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
    s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  end
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  Checkpoint.write_state(s)
end
local co,revision,result
local function resumed(r)
  local ok,req=coroutine.resume(co,r)
  assert(ok,req)
  if req then assert(client.query(req,resumed)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,owner
  local r=assert(coroutine.yield(fields))
  assert(r.ok,r.why)
  revision=r.revision or revision
  return r.value
end
local function command(kind,fields)
  fields=fields or {}
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields})
end
local function transport(req)
  local q=ask("transport_quote",{request=req})
  return command("transport_commit",{token=q.token})
end
local function counts()
  ask("checkpoint")
  local s=assert(Checkpoint.read())
  local p=assert(s.ship_pilot)
  local unit=assert(s.stock_owned_ferry)
  assert(p.phase~="blocked" and p.owned and unit.stock_pool_id==(mixed and 13 or 12),p.failure)
  local c=assert(s.companies[owner])
  local service=s.stock_ship_commercial.service
  local hull=assert(service.vehicles[p.paid_clock])
  local bus
  if mixed then
    local group=assert(s.stock_joined_stations[0])
    local station=assert(service.stations[group.service_station_id])
    local road=assert(s.stations[group.members.road])
    assert(station.stock==road.stock and station.passenger_rating_state==road.passenger_rating_state)
    assert(#station.tiles==(hub and 8 or 3) and group.facilities==(hub and 29 or 20) and station.stock_station_id==0 and hull.stock_station_physical_vehicle==13)
    for _,v in pairs(s.fleet) do if v.stock_pool_id==12 then bus=v end end
    assert(bus and bus.engine=="leopard_bus")
  end
  local air
  if rotary then
    air=assert(s.airport_owned_runs and s.airport_owned_runs[1])
    local unit=assert(s.stock_owned_air_fleet[1])
    assert(air.phase~="blocked",air.failure)
    assert(unit.stock_pool_ids[1]==14 and air.first~=unit.hangar and air.second==unit.hangar)
    assert(s.stock_small_airports[air.first].origin==90*256+46)
    assert(s.stock_small_airports[air.second].stock_station_id==0)
    if air.arrivals>0 then assert(unit.stock_fault.date_of_last_service>s.stock_bus_market.epoch+unit.day) end
  end
  local train
  if four then
    train=assert(s.stock_rail_dispatch.runs[1])
    assert(train.stock_pool_id==17 and train.stock_engine==15 and train.stock_wagon==27 and not train.failure)
    assert(train.shuttle and train.shuttle.first==s.stock_joined_stations[0].members.rail)
  end
  return s,p,hull.boarded or 0,c.revenue or 0,bus,air,train
end
local function work()
  local first=previous and previous.companies[owner]
  if not first then
    ask("advance",{days=4})
    command("company_open")
    local first={mode="ship",operation="build",kind="dock",tile=29757,adjacent=true}
    if mixed then
      local function cell(x,y) return y*256+x+1 end
      local function road(request)
        local q=ask("road_quote",{request=request})
        return command("road_commit",{request=request,quote=q})
      end
      road({tool="drag",first=cell(52,115),last=cell(58,115),axis=0,start_half=false,end_half=true})
      local dp=cell(59,115)
      road({tool="stock_terminal",first=dp,kind="depot",direction=0})
      road({tool="stock_terminal",first=cell(53,115),kind="bus",direction=0,through=true})
      road({tool="stock_terminal",first=cell(57,115),kind="bus",direction=0,through=true})
      local panel=ask("depot",{mode="road",depot=dp})
      local bus
      for _,q in ipairs(panel.offers) do if q.request.engine=="leopard_bus" then bus=command("road_buy",q.request);break end end
      assert(bus)
      ask("checkpoint")
      local s=assert(Checkpoint.read())
      command("road_order_add",{vehicle=bus,station=s.tiles[cell(57,115)].station})
      command("road_order_add",{vehicle=bus,station=s.tiles[cell(53,115)].station})
      command("road_toggle",{vehicle=bus})
      local picks=ask("dock_join_choices",{request=first})
      for _,choice in ipairs(picks.choices) do if choice.id==0x4000 then first.join=choice.id;break end end
      assert(first.join)
    end
    local da=transport(first)
    local db=transport({mode="ship",operation="build",kind="dock",tile=31026,adjacent=true})
    if hub then
      local function cell(x,y) return y*256+x+1 end
      local field={mode="air",operation="build",tile=cell(53,106),layout="helidepot",air_join=0,separate=false}
      local ap=ask("airport_join_choices",{request=field})
      local offered
      for _,choice in ipairs(ap.choices) do if choice.id==0 then offered=true end end
      assert(offered)
      transport(field)
      local r={tool="station",first=cell(53,109),last=cell(53,109),axis=0,length=1,tracks=1,separate=true,drag=true}
      local choices=ask("rail_join_choices",{request=r})
      offered=false
      for _,choice in ipairs(choices.choices) do if choice.id==0 then offered=true end end
      assert(offered)
      r.road_station_id=0
      local q=ask("rail_quote",{request=r})
      command("rail_commit",{token=q.token})
    end
    local dp=transport({mode="ship",operation="build",kind="depot",tile=29760,axis=0})
    assert(transport({mode="ship",operation="buy",depot=dp.id,engine=207}).id=="ferry")
    command("transport_start",{mode="ship",vehicle="ferry",depot=dp.id,first=da.id,second=db.id})
    if rotary then
      ask("checkpoint")
      local s=assert(Checkpoint.read())
      local home=assert(s.stock_joined_stations[0].members.air)
      local away=transport({mode="air",operation="build",tile=90*256+46,layout="helidepot",separate=true}).id
      local aircraft=transport({mode="air",operation="buy",depot=home,engine=253}).id
      command("transport_start",{mode="air",vehicle=aircraft,first=away,second=home})
    end
    if demolition then
      for _=1,4 do ask("advance",{days=4}) end
      ask("checkpoint")
      local id=109*256+50
      local s=assert(Checkpoint.read())
      local h=assert(s.tiles[id].source_house)
      local town=s.stock_town_growth.towns[h.town]
      assert(h.id==6 and (town.stock_id or h.town-1)==17)
      local c=s.companies[owner]
      local before=assert(c.stock_town_authority_ratings[h.town])
      local q=ask("terrain_quote",{request={operation="bulldoze",first=id}})
      assert(q.cost==500)
      command("terrain_commit",{token=q.token})
      ask("checkpoint")
      local changed=assert(Checkpoint.read())
      local after=changed.stock_town_growth.towns[h.town]
      assert(not changed.tiles[id].house and not changed.tiles[id].source_house)
      assert(after.population==town.population-30 and after.num_houses==town.num_houses-1)
      assert(changed.companies[owner].cash==c.cash-500)
      assert(changed.companies[owner].stock_town_authority_ratings[h.town]==before-80)
    end
    if four then
      -- The year witness buys its train in late January; let the
      -- ordinary company and dated engine roster advance to that point.
      for _=1,5 do ask("advance",{days=4}) end
      -- The ordinary game has a real starting budget. Finance its fifth
      -- vehicle body through the normal company loan controls.
      for _=1,7 do command("company_loan",{amount=10000}) end
      local function cell(x,y) return y*256+x+1 end
      local Track=m("openttd/rail_track")
      local function rail(r)
        local q=ask("rail_quote",{request=r})
        command("rail_commit",{token=q.token})
      end
      rail({tool="track",first=cell(52,109),last=cell(52,109),track=Track.X})
      rail({tool="track",first=cell(54,109),last=cell(59,109),track=Track.X})
      rail({tool="station",first=cell(57,109),last=cell(57,109),axis=0,length=1,tracks=1,separate=true,drag=true})
      local depot=cell(60,109)
      rail({tool="depot",first=depot,direction=Track.NE})
      for i,stock in ipairs({15,27}) do
        local q=ask("rail_assembly",{depot=depot})
        local offers={}
        for _,offer in ipairs(i==1 and q.engines or q.wagons) do offers[#offers+1]=offer.id end
        assert((", "..table.concat(offers,", ")..", "):find(", "..stock..", ",1,true),
          ("Stock part %d missing from actual depot offers: %s"):format(stock,table.concat(offers,", ")))
        command("rail_assembly",{token=q.token,operation=i==1 and "engine" or "wagon",stock=stock})
      end
      local q=ask("rail_assembly",{depot=depot})
      local train
      for id,u in pairs(q.units) do if #u.stocks==2 and u.stocks[1]==15 and u.stocks[2]==27 then train=id end end
      assert(train)
      ask("checkpoint")
      local s=assert(Checkpoint.read())
      local home=s.stock_joined_stations[0].members.rail
      local away=assert(s.tiles[cell(57,109)].rail_station_id)
      command("transport_start",{mode="rail",vehicle=train,first=home,second=away})
    end
  end
  local prior_ferry=first and previous.stock_ship_commercial.service.vehicles[previous.ship_pilot.paid_clock]
  local baseline_boarded,baseline_money=prior_ferry and prior_ferry.boarded or 0,first and first.revenue or 0
  local baseline_tick=previous and previous.passenger_house_clock.counter or 0
  local baseline_air=rotary and first and previous.airport_owned_runs[1].arrivals or 0
  local baseline_train=four and first and previous.stock_rail_dispatch.runs[1].shuttle.arrivals or 0
  local baseline_bus=0
  if four and first then
    for _,v in pairs(previous.fleet) do
      if v.stock_pool_id==12 then baseline_bus=assert(v.last_arrival).tick;break end
    end
    assert(baseline_bus>0)
  end
  if first then
    local s,p,boarded,money,bus,air,train=counts()
    assert(s.passenger_house_clock.counter==baseline_tick and boarded==baseline_boarded and money==baseline_money)
    assert(p.arrivals==previous.ship_pilot.arrivals)
    if rotary then assert(air.arrivals==baseline_air) end
    if demolition then
      local id=109*256+50
      local now,prior=s.tiles[id].source_house,previous.tiles[id].source_house
      assert((now and now.id)==(prior and prior.id))
      local town=18 -- physical TownID 17 in the one-based Luanti town book
      assert(s.companies[owner].stock_town_authority_ratings[town]
        ==previous.companies[owner].stock_town_authority_ratings[town])
    end
    if four then
      assert(train.shuttle.arrivals==baseline_train and bus.last_arrival.tick==baseline_bus)
    end
  end
  for _=1,(mixed and 43 or 22) do
    ask("advance",{days=4})
    local state,p,boarded,revenue,bus,air,train=counts()
    if boarded>baseline_boarded and (not mixed or bus.units>0) and (not rotary or air.arrivals>baseline_air) and
        (not four or train.shuttle.arrivals>baseline_train and (bus.last_arrival and bus.last_arrival.tick or 0)>baseline_bus) then
      assert(state.stock_owned_ferry.stock_fault.reliability<65535 and p.arrivals>=2 and (mixed or revenue==0))
      result=("NATIVE RC1 FERRY %s: %d boarded, VehicleID %d, elapsed tick %d"):format(
        first and "REOPEN" or "SERVICE",boarded,state.stock_owned_ferry.stock_pool_id,state.passenger_house_clock.counter)
      if mixed then result=result..(", bus carries %d through the same physical station"):format(bus.units) end
      if rotary then result=result..(", helicopter made %d arrivals"):format(air.arrivals) end
      if four then result=result..(", train made %d arrivals, bus last arrived at tick %d"):format(train.shuttle.arrivals,bus.last_arrival.tick) end
      if demolition then result=result..", stock house clear retained" end
      return {kind="stop"}
    end
  end
  error("No ordinary ferry boarding")
end
core.register_on_mods_loaded(function()
  co=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resumed(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and result,tostring(detail or reason))
    core.log("action",result)
    core.request_shutdown("Stock ferry worker verified",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
