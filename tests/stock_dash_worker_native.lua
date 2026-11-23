-- Luanti worker: a genuine depot offer/purchase and normal route with
-- independently boarding front, coach and rear. Checkpoint then restart.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local Roster=m("openttd/rail_roster")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local actor="RC1 Dash Line"
local balance=250000
local function cell(x,z) return (z-1)*64+x end
local function tile(x) return cell(x,17) end
local first,second,depot=tile(11),tile(45),tile(6)
local cap={road={start_year=1988,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready.dash)
for _,id in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..id,"air") end
if not initial then
  local s=Sim.new(1725)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function() return 1 end)
  for i=1,4096 do s.tiles[i]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  for i,x in ipairs({11,45}) do
    s.sites[i]={id=i,kind="town",name=i==1 and "Western Vale" or "East End",tile=cell(x,14),
      population=600,stock={},produced={},received={},service=0}
    for z=12,15 do for dx=-2,5 do
      local t=s.tiles[cell(x+dx,z)]
      t.house=true
      t.source_house={id=dx%2==0 and 4 or 1,town=i,completed=true}
    end end
  end
  Sim.company(s,actor).cash=balance
  checkpoint.write_state(s)
end
local thread,revision,goal
local function resume(r)
  local ok,req=coroutine.resume(thread,r)
  assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,actor
  local r=assert(coroutine.yield(fields))
  assert(r.ok,tostring(r.why))
  revision=r.revision or revision
  return r.value
end
local function cmd(kind,p)
  p.kind,p.revision=kind,revision
  return ask("command",{command=p})
end
local function lay(p)
  local q=ask("rail_quote",{request=p})
  return cmd("rail_commit",{token=q.token})
end
local function visual()
  local groups=ask("actor_frames",{windows={{x=5,z=15,w=26,h=4},{x=31,z=15,w=27,h=4}},fraction=1})
  for _,sector in ipairs(groups) do for _,r in ipairs(sector.actors) do
    if r.mode=="rail" and r.complete_parts and #r.parts==3 then
      local p=r.parts
      assert(p[1].kind=="dash" and p[2].kind=="wagon" and p[3].kind=="dash")
      return true,p[1].reversed
    end
  end end
end
local function payload()
  local s=assert(checkpoint.read())
  local r=assert(s.stock_rail_dispatch.runs[1])
  local v=assert(s.stock_ship_commercial.service.vehicles[0x4000+r.paid_clock])
  assert(r.stock_engine==12 and r.dual_head and v.linked_heads and v.engine==12 and #v.carrying_parts==3)
  assert(r.max_track_speed==120 and r.running_year_fp==364000 and r.total_length==24)
  local bodies=v.carrying_parts
  local p={bodies[1].units,bodies[2].units,bodies[3].units}
  assert(bodies[1].capacity==40 and bodies[2].capacity==40 and bodies[3].capacity==40)
  assert(bodies[1].role=="front" and bodies[2].role=="carriage" and bodies[3].role=="rear")
  local stats=assert(Roster.stats({{stock_id=12,cargo_count=p[1],rear_cargo_count=p[3]},
    {stock_id=27,cargo_count=p[2]}}))
  assert(v.units==p[1]+p[2]+p[3] and r.passengers_onboard==v.units and r.consist_mass==stats.weight)
  return s,r,v,p
end
local function work()
  if not initial then
    lay({tool="track",first=tile(7),last=tile(55),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({11,45}) do
      lay({tool="station",first=tile(x),last=tile(x+2),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    local panel=ask("depot",{mode="rail",depot=depot})
    local pure,plus
    for _,offer in ipairs(panel.offers) do
      local ids=offer.request.parts
      if ids[1]==12 and not ids[2] then pure=offer
      elseif ids[1]==12 and ids[2]==27 then plus=offer end
    end
    assert(pure and plus and pure.price==21875 and plus.price==23804)
    assert(pure.help.model:find("80 seats",1,true) and plus.help.model:find("120 seats",1,true)
      and pure.help.model:find("120 km/h",1,true))
    local a=ask("rail_assembly",{depot=depot})
    local engine
    for _,o in ipairs(a.engines) do if o.id==12 then engine=o end end
    assert(engine and engine.quote.price==21875 and engine.help.model:find("80 seats",1,true))
    cmd("rail_assembly",{token=a.token,operation="engine",stock=12})
    a=ask("rail_assembly",{depot=depot})
    cmd("rail_assembly",{token=a.token,operation="wagon",stock=27})
    a=ask("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(a.units) do
      if u.stocks[1]==12 and u.stocks[2]==27 and not u.stocks[3] then train=k;assert(u.passenger) end
    end
    assert(train,"The ordinary depot did not couple the separate coach between both powered halves")
    ask("checkpoint")
    local t=checkpoint.read().tiles
    local from,to=t[first].rail_station_id,t[second].rail_station_id
    cmd("transport_start",{mode="rail",vehicle=train,first=from,second=to})
    local order=ask("orders",{mode="rail",vehicle=train,page=1})
    assert(order.items[1].id==from and order.items[2].id==to)
    local displayed=false
    for _=1,200 do
      ask("advance",{days=1})
      displayed=visual() or displayed
      ask("checkpoint")
      local _,r,v,p=payload()
      if displayed and not v.delivered and p[1]>0 and p[2]>0 and p[3]>0 then
        goal=("DASH_WORKER_NATIVE_SAVED %d/%d/%d passengers in a stock #12 / Coach / #12"):format(unpack(p))
        return {kind="stop"}
      end
    end
    error("No visible Dash boarded all three bodies")
  end
  local s,r,v,p=payload()
  local saved=initial.stock_ship_commercial.service.vehicles[v.id]
  for i,u in ipairs(p) do assert(u>0 and saved.carrying_parts[i].units==u) end
  assert(not v.delivered and visual())
  local reversed,peak
  for _=1,180 do
    ask("advance",{days=1})
    local _,rev=visual();reversed=reversed or rev
    ask("checkpoint")
    s,r,v=payload()
    peak=math.max(peak or 0,r.speed)
    if reversed and (v.delivered or 0)>0 and peak>64 then
      local c=assert(s.companies[actor])
      assert(c.paid_units==v.delivered and c.revenue==v.route_profit and c.cash==balance-c.expense+c.revenue)
      assert(r.passenger_finance.expense>0 and r.shuttle.reversals>0)
      goal=("DASH_WORKER_NATIVE_PASS native reversal, restored %d seats occupied, delivered %d for $%d, peak %d")
        :format(p[1]+p[2]+p[3],v.delivered,c.revenue,peak)
      return {kind="stop"}
    end
  end
  error(("Dash did not pay and reverse: paid=%s phase=%s fault=%s reversed=%s peak=%s"):format(
    tostring(v.delivered),tostring(r.phase),tostring(r.failure),tostring(reversed),tostring(peak)))
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary Dash DMU worker verified",false,0)
  end,file))
end)
