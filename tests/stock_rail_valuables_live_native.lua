-- Real Luanti worker and SQLite restart, eligible seeded houses only.
-- Companies, Banks, construction, depot, orders and cargo use production.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local mode=core.settings:get("luanttd_qa_rail_valuables_phase")
local name="RC1 Valuables Rail"
local function cell(x,z) return (z-1)*64+x end
local depot,west,same,east,far=cell(6,15),cell(9,15),cell(13,15),cell(42,15),cell(28,15)
local bank_tiles={cell(10,12),cell(42,12)}
local cap={temperate_bank=true,road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready.armoured_van)
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local balance=3000000
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles={};for id=1,64^2 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.corner_grid=T.new(64,64,function()return 1 end)
  s.stock_generated_profile={width=64,depth=64}
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.road_mail,s.road_junction_clearance=true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  s.sites={{id=1,kind="town",name="Banktown",tile=cell(8,12),population=1500,stock={},received={},produced={},service=0},
    {id=2,kind="town",name="Stationfield",tile=cell(45,12),population=1500,stock={},received={},produced={},service=0}}
  s.stock_town_growth={version=1,order={},towns={}}
  for _,p in ipairs(s.sites) do
    local q=m("openttd/town_growth").new(p.id,Sim.xy(p.tile))
    q.population,q.num_houses,q.house_counts=1500,2,{[0x06]=2}
    s.stock_town_growth.towns[p.id]=q
  end
  for _,p in ipairs({{10,12,1},{11,12,1},{42,12,2},{43,12,2}}) do
    local t=s.tiles[cell(p[1],p[2])]
    t.house=true
    t.source_house={id=0x06,root=true,completed=true,town_growth=true,town=p[3],x=p[1],z=p[2]}
  end
  Sim.company(s,name).cash=balance
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
local function query(kind,fields,raw)
  fields=fields or {};fields.kind,fields.player=kind,name
  local r=assert(coroutine.yield(fields))
  if r.revision then revision=r.revision end
  if raw then return r end
  assert(r.ok,tostring(r.why))
  return r.value,r
end
local function command(kind,fields,raw)
  fields.kind,fields.revision=kind,revision
  return query("command",{command=fields},raw)
end
local function stage(tile,role,raw)
  return command("rail_freight_stage",{tile=tile,cargo="valuables",role=role},raw)
end
local function lay(req)
  local q=query("rail_quote",{request=req})
  command("rail_commit",{token=q.token})
end
local function banks(s)
  local p={}
  for i,tile in ipairs(bank_tiles) do p[i]=assert(s.stock_bank_industries[s.tiles[tile].stock_industry.id]) end
  return p[1],p[2]
end
local function payload()
  local s=assert(checkpoint.read())
  local a,b=banks(s)
  local v=assert(s.stock_rail_valuables.vehicle)
  local run
  for _,r in ipairs(s.stock_rail_dispatch.runs) do if r.freight and r.freight.cargo=="valuables" then run=r end end
  return s,v,a,b,assert(run)
end
local function visible()
  local rows=query("actor_frames",{windows={{x=4,z=13,w=25,h=5},{x=29,z=13,w=25,h=5}},fraction=1})
  for _,sector in ipairs(rows) do
    for _,r in ipairs(sector.actors) do
      if r.mode=="rail" and r.wagon==37 and r.complete_parts and #r.parts==2 then
        assert(r.part_count==2)
        for _,part in ipairs(r.parts) do if part.body_index==2 then
          assert(part.kind=="armoured_van" and part.rotation.y==part.rotation.y)
          return true
        end end
      end
    end
  end
end
local function work()
  if mode=="start" then
    for _,tile in ipairs(bank_tiles) do
      local req={tool="fund_bank",first=tile}
      local q=query("road_quote",{request=req})
      assert(q.cost==996093)
      command("road_commit",{request=req,quote=q})
    end
    query("checkpoint")
    local state=assert(checkpoint.read())
    local a,b=banks(state)
    assert(a.id~=b.id and a.town~=b.town and state.companies[name].cash==balance-2*996093)
    lay({tool="track",first=cell(7,15),last=cell(51,15),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({9,13,28,42}) do
      lay({tool="station",first=cell(x,15),last=cell(x+2,15),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    assert(not stage(far,"load",true).ok and not stage(far,"unload",true).ok)
    stage(west,"load")
    assert(not stage(west,"unload",true).ok)
    stage(same,"unload")
    stage(east,"unload")
    local q=query("rail_assembly",{depot=depot})
    assert(type(q)=="table")
    local found
    for _,u in ipairs(q.wagons) do if u.id==37 then
      assert(u.quote.price==1992 and u.name=="Armoured Van");found=u
    end end
    assert(found,"Stock no.37 absent in real assembly")
    command("rail_assembly",{token=q.token,operation="engine",stock=0})
    q=query("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="wagon",stock=37})
    q=query("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(q.units) do if u.stocks[1]==0 and u.stocks[2]==37 then train=k end end
    assert(train,"Purchased Armoured Van not coupled")
    local panel=query("depot",{mode="rail",depot=depot})
    local source,other,dest,match
    for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo=="valuables" then match=true end end
    for _,row in ipairs(panel.targets) do
      if row.cargo=="valuables" then
        if row.role=="load" then source=row.id
        elseif not other then other=row.id
        else dest=row.id end
      end
    end
    assert(match and source and other and dest)
    local failed=command("transport_start",{mode="rail",vehicle=train,first=source,second=other,cargo="valuables"},true)
    assert(not failed.ok and failed.why:find("different banks",1,true),tostring(failed.why))
    command("transport_start",{mode="rail",vehicle=train,first=source,second=dest,cargo="valuables"})
    local orders=query("orders",{mode="rail",vehicle=train,page=1})
    assert(orders.items[1].id==source and orders.items[2].id==dest)
    local empty
    for day=1,260 do
      query("advance",{days=1})
      empty=empty or visible()
      if empty then
        query("checkpoint")
        local s,v,a,b=payload()
        if v.units>0 and v.units<20 then
          assert(v.delivered==0 and v.batches[1].source==a.id and (not b.received or not b.received.valuables))
          assert(s.stock_load_tick==s.passenger_house_clock.counter)
          goal=("RAIL_VALUABLES_NATIVE_SAVED %d bags from Bank %d"):format(v.units,a.id)
          return {kind="stop"}
        end
      end
    end
    error("Stock Bank did not load wagon #37")
  end
  local s,v,a,b,r=payload()
  assert(v.units>0 and v.units<20 and v.batches[1].source==a.id and v.delivered==0)
  assert(visible(),"Reopened stock closed Armoured Van did not project")
  local carry=v.units
  for _=1,260 do
    query("advance",{days=1})
    query("checkpoint")
    s,v,a,b,r=payload()
    if v.delivered>=20 then
      local c=s.companies[name]
      assert(v.delivered==20 and v.revenue>0 and v.boarded==20 and v.units==0)
      assert((not a.received or not a.received.valuables) and b.received.valuables==20)
      assert(c.paid_units==20 and c.revenue==v.revenue and c.cash==balance-c.expense+c.revenue)
      assert(r.freight.running_expense>0 and s.stock_load_tick==s.passenger_house_clock.counter)
      goal=("RAIL_VALUABLES_NATIVE_PASS %d/%d restored bags, %d bags delivered Bank %d→%d for $%d, exact ledger")
        :format(carry,20,v.delivered,a.id,b.id,v.revenue)
      return {kind="stop"}
    end
  end
  error(("No restored Bank payment %s / %s / %s"):format(r.phase,v.units,v.delivered))
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary Bank freight checked",false,0)
  end,file))
end)
