-- The actual Luanti worker owns this flat authored geography. Only the
-- source industry placement is seeded; stations, orders, purchases,
-- all loading, and receipts go through the live normal commands.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local codec=m("packed_campaign")
local name="RC1 Double Ore"
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,codec,file)
local initial=checkpoint.read()
local cfg=assert(io.open(core.get_worldpath().."/qa-multi-ore-phase.txt","r"))
local mode=cfg:read("*l");cfg:close()
local function cell(x,z) return (z-1)*64+x end
local ore_depot=cell(6,16)
local ore_source,ore_sink,short_sink=cell(10,16),cell(43,16),cell(41,16)
local windows={{x=5,z=15,w=31,h=4},{x=36,z=15,w=20,h=4}}
local Roster=m("openttd/rail_roster")
local balance=300000
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
for _,variant in ipairs({"iron_ore_hopper_empty","iron_ore_hopper_loaded","steel_truck_empty","steel_truck_loaded"}) do
  assert(cap.rail.ready[variant],variant)
end
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end

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
  local _,_,Rules=Sim.mount_farm_world(s,T,true)
  local H=Sim.mount_heavy_world(s,T)
  assert(Sim.mount_oil_world(s,T,true))
  local function record(kind,x,z)
    return Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950})
  end
  local ore=assert(H.place_generated(s,"iron_mine",cell(10,12),{record=record("iron_mine",10,12),name="Ore"}))
  local mill=assert(H.place_generated(s,"steel_mill",cell(43,12),{record=record("steel_mill",43,12),name="Steel"}))
  s.rail_multi_ore_qa={mine=ore.id,mill=mill.id}
  Sim.company(s,name).cash=balance
  checkpoint.write_state(s)
else
  assert(mode=="reload" or mode=="finish" or mode=="confirm")
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
local function lay(fields)
  local p=query("rail_quote",{request=fields})
  return command("rail_commit",{token=p.token})
end
local function station(x,n)
  return lay({tool="station",first=cell(x,16),last=cell(x+n-1,16),axis=0,length=n,tracks=1,separate=true,drag=true})
end
local function check()
  local s=assert(checkpoint.read())
  local a=assert(s.stock_rail_iron_ore.vehicle)
  local train=assert(s.stock_rail_dispatch.runs[1])
  local body=a.carrying_parts
  assert(#body==2 and #train.freight_parts==2 and #train.consist.parts==3 and train.total_length==24)
  local record=assert(s.stock_rail_fleet.units[train.fleet_id])
  assert(a.units==body[1].units+body[2].units and train.cargo_onboard==a.units)
  local stat=assert(Roster.stats({0,{stock_id=35,cargo_count=body[1].units},{stock_id=35,cargo_count=body[2].units}},
    {freight_trains=train.freight_multiplier}))
  assert(train.consist_mass==stat.weight and train.acceleration==stat.acceleration)
  for i,v in ipairs(body) do
    assert(v.body_id==record.parts[i+1].body_id and v.part==i+1 and v.stock==35 and v.capacity==30 and v.units<=30)
    assert(train.freight_parts[i].body_id==v.body_id and v.cargo_age_counter>0 and v.cargo_age_counter<=185)
  end
  assert(s.passenger_house_clock.counter==s.day*74 and s.stock_load_tick==s.day*74)
  assert(train.phase~="blocked",train.failure)
  return s,a,train,body[1],body[2]
end
local function vis(train,left,right,kind)
  local batch=query("actor_frames",{windows=windows,fraction=1})
  for _,region in ipairs(batch) do
    for _,row in ipairs(region.actors) do
      if row.mode=="rail" and row.wagon==35 and row.complete_parts and #row.parts==3 then
        local by={}
        for _,p in ipairs(row.parts) do by[p.body_index]=p end
        assert(by[1].kind=="steam" and by[1].body_id==train.freight_engine_body_id)
        for _,v in ipairs({left,right}) do
          local p=assert(by[v.part])
          assert(p.stock_id==35 and p.body_id==v.body_id and p.rotation.y==p.rotation.y)
          assert(p.kind==(v.units>=15 and "iron_ore_hopper_loaded" or "iron_ore_hopper_empty"))
        end
        if kind then
          assert(core.safe_file_write(core.get_worldpath().."/ore-"..kind..".json",core.write_json(row)))
        end
        return true
      end
    end
  end
end
local function step()
  query("advance",{days=1})
  query("checkpoint")
  return check()
end
local function work()
  if mode=="start" then
    lay({tool="track",first=cell(7,16),last=cell(51,16),track=Track.X})
    lay({tool="depot",first=ore_depot,direction=Track.SW})
    station(10,2);station(41,1);station(43,2)
    for _,row in ipairs({{ore_source,"load"},{short_sink,"unload"},{ore_sink,"unload"}}) do
      command("rail_freight_stage",{tile=row[1],cargo="iron_ore",role=row[2]})
    end
    local function offer(parts)
      return query("transport_quote",{request={mode="rail",operation="buy",depot=ore_depot,parts=parts}},true)
    end
    assert(not offer({0,35,35,35}).ok)
    assert(not offer({0,35,36}).ok and not offer({0,35,27}).ok and not offer({0,35,0}).ok)
    local panel=query("depot",{mode="rail",depot=ore_depot})
    local pair
    for _,offer in ipairs(panel.offers) do
      local list=offer.request.parts
      if #list==3 and list[1]==0 and list[2]==35 and list[3]==35 then pair=offer end
    end
    assert(pair and pair.help.model:find("60 t of ore",1,true))
    local q=query("rail_assembly",{depot=ore_depot})
    command("rail_assembly",{token=q.token,operation="engine",stock=0})
    for _=1,2 do
      q=query("rail_assembly",{depot=ore_depot})
      local stock
      for _,wagon in ipairs(q.wagons) do if wagon.id==35 then stock=wagon end end
      assert(stock and stock.quote.price==1398)
      command("rail_assembly",{token=q.token,operation="wagon",stock=35})
    end
    q=query("rail_assembly",{depot=ore_depot})
    local train
    for id,u in pairs(q.units) do
      if #u.stocks==3 and u.stocks[1]==0 and u.stocks[2]==35 and u.stocks[3]==35 then train=id end
    end
    assert(train,"The ordinary yard did not attach both genuine #35s")
    query("checkpoint")
    local tiles=assert(checkpoint.read()).tiles
    local from,to,small=tiles[ore_source].rail_station_id,tiles[ore_sink].rail_station_id,tiles[short_sink].rail_station_id
    local function request(dest,raw)
      return command("transport_start",{mode="rail",vehicle=train,first=from,second=dest,cargo="iron_ore"},raw)
    end
    local refused=request(small,true)
    assert(not refused.ok and tostring(refused.why):find("platform",1,true),refused.why)
    request(to)
    local o=query("orders",{mode="rail",vehicle=train,page=1})
    assert(o.items[1].id==from and o.items[2].id==to and o.can_replace and not o.cargo_rules)
    local a,t,p,r
    for _=1,220 do
      _,a,t,p,r=step()
      if a.load_state and p.units>=15 and r.units<15 and a.delivered==0 and vis(t,p,r,"asymmetric") then
        assert(p.cargo_tile and r.cargo_tile and p.cargo_tile~=r.cargo_tile and a.load_state.platform_tiles==2)
        goal=("RAIL_MULTI_ORE_SAVED ids %d/%d; %d/%d ore, different loaded/empty meshes, short station refused")
          :format(p.body_id,r.body_id,p.units,r.units)
        return {kind="stop"}
      end
    end
    error(("Expected genuine differently loaded wagons: %s, %d/%d, paid=%d"):format(t.phase,p.units,r.units,a.delivered))
  end
  local s,a,t,p,r=check()
  if mode=="reload" then
    local before=initial.stock_rail_iron_ore.vehicle
    assert(p.cargo_age_counter==before.carrying_parts[1].cargo_age_counter and r.cargo_age_counter==before.carrying_parts[2].cargo_age_counter)
    assert(p.units>=15 and r.units<15 and vis(t,p,r))
    local moved
    for _=1,220 do
      s,a,t,p,r=step()
      if p.units==30 and r.units==30 and not a.load_state and t.speed>0 and vis(t,p,r,"moving") then moved=true end
      local l=a.load_state
      if l and l.payment and l.payment.delivered>0 and a.units>0 then
        assert(moved,"No physically moving fully loaded two-wagon consist")
        assert(s.companies[name].paid_units==0 and s.companies[name].revenue==0)
        assert(l.payment.route==199 and l.payment.delivered==10 and l.payment.delivered+a.units==60 and l.iron_ore_packet_sequence==2)
        goal=("RAIL_MULTI_ORE_PENDING uncredited $%d for %d t, both loaded wagons moved")
          :format(l.payment.route,l.payment.delivered)
        return {kind="stop"}
      end
    end
    error(("No pending visit: %s %d/%d paid=%d"):format(t.phase,p.units,r.units,a.delivered))
  elseif mode=="confirm" then
    local fare=a.last_fare
    s,a,t=step()
    assert(a.delivered==60 and a.revenue==fare and s.companies[name].paid_units==60 and s.companies[name].revenue==fare)
    goal=("RAIL_MULTI_ORE_CONFIRMED reopen did not duplicate $%d or 60 t"):format(fare)
    return {kind="stop"}
  end
  local old=initial.stock_rail_iron_ore.vehicle
  assert(a.load_state.payment.route==old.load_state.payment.route and a.delivered==0)
  for _=1,80 do
    s,a,t,p,r=step()
    if a.delivered>0 then
      local mill=s.stock_heavy_industries[s.rail_multi_ore_qa.mill]
      local c=s.companies[name]
      assert(a.delivered==60 and a.revenue==a.last_fare and a.revenue==1199)
      assert(mill.received.iron_ore==60 and c.paid_units==60 and c.revenue==a.revenue)
      assert(c.cash==balance-c.expense+c.revenue and c.cash==278882 and t.freight.running_expense>0)
      goal=("RAIL_MULTI_ORE_PASS paid $%d once for 60 t across 2 actual hoppers; exact cash $%d"):format(a.revenue,c.cash)
      return {kind="stop"}
    end
  end
  error("No complete payment")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resume(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Two ordinary rail ore hoppers verified",false,0)
  end,file))
end)
