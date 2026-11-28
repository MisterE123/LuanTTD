-- Real Luanti process + worker, normal in-world construction commands.
-- A rail platform attaches to an active bus stop and reopens as one station.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,Track=m("sim"),m("openttd/rail_track")
local owner="Rail Connection QA"
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local before=cp.read()
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  ferry={},air={},rail=m("rail_dispatch_manifest").scan(mod,false,false),oil_tanker=true,durable_actions=true}
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
local function cell(x,y) return y*128+x+1 end
local bus_origin,joined=cell(41,44),cell(43,47)
local first_rail,second_rail,depot_rail=cell(43,53),cell(49,53),cell(51,53)
if not before then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,trees=2,
    towns=4,custom_towns=4,larger_towns=3,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
  })
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
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
local function rail(req)
  local q=ask("rail_quote",{request=req})
  return command("rail_commit",{token=q.token})
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
  local track=assert(s.stock_rail_stations[group.members.rail])
  local service=assert(s.stock_ship_commercial.service)
  local st=assert(service.stations[group.service_station_id])
  local run=assert(s.stock_rail_dispatch.runs[1])
  local unit=assert(service.vehicles[0x4000+run.paid_clock])
  local _,bus=next(s.fleet)
  assert(group.facilities==5 and group.tile==joined and track.sign_tile==joined and track.stock_station_id==road.stock_station_id)
  assert(st.stock==road.stock and st.passenger_rating_state==road.passenger_rating_state and #st.tiles==2)
  assert(st.rating_phase==road.passenger_rating_phase and st.time_since_load==road.time_since_load)
  assert(not run.failure and bus.stock_bus,run.failure)
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
    rail({tool="track",first=first_rail,last=depot_rail-1,track=Track.X})
    rail({tool="depot",first=depot_rail,direction=Track.NE})
    local req={tool="station",first=first_rail,last=first_rail,axis=0,length=1,tracks=1,separate=true,drag=true}
    local picks=ask("rail_join_choices",{request=req})
    local target=s.stations[b].stock_station_id
    local found
    for _,choice in ipairs(picks.choices) do if choice.id==target then found=true end end
    assert(found and picks.choices[1].id==nil)
    req.road_station_id=target
    rail(req)
    rail({tool="station",first=second_rail,last=second_rail,axis=0,length=1,tracks=1,separate=true,drag=true})
    local function assemble(operation,stock)
      local q=ask("rail_assembly",{depot=depot_rail})
      command("rail_assembly",{token=q.token,operation=operation,stock=stock})
    end
    assemble("engine",0)
    assemble("wagon",27)
    local q=ask("rail_assembly",{depot=depot_rail})
    local selected
    for id,v in pairs(q.units) do if #v.stocks==2 and v.stocks[1]==0 and v.stocks[2]==27 then selected=id end end
    s=state()
    command("transport_start",{mode="rail",vehicle=assert(selected),
      first=s.tiles[first_rail].rail_station_id,second=s.tiles[second_rail].rail_station_id})
  else
    local s=state()
    assert(s.passenger_house_clock.counter==before.passenger_house_clock.counter)
    local run,unit,bus=shared(s)
    local old,oldtrain,oldbus=shared(before)
    assert(run.stock_pool_id==old.stock_pool_id and unit.boarded==oldtrain.boarded and bus.units==oldbus.units)
  end
  local old=before and select(2,shared(before)).boarded or 0
  for _=1,65 do
    ask("advance",{days=2})
    local s=state()
    local run,unit,bus,st=shared(s)
    if unit.boarded and unit.boarded>(old or 0) and bus.delivered>0 then
      local frames=ask("actor_frames",{windows={{x=40,z=43,w=16,h=16}},fraction=1})
      local shown
      for _,frame in ipairs(frames) do for _,v in ipairs(frame.actors) do
        if v.mode=="rail" and v.owner==owner and v.complete_parts and #v.parts==2 then shown=true end
      end end
      if shown then
        result=("NATIVE RC1 JOINT RAIL %s: physical station %d, bus delivered %d, train boarded %d"):format(
          before and "REOPEN" or "SERVICE",st.stock_station_id,bus.delivered,unit.boarded)
        return {kind="stop"}
      end
    end
  end
  error("No active shared passenger station and passenger train found")
end
core.register_on_mods_loaded(function()
  co=coroutine.create(work)
  assert(client.start(cap,function(r) assert(r.ready);revision=r.revision;resumed(r) end,
    function(reason,_,_,detail)
      assert(reason=="stopped" and result,tostring(detail or reason))
      core.log("action",result)
      core.request_shutdown("Joined railway verified",false,0)
    end,"luanttd-wide-campaign.chk"))
end)
