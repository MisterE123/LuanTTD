-- Two real Luanti authority-worker processes. Commands and cargo are
-- ordinary paid gameplay, not an imported stock save or seeded packets.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local owner="Stock Ferry QA"
local hub=core.settings:get_bool("luanttd_qa_coastal_hub",false)
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
  return s,p,hull.boarded or 0,c.revenue or 0,bus
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
  end
  local prior_ferry=first and previous.stock_ship_commercial.service.vehicles[previous.ship_pilot.paid_clock]
  local baseline_boarded,baseline_money=prior_ferry and prior_ferry.boarded or 0,first and first.revenue or 0
  local baseline_tick=previous and previous.passenger_house_clock.counter or 0
  if first then
    local s,p,boarded,money=counts()
    assert(s.passenger_house_clock.counter==baseline_tick and boarded==baseline_boarded and money==baseline_money)
    assert(p.arrivals==previous.ship_pilot.arrivals)
  end
  for _=1,(mixed and 43 or 22) do
    ask("advance",{days=4})
    local state,p,boarded,revenue,bus=counts()
    if boarded>baseline_boarded and (not mixed or bus.units>0) then
      assert(state.stock_owned_ferry.stock_fault.reliability<65535 and p.arrivals>=2 and (mixed or revenue==0))
      result=("NATIVE RC1 FERRY %s: %d boarded, VehicleID %d, elapsed tick %d"):format(
        first and "REOPEN" or "SERVICE",boarded,state.stock_owned_ferry.stock_pool_id,state.passenger_house_clock.counter)
      if mixed then result=result..(", bus carries %d through the same physical station"):format(bus.units) end
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
