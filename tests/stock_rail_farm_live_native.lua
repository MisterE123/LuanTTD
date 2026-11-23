-- Unmodified authority workload and a two-process SQLite reopen. Only
-- authored stock geography is seeded; no supply, routes or receipts are.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local mode=core.settings:get("luanttd_qa_rail_farm_phase")
local name="RC1 Farm Rail"
local function cell(x,z) return (z-1)*64+x end
local routes={
  {cargo="livestock",depot=cell(6,15),z=15,id=31,price=1500,capacity=25,stem="livestock_van"},
  {cargo="grain",depot=cell(6,23),z=23,id=33,price=1421,capacity=30,stem="grain_hopper"},
}
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
for _,stem in ipairs({"livestock_van","grain_hopper_empty","grain_hopper_loaded"}) do assert(cap.rail.ready[stem],stem) end
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local initial_cash=300000
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function() return 1 end)
  for id=1,4096 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.stock_generated_profile={width=64,depth=64}
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_farm,s.road_junction_clearance=true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  s.stock_farm_frozen=true
  local Farm,_,Rules=Sim.mount_farm_world(s,T,true)
  local function plant(kind,x,z)
    local rec=Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950})
    return assert(Farm.place_generated(s,kind,cell(x,z),{record=rec,name=kind},function()return 0 end))
  end
  local a,b=plant("farm",10,18),plant("factory",44,18)
  Sim.company(s,name).cash=initial_cash
  s.rail_farm_native_qa={farm=a.id,factory=b.id}
  checkpoint.write_state(s)
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
  fields=fields or {};fields.kind,fields.player=kind,name
  local r=assert(coroutine.yield(fields))
  if r.revision then revision=r.revision end
  if raw then return r end
  assert(r.ok,tostring(r.why))
  return r.value,r
end
local function command(kind,fields,raw)
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields},raw)
end
local function lay(req)
  local q=ask("rail_quote",{request=req})
  command("rail_commit",{token=q.token})
end
local function designate(cargo,tile,role,raw)
  return command("rail_freight_stage",{tile=tile,cargo=cargo,role=role},raw)
end
local function serving(p)
  local z=p.z
  lay({tool="track",first=cell(7,z),last=cell(53,z),track=Track.X})
  lay({tool="depot",first=p.depot,direction=Track.SW})
  for _,x in ipairs({10,44}) do
    lay({tool="station",first=cell(x,z),last=cell(x+2,z),axis=0,length=3,tracks=1,separate=true,drag=true})
  end
  assert(not designate(p.cargo,cell(10,z),"unload",true).ok)
  assert(not designate(p.cargo,cell(44,z),"load",true).ok)
  designate(p.cargo,cell(10,z),"load")
  designate(p.cargo,cell(44,z),"unload")
  assert(not designate(p.cargo=="grain" and "livestock" or "grain",cell(10,z),"load",true).ok)
  local q=ask("rail_assembly",{depot=p.depot})
  local found
  for _,u in ipairs(q.wagons) do if u.id==p.id then
    assert(u.quote.price==p.price);found=true
  end end
  assert(found,"No wagon "..p.id.." in the depot's stock selection")
  command("rail_assembly",{token=q.token,operation="engine",stock=0})
  q=ask("rail_assembly",{depot=p.depot})
  command("rail_assembly",{token=q.token,operation="wagon",stock=p.id})
  q=ask("rail_assembly",{depot=p.depot})
  local train
  for k,u in pairs(q.units) do if u.stocks[1]==0 and u.stocks[2]==p.id then train=k end end
  assert(train,"No ordered locomotive and authentic farm wagon")
  local panel=ask("depot",{mode="rail",depot=p.depot})
  local source,destination,match
  for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo==p.cargo then match=true end end
  for _,r in ipairs(panel.targets) do if r.cargo==p.cargo then
    if r.role=="load" then source=r.id else destination=r.id end
  end end
  assert(match and source and destination and source~=destination)
  command("transport_start",{mode="rail",vehicle=train,first=source,second=destination,cargo=p.cargo})
  local orders=ask("orders",{mode="rail",vehicle=train,page=1})
  assert(orders.items[1].id==source and orders.items[2].id==destination)
end
local function payload()
  local s=assert(checkpoint.read())
  local a=assert(s.stock_rail_livestock.vehicle);local b=assert(s.stock_rail_grain.vehicle)
  local f=assert(s.stock_farm_industries[s.rail_farm_native_qa.farm])
  local t=assert(s.stock_farm_industries[s.rail_farm_native_qa.factory])
  return s,a,b,f,t
end
local function visible()
  local rows=ask("actor_frames",{windows={{x=4,z=13,w=25,h=5},{x=29,z=13,w=25,h=5},
    {x=4,z=21,w=25,h=5},{x=29,z=21,w=25,h=5}},fraction=1})
  local kinds={}
  for _,sector in ipairs(rows) do for _,row in ipairs(sector.actors) do
    if row.mode=="rail" and (row.wagon==31 or row.wagon==33) and row.complete_parts and #row.parts==2 then
      assert(row.part_count==2)
      for _,part in ipairs(row.parts) do
        if part.body_index==2 then
          assert(part.rotation.y==part.rotation.y)
          kinds[row.wagon]=part.kind
        end
      end
    end
  end end
  return kinds
end
local function work()
  if mode=="start" then
    for _,p in ipairs(routes) do serving(p) end
    local seen_livestock,empty_grain
    for _=1,190 do
      ask("advance",{days=1})
      local art=visible()
      seen_livestock=seen_livestock or art[31]=="livestock_van"
      empty_grain=empty_grain or art[33]=="grain_hopper_empty"
      if seen_livestock and empty_grain and art[33]=="grain_hopper_loaded" then
        ask("checkpoint")
        local s,a,b,f=payload()
        if a.units>0 and a.units<=25 and b.units>=15 and b.units<30 and a.delivered==0 and b.delivered==0 then
          assert(a.batches[1].source==f.id and b.batches[1].source==f.id)
          assert(s.stock_load_tick==s.passenger_house_clock.counter)
          assert(not s.rail_iron_ore_service and not s.rail_valuables_service,"Use Farm-only industry configuration")
          goal=("RAIL_FARM_NATIVE_SAVED %d livestock + %d t grain from Farm %d"):format(a.units,b.units,f.id)
          return {kind="stop"}
        end
      end
    end
    local s,a,b=payload()
    error(("Unverified loading at day %d: %d livestock/%d delivered; %d grain/%d delivered"):format(s.day,a.units,a.delivered,b.units,b.delivered))
  end
  local s,a,b,f,t=payload()
  assert(a.units>0 and b.units>=15 and b.units<30 and a.batches[1].source==f.id and b.batches[1].source==f.id)
  local art=visible()
  assert(art[31]=="livestock_van" and art[33]=="grain_hopper_loaded","Reopened wagons lost their stock art")
  local after_grain,after_livestock
  for _=1,220 do
    ask("advance",{days=1})
    art=visible()
    after_livestock=after_livestock or art[31]=="livestock_van"
    after_grain=after_grain or art[33]=="grain_hopper_empty"
    ask("checkpoint")
    s,a,b,f,t=payload()
    if a.delivered>=25 and b.delivered>=30 and after_grain and after_livestock then
      local c=s.companies[name]
      assert(a.delivered%25==0 and b.delivered%30==0)
      assert(t.received.livestock==a.delivered and t.received.grain==b.delivered and not f.received)
      assert(t.produced[1].cargo=="goods" and t.produced[1].waiting>0)
      assert(a.revenue>0 and b.revenue>0 and c.paid_units==a.delivered+b.delivered and c.revenue==a.revenue+b.revenue)
      assert(c.cash==initial_cash-c.expense+c.revenue and s.stock_load_tick==s.passenger_house_clock.counter)
      for _,run in ipairs(s.stock_rail_dispatch.runs) do assert(run.freight and run.freight.running_expense>0) end
      goal=("RAIL_FARM_NATIVE_PASS Factory %d received exactly %d livestock / $%d and %d t grain / $%d; real Goods and exact ledger")
        :format(t.id,a.delivered,a.revenue,b.delivered,b.revenue)
      return {kind="stop"}
    end
  end
  error("Rail Livestock and Grain service failed to finish after reopening")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary Farm freight checked",false,0)
  end,file))
end)
