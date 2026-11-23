-- Real Luanti authority worker and process/SQLite restart. Only the
-- authored town geography is seeded; no generated Mail or vehicles are.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local initial=Checkpoint.read()
local mode=core.settings:get("luanttd_qa_rail_mail_phase")
local name="RC1 Rail Mail"
local road_owner="Road Mail Rival"
local function cell(x,z) return (z-1)*64+x end
local depot,first,second=cell(6,17),cell(10,17),cell(43,17)
local road_depot,road_one,road_two=cell(17,7),cell(10,11),cell(43,11)
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0,extra={mail_mps=true}},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready.mail_van)
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local balance=300000
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles={}
  for id=1,64*64 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.corner_grid=T.new(64,64,function() return 1 end)
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  s.sites={}
  for i,x in ipairs({10,43}) do
    s.sites[i]={id=i,kind="town",name=i==1 and "West Post" or "East Post",tile=cell(x,14),
      population=800,stock={},produced={},received={},service=0}
    for r=13,15 do for dx=-3,4 do
      local tile=s.tiles[cell(x+dx,r)]
      tile.house=true
      tile.source_house={id=dx%2==0 and 4 or 1,town=i,completed=true}
    end end
  end
  Sim.company(s,name).cash=balance
  Sim.company(s,road_owner).cash=balance
  Checkpoint.write_state(s)
else
  assert(mode=="reload")
end
local thread,revision,goal
local function resume(r)
  local ok,req=coroutine.resume(thread,r)
  assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(kind,fields,raw)
  fields=fields or {};fields.kind=kind
  fields.player=fields.player or name
  local r=assert(coroutine.yield(fields))
  if r.revision then revision=r.revision end
  if raw then return r end
  assert(r.ok,tostring(r.why))
  return r.value,r
end
local function command(kind,fields,owner,raw)
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields,player=owner},raw)
end
local function road(req)
  local q=ask("road_quote",{request=req,player=road_owner})
  command("road_commit",{request=req,quote=q},road_owner)
end
local function build_road()
  road({tool="drag",first=cell(7,11),last=cell(47,11),axis=0,start_half=false,end_half=true})
  road({tool="drag",first=cell(7,8),last=cell(47,8),axis=0,start_half=false,end_half=true})
  road({tool="drag",first=cell(7,8),last=cell(7,11),axis=1,start_half=false,end_half=true})
  road({tool="drag",first=cell(47,8),last=cell(47,11),axis=1,start_half=false,end_half=true})
  road({tool="road_depot",first=road_depot})
  road({tool="truck_stop",first=road_one})
  road({tool="truck_stop",first=road_two})
  ask("checkpoint")
  local state=assert(Checkpoint.read())
  local from,to=state.tiles[road_one].station,state.tiles[road_two].station
  local panel=ask("depot",{mode="road",depot=road_depot,player=road_owner})
  local van
  for _,o in ipairs(panel.offers) do
    if o.request.engine=="mail_mps" then
      van=command("road_buy",o.request,road_owner);break
    end
  end
  assert(van,"No mounted stock MPS Mail Truck")
  command("road_order_add",{vehicle=van,station=from},road_owner)
  command("road_order_add",{vehicle=van,station=to},road_owner)
  command("road_toggle",{vehicle=van},road_owner)
end
local function lay(req)
  local q=ask("rail_quote",{request=req})
  command("rail_commit",{token=q.token})
end
local function payload()
  local s=assert(Checkpoint.read())
  local c=assert(s.stock_ship_commercial and s.stock_ship_commercial.service)
  local run
  for _,r in ipairs(s.stock_rail_dispatch.runs) do if r.stock_wagon==28 then run=r end end
  run=assert(run)
  local v=assert(c.vehicles[0x4000+run.paid_clock])
  local a,b=c.stations[0x4000+assert(s.tiles[first].rail_station_id)],c.stations[0x4000+assert(s.tiles[second].rail_station_id)]
  assert(a and b)
  return s,c,run,v,a,b
end
local function visual()
  local rows=ask("actor_frames",{windows={{x=4,z=15,w=25,h=5},{x=29,z=15,w=26,h=5}},fraction=1})
  for _,sector in ipairs(rows) do for _,row in ipairs(sector.actors) do
    if row.mode=="rail" and row.wagon==28 and row.complete_parts and #row.parts==2 then
      for _,part in ipairs(row.parts) do if part.body_index==2 then return part.kind=="mail_van" and part.rotation.y==part.rotation.y end end
    end
  end end
end
local function work()
  if mode=="start" then
    build_road()
    lay({tool="track",first=cell(7,17),last=cell(53,17),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({10,43}) do
      lay({tool="station",first=cell(x,17),last=cell(x+2,17),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    local paused=ask("rail_mail_station",{tile=second})
    assert(paused.cargo[1].name=="Mail bags" and paused.cargo[1].accepts and paused.cargo[1].waiting==0)
    local q=ask("rail_assembly",{depot=depot})
    local offer
    for _,w in ipairs(q.wagons) do if w.id==28 then offer=w end end
    assert(offer and offer.name=="Mail Van" and offer.quote.price==1781)
    command("rail_assembly",{token=q.token,operation="engine",stock=0})
    q=ask("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="wagon",stock=28})
    q=ask("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(q.units) do if u.stocks[1]==0 and u.stocks[2]==28 then train=k end end
    assert(train)
    local panel=ask("depot",{mode="rail",depot=depot})
    local source,sink,selected
    for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo=="mail" then selected=true end end
    for _,st in ipairs(panel.targets) do if not st.cargo then
      if not source then source=st.id else sink=st.id end
    end end
    assert(selected and source and sink and source~=sink)
    command("transport_start",{mode="rail",vehicle=train,first=source,second=sink,cargo="mail"})
    local order=ask("orders",{mode="rail",vehicle=train,page=1})
    assert(order.items[1].id==source and order.items[2].id==sink)
    local visible
    for _=1,240 do
      ask("advance",{days=1})
      visible=visible or visual()
      if visible then
        ask("checkpoint")
        local s,c,run,v,a,b=payload()
        if v.units>0 and v.delivered==nil then
          local road=s.stations[s.tiles[road_one].station]
          assert(v.cargo=="mail" and v.wagon==28 and v.units<=30 and v.batches[1].source_type=="town")
          assert(run.consist_mass==68+math.floor(v.units/4) and run.mail_onboard==v.units)
          assert(a.mail_enabled and a.mail_acceptance>=8 and a.mail_rating_state and a.mail_rating_state.last_speed>0)
          assert(b.mail_enabled and b.mail_acceptance>=8)
          assert(road.mail_rating_state and road.mail_rating_state.last_speed>0)
          assert(next(a.stock.passenger)==nil and next(c.towns)==nil and run.passengers_onboard==nil)
          goal=("RAIL_MAIL_NATIVE_SAVED %d bags in real #28, shared road truck loaded too"):format(v.units)
          return {kind="stop"}
        end
      end
    end
    error("No real Mail Van load")
  end
  local s,c,run,v,a,b=payload()
  assert(v.units>0 and not v.delivered and visual())
  local resumed=v.units
  assert(v.cargo_age_counter==initial.stock_ship_commercial.service.vehicles[v.id].cargo_age_counter)
  for _=1,220 do
    ask("advance",{days=1})
    ask("checkpoint")
    s,c,run,v,a,b=payload()
    if (v.delivered or 0)>0 and s.companies[road_owner].paid_units>0 then
      local fare=assert(v.last_fare)
      local company=s.companies[name]
      assert(fare.cargo=="mail" and fare.units==v.delivered and fare.amount==v.route_profit and fare.amount>0)
      assert(company.paid_units==v.delivered and company.revenue==fare.amount and company.cash==balance-company.expense+company.revenue)
      assert(run.passenger_finance.expense>0 and run.mail_onboard~=nil and run.passengers_onboard==nil)
      assert(c.mail_towns and c.mail_towns[2]==v.delivered and next(c.towns)==nil)
      assert(s.sites[2].received.mail and not s.sites[2].received.passenger and s.sites[2].service==0)
      assert(s.stock_load_tick==s.passenger_house_clock.counter)
      goal=("RAIL_MAIL_NATIVE_PASS restored %d bags, delivered %d in #28 for $%d with same-house road competition")
        :format(resumed,v.delivered,fare.amount)
      return {kind="stop"}
    end
  end
  local _,road_vehicle=next(s.fleet)
  error(("No paired Mail proof: day=%s rail phase=%s failure=%s pay=%s aboard=%s, road stage=%s pay=%s aboard=%s")
    :format(s.day,tostring(run.phase),tostring(run.failure),tostring(v.delivered),v.units,
      tostring(road_vehicle.status),tostring(road_vehicle.delivered),road_vehicle.units))
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary Rail Mail verified",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
