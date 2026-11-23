-- The actual Luanti worker owns this flat authored geography. Only the
-- source industry placement is seeded; stations, orders, purchases,
-- all loading, and receipts go through the live normal commands.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local codec=m("packed_campaign")
local name="RC1 Metals Rail"
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,codec,file)
local initial=checkpoint.read()
local cfg=core.settings
local mode=cfg:get("luanttd_qa_rail_metals_phase")
local function cell(x,z) return (z-1)*64+x end
local ore_depot,steel_depot=cell(6,16),cell(20,9)
local ore_source,ore_sink,steel_source,steel_sink=cell(10,16),cell(26,16),cell(26,9),cell(45,9)
local windows={{x=5,z=15,w=31,h=4},{x=20,z=8,w=32,h=4},{x=50,z=8,w=6,h=4}}
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
for _,variant in ipairs({"iron_ore_hopper_empty","iron_ore_hopper_loaded","steel_truck_empty","steel_truck_loaded"}) do
  assert(cap.rail.ready[variant],variant)
end
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end

local function check_payload()
  local s=assert(checkpoint.read())
  local a,b=assert(s.stock_rail_iron_ore.vehicle),assert(s.stock_rail_steel.vehicle)
  return s,a,b
end
if not initial then
  assert(mode=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function() return 1 end)
  for id=1,4096 do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_farm,s.road_heavy,s.road_oil,s.road_junction_clearance=true,true,true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  s.stock_oil_industries={}
  s.stock_farm_frozen,s.stock_oil_frozen=true,true
  local Farm,_,Rules=Sim.mount_farm_world(s,T,true)
  local H=Sim.mount_heavy_world(s,T)
  assert(Sim.mount_oil_world(s,T,true))
  local function record(kind,x,z)
    return Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950})
  end
  local ore=assert(H.place_generated(s,"iron_mine",cell(10,12),{record=record("iron_mine",10,12),name="Ore"}))
  local mill=assert(H.place_generated(s,"steel_mill",cell(26,12),{record=record("steel_mill",26,12),name="Steel"}))
  local factory=assert(Farm.place_generated(s,"factory",cell(45,12),
    {record=record("factory",45,12),name="Factory"},function()return 0 end))
  s.rail_metals_native_qa={mine=ore.id,mill=mill.id,factory=factory.id}
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
local function lay(z,a,b,depot,starts,sinks)
  local function q(fields)
    local p=query("rail_quote",{request=fields})
    command("rail_commit",{token=p.token})
  end
  q({tool="track",first=cell(a,z),last=cell(b,z),track=Track.X})
  q({tool="depot",first=depot,direction=Track.SW})
  for _,x in ipairs({starts,sinks}) do
    q({tool="station",first=cell(x,z),last=cell(x+2,z),axis=0,length=3,tracks=1,separate=true,drag=true})
  end
end
local function pick(depot,id)
  local q=query("rail_assembly",{depot=depot})
  local function offer(list,stock)
    for _,u in ipairs(list) do if u.id==stock then return u end end
  end
  assert(offer(q.engines,0))
  assert(offer(q.wagons,id).quote.price==(id==35 and 1398 or 1531))
  command("rail_assembly",{token=q.token,operation="engine",stock=0})
  q=query("rail_assembly",{depot=depot})
  command("rail_assembly",{token=q.token,operation="wagon",stock=id})
  q=query("rail_assembly",{depot=depot})
  for k,u in pairs(q.units) do if u.stocks[1]==0 and u.stocks[2]==id then return k end end
  error("Purchased wagon is not coupled")
end
local function stage(tile,cargo,role,raw)
  return command("rail_freight_stage",{tile=tile,cargo=cargo,role=role},raw)
end
local function send_orders(depot,train,cargo)
  local panel=query("depot",{mode="rail",depot=depot})
  local a,b,matched
  for _,v in ipairs(panel.vehicles) do if v.id==train and v.cargo==cargo then matched=true end end
  assert(matched,"Live depot missed bought freight train")
  for _,t in ipairs(panel.targets) do
    if t.cargo==cargo and t.role=="load" then a=t.id
    elseif t.cargo==cargo and t.role=="unload" then b=t.id end
  end
  assert(a and b and a~=b)
  command("transport_start",{mode="rail",vehicle=train,first=a,second=b,cargo=cargo})
  local order=query("orders",{mode="rail",vehicle=train,page=1})
  assert(order.items[1].id==a and order.items[2].id==b)
end
local function vis()
  local batch=query("actor_frames",{windows=windows,fraction=1})
  local got={}
  for _,region in ipairs(batch) do
    for _,row in ipairs(region.actors) do
      if row.mode=="rail" and (row.wagon==35 or row.wagon==36) then
        assert(row.complete_parts and row.part_count==2 and #row.parts==2)
        for _,part in ipairs(row.parts) do
          if part.body_index==2 then
            assert(type(part.rotation.y)=="number" and part.rotation.y==part.rotation.y)
            got[row.wagon]=part.kind
          end
        end
      end
    end
  end
  return got
end
local function work()
  if mode=="start" then
    command("company_open",{})
    lay(16,7,33,ore_depot,10,26)
    lay(9,21,52,steel_depot,26,45)
    assert(not stage(ore_source,"iron_ore","unload",true).ok)
    stage(ore_source,"iron_ore","load")
    stage(ore_sink,"iron_ore","unload")
    assert(not stage(ore_sink,"steel","load",true).ok)
    stage(steel_source,"steel","load")
    stage(steel_sink,"steel","unload")
    send_orders(ore_depot,pick(ore_depot,35),"iron_ore")
    send_orders(steel_depot,pick(steel_depot,36),"steel")
    -- A vehicle inside the depot is legitimately not projected; observe
    -- both empty cars after departure, and the real ore load in transit.
    local ore_empty,steel_empty
    for _=1,100 do
      query("advance",{days=2})
      local v=vis()
      ore_empty=ore_empty or v[35]=="iron_ore_hopper_empty"
      steel_empty=steel_empty or v[36]=="steel_truck_empty"
      if v[35]=="iron_ore_hopper_loaded" and ore_empty and steel_empty then
        query("checkpoint")
        local s,a,b=check_payload()
        assert(a.units>=15 and a.units<30 and a.delivered==0 and b.delivered==0)
        assert(s.passenger_house_clock.counter==s.day*74)
        goal="RAIL_METALS_NATIVE_SAVED "..a.units.." ore aboard"
        return {kind="stop"}
      end
    end
    error("The stock mine did not load its native hopper")
  end
  local s,a,b=check_payload()
  assert(a.units>=15 and a.units<30 and a.delivered==0 and b.delivered==0)
  assert(vis()[35]=="iron_ore_hopper_loaded","Reopened hopper lost its visible load")
  local seen_steel
  for _=1,140 do
    query("advance",{days=3})
    local models=vis()
    if models[36]=="steel_truck_loaded" then seen_steel=true end
    if seen_steel then
      query("checkpoint")
      s,a,b=check_payload()
      local q=s.rail_metals_native_qa
      local mill,factory=s.stock_heavy_industries[q.mill],s.stock_farm_industries[q.factory]
      if a.delivered>=30 and b.delivered>=20 then
        assert(a.revenue>0 and b.revenue>0 and a.delivered%30==0 and b.delivered%20==0)
        assert(mill.received.iron_ore==a.delivered and factory.received.steel==b.delivered)
        assert(s.companies[name].paid_units==a.delivered+b.delivered)
        assert(s.companies[name].revenue==a.revenue+b.revenue)
        assert(s.passenger_house_clock.counter==s.day*74 and s.stock_load_tick==s.day*74)
        local ds=s.stock_rail_dispatch
        assert(ds.runs[1].freight.running_expense>0 and ds.runs[2].freight.running_expense>0)
        goal=("RAIL_METALS_NATIVE_PASS ore %d t / $%d; steel %d t / $%d; exact restored industry receipts")
          :format(a.delivered,a.revenue,b.delivered,b.revenue)
        return {kind="stop"}
      end
    end
  end
  query("checkpoint");s,a,b=check_payload()
  error(("No restored metals payments: ore %d aboard/%d paid, steel %d aboard/%d paid; day %d")
    :format(a.units,a.delivered,b.units,b.delivered,s.day))
end

core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready)
    revision=start.revision
    resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary metals rail checked",false,0)
  end,file))
end)
