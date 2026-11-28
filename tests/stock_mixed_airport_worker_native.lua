-- Real Luanti process + worker, normal in-world construction commands.
-- An airport attaches to an active bus stop and reopens as one station.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim=m("sim")
local owner="Airport Connection QA"
local triple=core.settings:get_bool("luanttd_qa_triple_station",false)
local Track=triple and m("openttd/rail_track")
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local before=cp.read()
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  ferry={},air={[216]=true},oil_tanker=true,durable_actions=true}
if triple then cap.rail=m("rail_dispatch_manifest").scan(mod,false,false) end
assert(m("airport_manifest")(core,mod)[216])
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
local function cell(x,y) return y*128+x+1 end
local bus_origin,joined=cell(41,44),cell(43,47)
local first_air,second_air=cell(43,52),cell(47,93)
local first_rail,second_rail,depot_rail=cell(47,46),cell(53,46),cell(55,46)
if not before then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,trees=2,
    towns=4,custom_towns=4,larger_towns=3,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
  })
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
  if triple then s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true end
  cp.write_state(s)
end
local co,revision,result
local function resumed(r)
  local ok,q=coroutine.resume(co,r)
  assert(ok,q)
  if q then assert(client.query(q,resumed)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,owner
  local r=assert(coroutine.yield(fields));assert(r.ok,r.why)
  revision=r.revision or revision
  return r.value
end
local function command(kind,fields)
  fields=fields or {};fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields})
end
local function transport(req)
  local q=ask("transport_quote",{request=req})
  return command("transport_commit",{token=q.token})
end
local function road(req)
  local q=ask("road_quote",{request=req})
  return command("road_commit",{request=req,quote=q})
end
local function state()
  ask("checkpoint")
  return assert(cp.read())
end
local function shared(s)
  local road=assert(s.stations[s.tiles[joined].station])
  local group=assert(s.stock_joined_stations[road.stock_station_id])
  local air=assert(s.stock_small_airports[group.members.air])
  local service=assert(s.stock_ship_commercial.service)
  local st=assert(service.stations[group.service_station_id])
  local _,run=next(s.airport_owned_runs)
  local unit=assert(service.vehicles[0xC000+run.paid_clock])
  local _,bus=next(s.fleet)
  assert(group.facilities==(triple and 13 or 12) and group.tile==joined and air.sign_tile==joined and air.stock_station_id==road.stock_station_id)
  assert(st.stock==road.stock and st.passenger_rating_state==road.passenger_rating_state and #st.tiles==(triple and 14 or 13))
  assert(st.rating_phase==road.passenger_rating_phase and st.time_since_load==road.time_since_load)
  assert(run.phase~="blocked" and bus.stock_bus,run.failure)
  local train,rail_run
  if triple then
    rail_run=assert(s.stock_rail_dispatch.runs[1])
    train=assert(service.vehicles[0x4000+rail_run.paid_clock])
    local platform=assert(s.stock_rail_stations[group.members.rail])
    assert(platform.stock_station_id==group.id and platform.sign_tile==joined)
    assert(not service.stations[0x4000+platform.id] and not rail_run.failure)
  end
  return run,unit,bus,st,train,rail_run
end
local function work()
  if not before then
    command("company_open")
    road({tool="drag",first=cell(45,44),last=cell(46,44),axis=0,start_half=false,end_half=true})
    local dep=cell(47,44)
    local function terminal(kind,tile,direction,through)
      road({tool="stock_terminal",first=tile,kind=kind,direction=direction,through=through})
    end
    terminal("depot",dep,0)
    terminal("bus",bus_origin,0,true)
    terminal("bus",joined,3,true)
    local s=state()
    local a,b=s.tiles[bus_origin].station,s.tiles[joined].station
    local panel=ask("depot",{mode="road",depot=dep})
    local offer
    for _,o in ipairs(panel.offers) do if o.request.engine=="bus" then offer=o end end
    local bus=command("road_buy",assert(offer).request)
    command("road_order_add",{vehicle=bus,station=a})
    command("road_order_add",{vehicle=bus,station=b})
    command("road_toggle",{vehicle=bus})
    for _=1,37 do ask("advance",{days=4}) end
    local req={mode="air",operation="build",tile=first_air,layout="country"}
    local picks=ask("airport_join_choices",{request=req})
    local target=s.stations[b].stock_station_id
    local found
    for _,choice in ipairs(picks.choices) do if choice.id==target then found=true end end
    assert(found and picks.choices[1].id==nil)
    req.air_join=target
    local first=transport(req).id
    local second=transport({mode="air",operation="build",tile=second_air,layout="country",separate=true}).id
    local plane=transport({mode="air",operation="buy",depot=first,engine=216})
    command("transport_start",{mode="air",first=first,second=second,vehicle=plane.id})
    command("vehicle_order",{mode="air",vehicle=plane.id,order_revision=0,operation="load",row=1,destination=2})
    if triple then
      local function rail(request)
        local q=ask("rail_quote",{request=request})
        return command("rail_commit",{token=q.token})
      end
      rail({tool="track",first=first_rail,last=depot_rail-1,track=Track.X})
      rail({tool="depot",first=depot_rail,direction=Track.NE})
      local request={tool="station",first=first_rail,last=first_rail,axis=0,length=1,tracks=1,separate=true,drag=true}
      local picks=ask("rail_join_choices",{request=request})
      local found
      for _,choice in ipairs(picks.choices) do if choice.id==target then found=true end end
      assert(found and picks.choices[1].id==nil)
      request.road_station_id=target
      rail(request)
      rail({tool="station",first=second_rail,last=second_rail,axis=0,length=1,tracks=1,separate=true,drag=true})
      local function assemble(operation,stock)
        local q=ask("rail_assembly",{depot=depot_rail})
        command("rail_assembly",{token=q.token,operation=operation,stock=stock})
      end
      assemble("engine",0);assemble("wagon",27)
      local q=ask("rail_assembly",{depot=depot_rail})
      local selected
      for id,v in pairs(q.units) do if #v.stocks==2 and v.stocks[1]==0 and v.stocks[2]==27 then selected=id end end
      s=state()
      command("transport_start",{mode="rail",vehicle=assert(selected),
        first=s.tiles[first_rail].rail_station_id,second=s.tiles[second_rail].rail_station_id})
    end
  else
    local s=state()
    assert(s.passenger_house_clock.counter==before.passenger_house_clock.counter)
    local run,unit,bus,st,train,rail=shared(s)
    local old,oldplane,oldbus,oldstation,oldtrain,oldrail=shared(before)
    assert(run.arrivals==old.arrivals and unit.boarded==oldplane.boarded and bus.units==oldbus.units)
    if triple then
      assert(st.id==oldstation.id and train.boarded==oldtrain.boarded and rail.stock_pool_id==oldrail.stock_pool_id)
    end
  end
  local old=before and before.stock_ship_commercial.service.vehicles[0xC001].boarded or 0
  local old_train=before and triple and select(5,shared(before)).boarded or 0
  for _=1,65 do
    ask("advance",{days=2})
    local s=state()
    local run,unit,bus,st,train=shared(s)
    if unit.boarded and unit.boarded>(old or 0) and bus.delivered>0 and
        (not triple or train.boarded and train.boarded>(old_train or 0)) and
        (not before and run.vehicle.loading or before and run.arrivals>=1) then
      local frames=ask("actor_frames",{windows={{x=40,z=40,w=20,h=18}},fraction=1})
      local shown,rail_shown
      for _,frame in ipairs(frames) do for _,v in ipairs(frame.actors) do
        if v.mode=="air" and v.owner==owner and v.engine==216 and v.pos then shown=true end
        if v.mode=="rail" and v.owner==owner and v.complete_parts and #v.parts==2 then rail_shown=true end
      end end
      if shown and (not triple or rail_shown) then
        result=("NATIVE RC1 JOINT AIRPORT %s: physical station %d, bus delivered %d, aircraft boarded %d, train boarded %d"):format(
          before and "REOPEN" or "SERVICE",st.stock_station_id,bus.delivered,unit.boarded,train and train.boarded or 0)
        return {kind="stop"}
      end
    end
  end
  error("No active shared passenger station and aircraft found")
end
core.register_on_mods_loaded(function()
  co=coroutine.create(work)
  assert(client.start(cap,function(r) assert(r.ready);revision=r.revision;resumed(r) end,
    function(reason,_,_,detail)
      assert(reason=="stopped" and result,tostring(detail or reason))
      core.log("action",result)
      core.request_shutdown("Joined airport verified",false,0)
    end,"luanttd-wide-campaign.chk"))
end)
