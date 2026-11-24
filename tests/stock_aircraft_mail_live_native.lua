-- Real Luanti authority worker and process/SQLite restart. Only the
-- authored town geography is seeded; no generated Mail or vehicles are.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Roster=m("openttd/airport_roster")
local client=m("campaign_authority_client")(core,mod)
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local initial=Checkpoint.read()
local f=assert(io.open(core.get_worldpath().."/qa-airmail-phase.txt","r"))
local mode=f:read("*l");f:close()
local name="RC1 Aircraft Mail"
local road_owner="Road Mail Rival"
local function cell(x,z) return (z-1)*64+x end
local first_tile,second_tile=cell(10,17),cell(43,17)
local stock=tonumber(core.settings:get("luanttd_qa_paid_airframe")) or 216
local expected_mesh={
  [216]="bl_coleman_count.obj",[218]="bl_stock_yate_haugan.obj",
  [232]="bl_stock_guru_galaxy.obj",[233]="bl_stock_airtaxi_a21.obj",
}
assert(expected_mesh[stock])
local city=stock~=216
local layout=city and "city" or "country"
local airport_tiles=city and 36 or 12
local spec=assert(Roster.entry(stock))
local road_depot,road_one,road_two=cell(17,7),cell(10,11),cell(43,11)
local cap={road={start_year=city and 1975 or 1950,foster=true,breakdowns=0,service_interval=0,extra={mail_mps=true}},
  ferry={},air={},city_airport=city,oil_tanker=true,durable_actions=true}
local art=m("airport_manifest")(core,mod)
assert(art[stock] and art[stock].mesh==expected_mesh[stock])
for id in pairs(art) do cap.air[id]=true end
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
  s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
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
  assert(mode=="reload" or mode=="final" or mode=="confirm")
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
local function transport(req)
  local q=ask("transport_quote",{request=req})
  if req.operation=="build" then assert(#q.tiles==airport_tiles and q.cost==airport_tiles*600) end
  return command("transport_commit",{token=q.token})
end
local function payload(from,to)
  local s=assert(Checkpoint.read())
  local c=assert(s.stock_ship_commercial and s.stock_ship_commercial.service)
  local _,run=next(s.airport_owned_runs)
  local v=assert(c.vehicles[0xC000+run.paid_clock])
  from=from or run.first;to=to or run.second
  local a,b=assert(c.stations[0xC000+from]),assert(c.stations[0xC000+to])
  local p,m=v.carrying_parts[1],v.carrying_parts[2]
  assert(v.air_mail and v.cargo=="mixed" and p.capacity==spec.passengers and m.capacity==spec.mail and p.slice==20 and m.slice==5)
  assert(p.units<=p.capacity and m.units<=m.capacity and v.units==p.units+m.units)
  assert(#a.tiles==airport_tiles and #b.tiles==airport_tiles and a.mail_enabled and b.mail_enabled and a.mail_acceptance>=8 and b.mail_acceptance>=8)
  assert(run.engine_id==stock and run.phase~="blocked",run.failure)
  return s,c,run,v,a,b,p,m
end
local function visual(run,phase)
  local frame=ask("actor_frames",{windows={{x=6,z=14,w=10,h=12},{x=40,z=14,w=10,h=12}},fraction=1})
  local found=0
  for _,section in ipairs(frame) do
    for _,actor in ipairs(section.actors) do
      if actor.mode=="air" then
        assert(actor.engine==stock and actor.owner==name and actor.pos and actor.pos.x==actor.pos.x)
        found=found+1
        if phase then assert(core.safe_file_write(core.get_worldpath().."/airmail-"..phase..".json",core.write_json(actor))) end
      end
    end
  end
  assert(found<=1,"The Mail hold must not produce a second plane")
  return found==1
end
local function work()
  if mode=="start" then
    build_road()
    local first=transport({mode="air",operation="build",layout=layout,tile=first_tile}).id
    local second=transport({mode="air",operation="build",layout=layout,tile=second_tile}).id
    local panel=ask("depot",{mode="air",depot=first})
    local offer
    for _,r in ipairs(panel.offers) do if r.request.engine==stock then offer=r end end
    assert(offer and offer.help.model:find(spec.passengers.." seats",1,true) and offer.help.model:find(spec.mail.." Mail bags",1,true))
    local unit=transport(offer.request)
    command("transport_start",{mode="air",first=first,second=second})
    local function orders() return ask("orders",{mode="air",vehicle=unit.id,page=1}) end
    local o=orders()
    assert(o.items[1].id==first and o.items[2].id==second and o.cargo_rules.load)
    command("vehicle_order",{mode="air",vehicle=unit.id,order_revision=o.revision,operation="load",row=1,destination=2})
    o=orders()
    command("vehicle_order",{mode="air",vehicle=unit.id,order_revision=o.revision,operation="load",row=2,destination=4})
    local s,c,run,v,a,b,p,m
    for _=1,250 do
      ask("advance",{days=1})
      ask("checkpoint")
      s,c,run,v,a,b,p,m=payload(first,second)
      if p.units>0 and m.units>0 and not v.delivered and visual(run,"onboard") then
        local road=s.stations[s.tiles[road_one].station]
        assert(road.mail_rating_state and road.mail_rating_state.last_speed>0)
        assert(a.mail_rating_state.last_speed>0 and a.passenger_rating_state.last_speed>0)
        assert(m.batches[1].source_type=="town" and m.batches[1].source==1 and p.batches[1].source==1)
        assert(v.cargo_tile and s.tiles[v.cargo_tile].airfield and s.tiles[v.cargo_tile].airfield.airport==first)
        goal=("AIR_MAIL_NATIVE_SAVED %s #%d with %d passengers and %d Mail bags competing for the same houses"):format(spec.name,stock,p.units,m.units)
        return {kind="stop"}
      end
    end
    error(("Never loaded both cargoes: %s %s paid=%s p/m=%d/%d"):format(run.phase,run.failure,tostring(v.delivered),p.units,m.units))
  end
  local s,c,run,v,a,b,p,m=payload()
  if mode=="reload" then
    assert(p.units>0 and m.units>0 and not v.delivered and visual(run))
    local old=assert(initial.stock_ship_commercial.service.vehicles[v.id])
    assert(old.carrying_parts[1].cargo_age_counter==p.cargo_age_counter and old.carrying_parts[2].cargo_age_counter==m.cargo_age_counter)
    for _=1,250 do
      ask("advance",{days=1})
      ask("checkpoint")
      s,c,run,v,a,b,p,m=payload()
      local pending=v.load_state and v.load_state.payment
      if pending and pending.delivered>0 and (p.units>0 or m.units>0) and visual(run,"pending") then
        local md,pd=pending.by_cargo.mail.delivered,pending.by_cargo.passenger.delivered
        assert(pending.route>0 and md>0 and pd>0)
        if stock<=218 then
          assert(md==5 and pd==20 and pending.route==(city and 337 or 334))
        else
          -- A daily checkpoint may occur after several short unload
          -- slices. Each hold must still advance in its stock increments.
          assert(md%5==0 and pd%20==0 and md<=spec.mail and pd<=spec.passengers,
            ("unload slices %d Mail / %d passengers"):format(md,pd))
        end
        assert(pending.delivered==pending.by_cargo.mail.delivered+pending.by_cargo.passenger.delivered)
        assert(s.companies[name].paid_units==0 and s.companies[name].revenue==0)
        goal=("AIR_MAIL_NATIVE_PENDING exact uncredited $%d after unloading %d passengers + %d Mail bags"):format(
          pending.route,pending.by_cargo.passenger.delivered,pending.by_cargo.mail.delivered)
        return {kind="stop"}
      end
    end
    error(("Missed first pending payment: %s p/m=%d/%d fare=%s"):format(run.phase,p.units,m.units,tostring(v.route_profit)))
  end
  if mode=="confirm" then
    local fare=assert(v.last_fare)
    local paid,revenue=v.delivered,v.route_profit
    ask("advance",{days=1});ask("checkpoint")
    s,c,run,v=payload()
    assert(v.last_fare.tick==fare.tick and v.delivered==paid and v.route_profit==revenue and s.companies[name].revenue==revenue)
    goal=("AIR_MAIL_NATIVE_CONFIRMED restart did not re-credit $%d or %d units"):format(revenue,paid)
    return {kind="stop"}
  end
  local pending=assert(v.load_state.payment)
  local old=assert(initial.stock_ship_commercial.service.vehicles[v.id]).load_state.payment
  assert(pending.route==old.route and pending.delivered==old.delivered and s.companies[name].revenue==0)
  for _=1,140 do
    ask("advance",{days=1});ask("checkpoint")
    s,c,run,v,a,b,p,m=payload()
    if (v.delivered or 0)>0 and (city or s.companies[road_owner].paid_units>0) then
      local f=assert(v.last_fare)
      local commercial=s.companies[name]
      local pb,mb=assert(f.by_cargo.passenger),assert(f.by_cargo.mail)
      assert(f.cargo=="mixed" and pb.delivered==spec.passengers and mb.delivered==spec.mail and f.units==spec.passengers+spec.mail and f.amount==pb.route+mb.route)
      assert(pb.route>0 and mb.route>0)
      if stock<=218 then
        assert(pb.route==(city and 1242 or 790) and mb.route==(city and 363 or 145) and f.amount==(city and 1605 or 935))
      end
      assert(f.amount==v.route_profit and commercial.revenue==f.amount and commercial.paid_units==spec.passengers+spec.mail,
        ("fare=%d total=%d revenue=%d paid=%d last unit=%d last station=%d, tick=%d"):format(
          f.amount,v.route_profit,commercial.revenue,commercial.paid_units,f.units,f.station or -1,f.tick))
      assert(commercial.cash==balance-commercial.expense+commercial.revenue and run.finance.expense>0)
      assert(c.mail_towns[2]==spec.mail and c.towns[2]==spec.passengers and s.sites[2].received.passenger==spec.passengers)
      assert((s.sites[1].received.mail or 0)+s.sites[2].received.mail==spec.mail+s.companies[road_owner].paid_units)
      assert(s.stock_load_tick==s.passenger_house_clock.counter)
      goal=("AIR_MAIL_NATIVE_PASS paid once $%d: %d passengers/$%d + %d Mail bags/$%d, one real airframe and shared road Mail provisioning")
        :format(f.amount,spec.passengers,pb.route,spec.mail,mb.route)
      return {kind="stop"}
    end
  end
  error("No combined aircraft payout")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary aircraft Mail verified",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
