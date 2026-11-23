-- Original timber geography, genuine production and paid rail through
-- the actual authority command/worker/SQLite start and reload paths.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local mode=core.settings:get("luanttd_qa_rail_wood_phase")
local mixed=core.settings:get_bool("luanttd_qa_rail_wood_mixed",false)
local name="RC1 Timber Rail"
local function cell(x,z) return (z-1)*64+x end
local depot,origin,dest=cell(6,18),cell(10,18),cell(44,18)
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready.wood_truck_empty and cap.rail.ready.wood_truck_loaded)
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local balance=300000
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=Terrain.new(64,64,function() return 1 end)
  for id=1,4096 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_timber,s.road_junction_clearance=true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service,s.rail_goods_service=true,true,true,true
  local Rules=Sim.timber_rules()
  local W=m("timber_world")(Sim,Terrain,Rules)
  local function plant(kind,x,z)
    local r=Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950})
    return assert(W.place_generated(s,kind,cell(x,z),{record=r,name=kind}))
  end
  local f,b=plant("forest",10,13),plant("sawmill",44,14)
  if mixed then
    s.stock_generated_profile={width=64,depth=64}
    s.road_farm,s.stock_farm_frozen=true,true
    local Farm,_,Rules=Sim.mount_farm_world(s,Terrain,true)
    for _,z in ipairs({{"farm",11,30},{"factory",44,30}}) do
      local kind,x,row=unpack(z)
      local r=Rules.new(kind,0,x-1,row-1,{completed=true,counter=1,economy_year=1950})
      assert(Farm.place_generated(s,kind,cell(x,row),{record=r,name=kind},function()return 0 end))
    end
  end
  Sim.company(s,name).cash=balance
  s.stock_rail_wood_qa={forest=f.id,sawmill=b.id}
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
local function stage(tile,role,raw)
  return command("rail_freight_stage",{tile=tile,cargo="wood",role=role},raw)
end
local function payload()
  local s=assert(checkpoint.read())
  local a=assert(s.stock_rail_wood.vehicle)
  local q=assert(s.stock_rail_wood_qa)
  local forest=assert(s.stock_timber_industries[q.forest])
  local mill=assert(s.stock_timber_industries[q.sawmill])
  local run
  for _,r in ipairs(s.stock_rail_dispatch.runs) do
    if r.freight and r.freight.cargo=="wood" then run=r end
  end
  return s,a,forest,mill,assert(run)
end
local function visible()
  local rows=ask("actor_frames",{windows={{x=4,z=16,w=25,h=5},{x=29,z=16,w=26,h=5}},fraction=1})
  for _,sector in ipairs(rows) do for _,row in ipairs(sector.actors) do
    if row.mode=="rail" and row.wagon==34 and row.complete_parts and #row.parts==2 then
      assert(row.part_count==2)
      for _,part in ipairs(row.parts) do
        if part.body_index==2 then
          assert(part.rotation.y==part.rotation.y)
          return part.kind
        end
      end
    end
  end end
end
local function work()
  if mode=="start" then
    lay({tool="track",first=cell(7,18),last=cell(54,18),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({10,44}) do
      lay({tool="station",first=cell(x,18),last=cell(x+2,18),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    assert(not stage(origin,"unload",true).ok and not stage(dest,"load",true).ok)
    stage(origin,"load");stage(dest,"unload")
    local overlap=command("rail_freight_stage",{tile=dest,cargo="goods",role="load"},true)
    assert(not overlap.ok and overlap.why:find("another freight stage",1,true))
    local q=ask("rail_assembly",{depot=depot})
    local found,both
    for _,u in ipairs(q.wagons) do
      if u.id==34 then assert(u.quote.price==1414 and u.name=="Wood Truck");found=true end
      if u.id==32 then both=true end
    end
    assert(found and both,"Wood Truck and Goods Van must coexist in ordinary depot")
    command("rail_assembly",{token=q.token,operation="engine",stock=0})
    q=ask("rail_assembly",{depot=depot})
    command("rail_assembly",{token=q.token,operation="wagon",stock=34})
    q=ask("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(q.units) do if u.stocks[1]==0 and u.stocks[2]==34 then train=k end end
    assert(train)
    local panel=ask("depot",{mode="rail",depot=depot})
    local source,sink,ready
    for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo=="wood" then ready=true end end
    for _,r in ipairs(panel.targets) do if r.cargo=="wood" then
      if r.role=="load" then source=r.id else sink=r.id end
    end end
    assert(source and sink and source~=sink and ready)
    command("transport_start",{mode="rail",vehicle=train,first=source,second=sink,cargo="wood"})
    local orders=ask("orders",{mode="rail",vehicle=train,page=1})
    assert(orders.items[1].id==source and orders.items[2].id==sink)
    local empty
    for _=1,250 do
      ask("advance",{days=1})
      local art=visible()
      empty=empty or art=="wood_truck_empty"
      if empty and art=="wood_truck_loaded" then
        ask("checkpoint")
        local s,a,forest,mill=payload()
        if a.units>=15 and a.units<30 and a.delivered==0 and #a.batches>0 then
          assert(a.batches[1].source==forest.id and not mill.wood_received and not mill.received)
          assert(s.stock_load_tick==s.passenger_house_clock.counter)
          assert(not s.rail_iron_ore_service and not s.rail_valuables_service)
          if mixed then
            assert(s.rail_grain_service and s.freight_transactions and not s.timber_transactions)
          else
            assert(not s.rail_grain_service and s.timber_transactions and not s.freight_transactions)
          end
          goal=("RAIL_WOOD_NATIVE_SAVED %d t of real logs from Forest %d"):format(a.units,forest.id)
          return {kind="stop"}
        end
      end
    end
    local s,a=payload()
    error(("No partial Forest load at day %d, %d aboard and %d paid"):format(s.day,a.units,a.delivered))
  end
  local s,a,forest,mill,r=payload()
  assert(a.units>=15 and a.units<30 and a.batches[1].source==forest.id)
  assert(a.delivered==0 and visible()=="wood_truck_loaded")
  local carry=a.units
  local empty
  for _=1,220 do
    ask("advance",{days=1})
    empty=empty or visible()=="wood_truck_empty"
    ask("checkpoint")
    s,a,forest,mill,r=payload()
    if a.delivered>=30 and empty then
      local c=s.companies[name]
      assert(a.delivered==30 and a.revenue>0 and (a.boarded or 0)==a.delivered)
      local accepted=mixed and mill.received and mill.received.wood or mill.wood_received
      assert(accepted==30 and mill.produced.cargo=="goods",tostring(accepted))
      assert(mill.produced.current.production+mill.produced.last.production+mill.produced.waiting==30)
      assert(not forest.wood_received and not forest.received and c.paid_units==30 and c.revenue==a.revenue)
      assert(c.cash==balance-c.expense+c.revenue and r.freight.running_expense>0)
      assert(s.stock_load_tick==s.passenger_house_clock.counter)
      goal=("RAIL_WOOD_NATIVE_PASS %d t resumed, 30 t / $%d logged and converted at Sawmill %d, exact company ledger (%s)")
        :format(carry,a.revenue,mill.id,mixed and "mixed industries" or "preserved timber queues")
      return {kind="stop"}
    end
  end
  error("Reloaded train did not deliver actual logs")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary Timber freight checked",false,0)
  end,file))
end)
