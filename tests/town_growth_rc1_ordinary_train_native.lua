-- Real Luanti worker, generated stock map, regular construction and
-- depot commands, real SQLite restart while heading to automatic service.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim,Track=m("sim"),m("openttd/rail_track")
local owner="Native Stock Rail"
local name="luanttd-wide-campaign.chk"
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),name)
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150,foster=true},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local initial=Checkpoint.read()
local function cell(x,z) return (z-1)*64+x end
local west,east,depot,road_depot=cell(44,56),cell(48,56),cell(50,56),cell(12,42)
if not initial then
  local G=m("campaign_generation")(core,mod,Sim,m("world_setup"))
  local s=G.run({width=64,depth=64,seed=1751,relief=0,sea=0,coast=0,rivers=0,towns=4,custom_towns=2})
  assert(s.stock_engine_startup_seed==1944356477 and s.stock_pool_authority)
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  assert(Sim.open_company(s,owner).stock_start.id==0)
  assert(Sim.build(s,owner,"road_depot",{road_depot}))
  Checkpoint.write_state(s)
end
local thread,revision,proof
local function resume(reply)
  local ok,req=coroutine.resume(thread,reply)
  assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,owner
  local r=assert(coroutine.yield(fields))
  if r.revision then revision=r.revision end
  assert(r.ok,tostring(r.why))
  return r.value
end
local function command(kind,args)
  args.kind,args.revision=kind,revision
  return ask("command",{command=args})
end
local function rail(req)
  local quote=ask("rail_quote",{request=req})
  command("rail_commit",{token=quote.token})
end
local function first_free_three(s)
  local ids={}
  local effect=s.stock_effect_vehicles or {}
  local i=0
  while #ids<3 do
    if not effect[i] then ids[#ids+1]=i end
    i=i+1
  end
  return ids
end
local function state()
  ask("checkpoint")
  local s=assert(Checkpoint.read())
  assert(s.companies[owner].stock_start.id==0)
  return s,s.stock_rail_dispatch and s.stock_rail_dispatch.runs[1]
end
local function actor_present()
  local rows=ask("actor_frames",{windows={{x=40,z=53,w=13,h=7}},fraction=1})
  for _,sector in ipairs(rows) do
    for _,r in ipairs(sector.actors) do
      if r.mode=="rail" and r.complete_parts and #r.parts==2 then
        assert(r.parts[1].kind=="steam" and r.parts[2].kind=="wagon")
        return true
      end
    end
  end
end
local function work()
  if not initial then
    rail({tool="track",first=cell(43,56),last=depot-1,track=Track.X})
    rail({tool="depot",first=depot,direction=Track.NE})
    for _,id in ipairs({west,east}) do
      rail({tool="station",first=id,last=id,axis=0,length=1,tracks=1,separate=true,drag=true})
    end
    local q=ask("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="engine",stock=0})
    local offers=ask("depot",{mode="road",depot=road_depot})
    local bus
    for _,offer in ipairs(offers.offers) do
      if offer.request.engine=="bus" and offer.request.cargo=="passenger" then bus=offer.request end
    end
    assert(bus,"Generated road depot omitted the stock bus")
    command("road_buy",{engine=bus.engine,cargo=bus.cargo,depot=road_depot,cost=bus.cost})
    q=ask("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="wagon",stock=27})
    q=ask("rail_assembly",{depot=depot})
    local train
    for id,unit in pairs(q.units) do if #unit.stocks==2 and unit.stocks[1]==0 and unit.stocks[2]==27 then train=id end end
    local s=state()
    local a,b=s.tiles[west].rail_station_id,s.tiles[east].rail_station_id
    assert(s.stock_rail_stations[a].stock_station_id~=s.stock_rail_stations[b].stock_station_id)
    local order=first_free_three(s)
    assert(s.stock_rail_fleet.units[train].parts[1].stock_pool_id==order[1] and
      s.stock_rail_fleet.units[train].parts[2].stock_pool_id==order[3] and s.fleet[1].stock_pool_id==order[2])
    command("transport_start",{mode="rail",vehicle=assert(train),first=a,second=b})
    for _=1,35 do ask("advance",{days=4}) end
    local shown=false
    for _=1,60 do
      ask("advance",{days=1})
      local live,run=state()
      assert(run.stock_live_procurement and run.stock_fault and not run.failure,tostring(run.failure))
      shown=shown or actor_present()
      if run.service_depot then
        assert(shown and run.service_depot==depot and not run.pending_depot_entry_tick)
        local charged=live.companies[owner]
        assert(charged.paid_units>0)
        proof=("ORDINARY_TRAIN_SAVED inbound depot route after %d paid passengers"):format(charged.paid_units)
        return {kind="stop"}
      end
    end
    error("New train never selected its automatic service depot")
  end
  local old=assert(initial.stock_rail_dispatch.runs[1])
  assert(old.service_depot==depot and not old.pending_depot_entry_tick)
  for _=1,12 do
    ask("advance",{days=1})
    local s,run=state()
    assert(not run.failure,tostring(run.failure))
    if run.pending_depot_entry_tick and run.phase~="depot" then
      assert(run.stock_fault.date_of_last_service>old.stock_fault.date_of_last_service)
      assert(run.stock_random_parts[1].stock_waiting_random_triggers%4>=2 and
        run.stock_random_parts[2].stock_waiting_random_triggers%4>=2)
      local order=first_free_three(s)
      assert(not run.service_depot and run.order.kind=="station" and run.stock_pool_id==order[1])
      assert(s.stock_rail_fleet.units[run.fleet_id].parts[2].stock_pool_id==order[3])
      proof=("ORDINARY_TRAIN_PASS serviced and resumed original station order after real restart, %d paid passengers")
        :format(s.companies[owner].paid_units)
      return {kind="stop"}
    end
  end
  error("New train did not resume service from the real world checkpoint")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(r)
    assert(r.ready);revision=r.revision;resume(r)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,tostring(detail or reason))
    core.log("action",proof);core.request_shutdown("Ordinary Train QA complete",false,0)
  end,name))
end)
