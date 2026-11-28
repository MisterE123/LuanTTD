-- Real Luanti process + worker, normal in-world construction commands.
-- An airport attaches to an active bus stop and reopens as one station.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim=m("sim")
local owner="Airport Connection QA"
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local before=cp.read()
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  ferry={},air={[216]=true},oil_tanker=true,durable_actions=true}
assert(m("airport_manifest")(core,mod)[216])
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
local function cell(x,y) return y*128+x+1 end
local bus_origin,joined=cell(41,44),cell(43,47)
local first_air,second_air=cell(43,52),cell(47,93)
if not before then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,trees=2,
    towns=4,custom_towns=4,larger_towns=3,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
  })
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
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
  assert(group.facilities==12 and group.tile==joined and air.sign_tile==joined and air.stock_station_id==road.stock_station_id)
  assert(st.stock==road.stock and st.passenger_rating_state==road.passenger_rating_state and #st.tiles==13)
  assert(st.rating_phase==road.passenger_rating_phase and st.time_since_load==road.time_since_load)
  assert(run.phase~="blocked" and bus.stock_bus,run.failure)
  return run,unit,bus,st
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
  else
    local s=state()
    assert(s.passenger_house_clock.counter==before.passenger_house_clock.counter)
    local run,unit,bus=shared(s)
    local old,oldplane,oldbus=shared(before)
    assert(run.arrivals==old.arrivals and unit.boarded==oldplane.boarded and bus.units==oldbus.units)
  end
  local old=before and before.stock_ship_commercial.service.vehicles[0xC001].boarded or 0
  for _=1,65 do
    ask("advance",{days=2})
    local s=state()
    local run,unit,bus,st=shared(s)
    if unit.boarded and unit.boarded>(old or 0) and bus.delivered>0 and
        (not before and run.vehicle.loading or before and run.arrivals>=1) then
      local frames=ask("actor_frames",{windows={{x=40,z=40,w=12,h=18}},fraction=1})
      local shown
      for _,frame in ipairs(frames) do for _,v in ipairs(frame.actors) do
        if v.mode=="air" and v.owner==owner and v.engine==216 and v.pos then shown=true end
      end end
      if shown then
        result=("NATIVE RC1 JOINT AIRPORT %s: physical station %d, bus delivered %d, aircraft boarded %d"):format(
          before and "REOPEN" or "SERVICE",st.stock_station_id,bus.delivered,unit.boarded)
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
