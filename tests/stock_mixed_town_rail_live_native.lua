-- Real Luanti authority worker and process/SQLite restart. Only the
-- authored town geography is seeded; no generated Mail or vehicles are.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track,Roster=m("openttd/rail_track"),m("openttd/rail_roster")
local client=m("campaign_authority_client")(core,mod)
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local initial=Checkpoint.read()
local fixture=assert(io.open(core.get_worldpath().."/qa-mixed-form.txt","r"))
local mode,form=fixture:read("*l","*l")
fixture:close()
assert(mode=="start" or mode=="reload" or mode=="final")
local profiles=m("rail_guideway_profiles").by_gauge
local gauge=form:match("^maglev") and 3 or form:match("^monorail") and 2 or nil
local profile=profiles[gauge]
assert(form=="coach-mail" or form=="mail-coach-mail" or
  profile and (form==profile.title:lower() or form==profile.title:lower().."-spans"))
local spans=form:match("%-spans$")~=nil
local stock=profile and profile.stocks or form=="coach-mail" and {0,27,28} or {0,28,27,28}
local function is_coach(i) return i==27 or profile and i==profile.passenger end
local name="RC1 Mixed Town Rail"
local function cell(x,z) return (z-1)*64+x end
local depot,first,second=cell(6,17),cell(10,17),cell(43,17)
local cap={road={start_year=gauge==3 and 2025 or profile and 2010 or 1950,foster=true,breakdowns=0,service_interval=0,extra={mail_mps=true}},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(not profile or cap.rail.advanced[profile.engine])
assert(not spans or cap.rail.guideway_spans[gauge])
assert(cap.rail.ready.mail_van and cap.rail.mixed_town_engines[0], "Ordinary scanned stock art must enable mixed town rail")
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local balance=300000
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles={}
  for id=1,64*64 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.corner_grid=T.new(64,64,function(x)
    if not spans then return 1 end
    if x>=27 and x<=31 then return 5 end
    if x==18 or x==19 then return 3 end
    return 4
  end)
  for id,tile in ipairs(s.tiles) do local _,h=T.tile(s.corner_grid,Sim.xy(id));tile.h=h end
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
  Checkpoint.write_state(s)
else
  assert(mode=="reload" or mode=="final")
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
local function lay(req)
  local q=ask("rail_quote",{request=req})
  command("rail_commit",{token=q.token})
end
local function payload()
  local s=assert(Checkpoint.read())
  local c=assert(s.stock_ship_commercial and s.stock_ship_commercial.service)
  local run
  for _,r in ipairs(s.stock_rail_dispatch.runs) do if r.town_parts then run=r end end
  run=assert(run)
  local v=assert(c.vehicles[0x4000+run.paid_clock])
  local a,b=c.stations[0x4000+assert(s.tiles[first].rail_station_id)],c.stations[0x4000+assert(s.tiles[second].rail_station_id)]
  assert(a and b)
  return s,c,run,v,a,b
end
local function visual(run,capture)
  local rows=ask("actor_frames",{windows={{x=4,z=15,w=25,h=5},{x=29,z=15,w=26,h=5}},fraction=1})
  for _,sector in ipairs(rows) do for _,row in ipairs(sector.actors) do
    if row.mode=="rail" and row.complete_parts and #row.parts==#stock then
      local seen={}
      for _,part in ipairs(row.parts) do
        local i=part.body_index
        assert(not seen[i] and stock[i]==part.stock_id and part.rotation.y==part.rotation.y)
        seen[i]=true
        if profile and (not spans or part.bogies) then
          local gears=assert(part.bogies);assert(#gears==2)
          for _,g in ipairs(gears) do
            assert(math.abs(g.pos.y-part.pos.y)<.001 and math.abs(g.rotation.y-part.rotation.y)<.001)
          end
          local dist=math.abs(gears[1].pos.x-gears[2].pos.x)+math.abs(gears[1].pos.z-gears[2].pos.z)
          assert(math.abs(dist-.505)<.001)
        else assert(not part.bogies) end
        if i==1 then assert(part.kind==(profile and profile.engine_visual or "steam") and part.body_id==run.town_engine_body_id)
        else
          assert(part.kind==(is_coach(stock[i]) and (profile and profile.passenger_visual or "wagon") or profile and profile.mail_visual or "mail_van"))
          assert(part.body_id==run.town_parts[i-1].body_id)
        end
      end
      if capture then
        assert(core.safe_file_write(core.get_worldpath().."/mixed-pose-"..capture..".json",
          core.write_json({form=form,reversals=run.shuttle.reversals,parts=row.parts})))
      end
      return true
    end
  end end
end
local function totals(v)
  local passenger,mail=0,0
  local ids={}
  for i,a in ipairs(v.carrying_parts) do
    assert(a.stock==stock[i+1] and a.part==i+1 and not ids[a.body_id])
    assert(a.units<=a.capacity and a.cargo_age_counter>=1 and a.cargo_age_counter<=185)
    assert(a.capacity==assert(Roster.entry(a.stock)).capacity)
    ids[a.body_id]=true
    if is_coach(a.stock) then passenger=passenger+a.units else mail=mail+a.units end
  end
  return passenger,mail
end
local function work()
  local pax_cap=profile and assert(Roster.entry(profile.passenger)).capacity or 40
  local mail_cap=profile and assert(Roster.entry(profile.mail)).capacity or (#stock-2)*30
  if mode=="start" then
    if spans then
      local function track(a,b)
        lay({tool="track",first=cell(a,17),last=cell(b,17),track=Track.X,railtype=gauge})
      end
      local bridge=ask("bridge_picker",{mode="rail",first=cell(16,17),last=cell(20,17),railtype=gauge})
      assert(bridge.railtype==gauge and #bridge.offers==1)
      command("bridge_picker",{token=bridge.token,style=bridge.offers[1].style})
      local tunnel=ask("transport_quote",{request={mode="rail",operation="tunnel",tile=cell(26,17),railtype=gauge}})
      command("transport_commit",{token=tunnel.token})
      local world=assert(Checkpoint.read())
      local bridge_rec=assert(world.stock_rail_spans[world.tiles[cell(16,17)].rail_span_id])
      local tunnel_rec=assert(world.stock_rail_spans[world.tiles[cell(26,17)].rail_span_id])
      assert(bridge_rec.railtype==gauge and bridge_rec.kind=="bridge" and tunnel_rec.railtype==gauge and tunnel_rec.kind=="tunnel")
      track(7,15);track(21,25);track(Sim.xy(tunnel_rec["end"])+1,53)
    else
      lay({tool="track",first=cell(7,17),last=cell(53,17),track=Track.X,railtype=gauge})
    end
    lay({tool="depot",first=depot,direction=Track.SW,railtype=gauge})
    for _,x in ipairs({10,43}) do
      lay({tool="station",first=cell(x,17),last=cell(x+2,17),axis=0,length=3,tracks=1,separate=true,drag=true,railtype=gauge})
    end
    local q=ask("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="engine",stock=stock[1]})
    for i=2,#stock do
      q=ask("rail_assembly",{depot=depot})
      local offer
      for _,w in ipairs(q.wagons) do if w.id==stock[i] then offer=w end end
      assert(offer and offer.quote.price==(is_coach(stock[i]) and 1929 or 1781))
      command("rail_assembly",{token=q.token,operation="wagon",stock=stock[i]})
    end
    q=ask("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(q.units) do
      local same=#u.stocks==#stock
      for i,id in ipairs(stock) do same=same and u.stocks[i]==id end
      if same then train=k end
    end
    assert(train,"The actual yard ignored purchase order")
    local panel=ask("depot",{mode="rail",depot=depot})
    local source,sink,selected,offer
    for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo=="mixed" then selected=true end end
    for _,o in ipairs(panel.offers) do if o.request.parts and #o.request.parts==3 then offer=o end end
    for _,st in ipairs(panel.targets) do if not st.cargo then
      if not source then source=st.id else sink=st.id end
    end end
    assert(selected and source and sink and source~=sink and (profile or offer))
    command("transport_start",{mode="rail",vehicle=train,first=source,second=sink,cargo="mixed"})
    local function orders() return ask("orders",{mode="rail",vehicle=train,page=1}) end
    local order=orders()
    assert(order.items[1].id==source and order.items[2].id==sink)
    command("vehicle_order",{mode="rail",vehicle=train,order_revision=order.revision,operation="load",row=1,destination=2})
    order=orders()
    command("vehicle_order",{mode="rail",vehicle=train,order_revision=order.revision,operation="load",row=2,destination=4})
    local seen
    for _=1,230 do
      ask("advance",{days=1})
      ask("checkpoint")
      local s,c,run,v,a,b=payload()
      seen=seen or visual(run)
      local p,m=totals(v)
      if seen and p>0 and m>0 and p+m<pax_cap+mail_cap and not v.delivered then
        assert(run.mail_onboard==m and run.passengers_onboard==p and v.load_state.full)
        local consist={stock[1]}
        for _,part in ipairs(v.carrying_parts) do
          consist[#consist+1]={stock_id=part.stock,cargo_count=part.units}
        end
        local stats=assert(Roster.stats(consist))
        assert(run.consist_mass==stats.weight and run.acceleration==stats.acceleration)
        assert(v.load_state and v.load_state.station==a.id and v.load_state.full)
        assert(a.loading_order[1]==v.id and a.loading_order[2]==nil)
        assert(s.stock_load_tick==s.passenger_house_clock.counter)
        assert(visual(run,"loading"))
        goal=("RAIL_MIXED_NATIVE_SAVED %s %d people + %d bags"):format(form,p,m)
        return {kind="stop"}
      end
    end
    error("No nonempty physically identified mixed consist")
  end
  local s,c,run,v,a,b=payload()
  local old=initial.stock_ship_commercial.service.vehicles[v.id]
  local p,m=totals(v)
  assert(not v.delivered and visual(run))
  for i,part in ipairs(v.carrying_parts) do
    assert(part.body_id==old.carrying_parts[i].body_id and part.cargo_age_counter==old.carrying_parts[i].cargo_age_counter)
  end
  if mode=="reload" then
    assert(p>0 and m>0)
    for _=1,200 do
      ask("advance",{days=1})
      ask("checkpoint")
      s,c,run,v,a,b=payload()
      local l=v.load_state
      local pay=l and l.station==b.id and l.payment
      if pay and pay.delivered>0 and pay.delivered<pax_cap+mail_cap then
        local pr=pay.by_cargo.passenger
        local ma=pay.by_cargo.mail
        assert(pr.delivered>0 and ma.delivered>0 and pr.delivered+ma.delivered==pay.delivered)
        assert(c.towns[2]==pr.delivered and c.mail_towns[2]==ma.delivered)
        assert(not v.delivered and s.companies[name].revenue==0 and s.companies[name].paid_units==0)
        assert(b.loading_order[1]==v.id and b.loading_order[2]==nil and visual(run,"unloading"))
        goal=("RAIL_MIXED_NATIVE_SAVED_PAYMENT %s staged %d people + %d bags, $%d pending (not credited)")
          :format(form,pr.delivered,ma.delivered,pay.route)
        return {kind="stop"}
      end
    end
    error("Did not catch one in-flight CargoPayment at the receiving station")
  end
  local pending=assert(v.load_state.payment)
  assert(pending.route>0 and pending.delivered>0)
  local old_pending=assert(old.load_state.payment)
  assert(pending.route==old_pending.route and pending.delivered==old_pending.delivered)
  assert(s.companies[name].paid_units==0 and s.companies[name].revenue==0)
  for _=1,220 do
    ask("advance",{days=1})
    ask("checkpoint")
    s,c,run,v,a,b=payload()
    if (v.delivered or 0)>0 and (run.shuttle.reversals or 0)>0 and visual(run,"reversed") then
      local fare=assert(v.last_fare)
      local p_,m_=assert(fare.by_cargo.passenger),assert(fare.by_cargo.mail)
      local company=s.companies[name]
      assert(fare.cargo=="mixed" and fare.units==pax_cap+mail_cap and fare.units==v.delivered)
      assert(p_.delivered==pax_cap and m_.delivered==mail_cap)
      assert(p_.route>0 and m_.route>0 and fare.amount==p_.route+m_.route and fare.amount==v.route_profit)
      assert(company.paid_units==v.delivered and company.revenue==fare.amount and company.cash==balance-company.expense+company.revenue)
      assert(run.passenger_finance.expense>0 and c.mail_towns[2]==mail_cap and c.towns[2]==pax_cap)
      assert(s.sites[2].received.mail==mail_cap and s.sites[2].received.passenger==pax_cap and s.sites[2].service<=pax_cap)
      assert(s.stock_load_tick==s.passenger_house_clock.counter)
      goal=("RAIL_MIXED_NATIVE_PASS %s paid once $%d, %d riders/$%d + %d bags/$%d, all yard body IDs stable after reversing")
        :format(form,fare.amount,p_.delivered,p_.route,m_.delivered,m_.route)
      return {kind="stop"}
    end
  end
  error(("No paid mixed proof after reopen: %s, %s, %s aboard, %s paid, %s reversals")
    :format(tostring(run.phase),tostring(run.failure),v.units,tostring(v.delivered),run.shuttle.reversals))
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Native mixed Rail Mail verified",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
