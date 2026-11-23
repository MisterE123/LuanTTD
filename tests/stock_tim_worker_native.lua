-- Luanti worker: a purchased T.I.M. coach service across a graded
-- electrified stock bridge. Check both projected physical collectors. Checkpoint then restart.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local asia=core.settings:get_bool("luanttd_qa_asiastar_worker",false)
local model=asia and {id=26,kind="asiastar",year=1995,power=8000,speed=264,annual=1200000,price=69116}
  or {id=25,kind="tim",year=1988,power=7000,speed=240,annual=1152000,price=64429}
local actor="RC1 Electric Express"
local balance=250000
local function cell(x,z) return (z-1)*64+x end
local function tile(x) return cell(x,17) end
local first,second,depot=tile(11),tile(45),tile(6)
local bridge_first,bridge_last=tile(29),tile(33)
local cap={road={start_year=model.year,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,true,true),ferry={},air={},oil_tanker=true,durable_actions=true}
cap.rail.bridge_wire=true
assert(cap.rail.ready[model.kind] and cap.rail.split[model.kind])
for _,id in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..id,"air") end
if not initial then
  local s=Sim.new(1725)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function(x) return (x==31 or x==32) and 0 or 1 end)
  for i=1,4096 do s.tiles[i]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.stock_electrification=true
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
local function cmd(kind,p,raw)
  p.kind,p.revision=kind,revision
  if raw then
    local r=assert(coroutine.yield({kind="command",player=actor,command=p}))
    revision=r.revision or revision
    return r
  end
  return ask("command",{command=p})
end
local function lay(p)
  local q=ask("rail_quote",{request=p})
  return cmd("rail_commit",{token=q.token})
end

local function buy_or_build(p)
  local q=ask("transport_quote",{request=p})
  return cmd("transport_commit",{token=q.token})
end
local function wire(a,b)
  return lay({tool="wire",first=a,last=b or a,target=1})
end
local function observe_collectors(seen,back)
  -- Most of the train can traverse a bridge during one game day.
  -- Sample the real movement replay, not only the latest tick.
  for i=0,10 do
    if seen[1] and seen[3] then break end
    local groups=ask("actor_frames",{windows={{x=24,z=15,w=14,h=4}},fraction=i/10})
    for _,sector in ipairs(groups) do for _,r in ipairs(sector.actors) do
      if r.mode=="rail" then
        for _,p in ipairs(r.parts) do
          if p.kind==model.kind and p.collector and p.collector.rows and p.reversed==back then
            assert(p.body_index==1 or p.body_index==3)
            assert(#p.collector.rows>=1 and p.collector.axis~=nil)
            seen[p.body_index]=true
          elseif p.kind=="wagon" then assert(not p.collector) end
        end
      end
    end end
  end
end
local function payload()
  local s=assert(checkpoint.read())
  local r=assert(s.stock_rail_dispatch.runs[1])
  local v=assert(s.stock_ship_commercial.service.vehicles[0x4000+r.paid_clock])
  assert(r.stock_engine==model.id and r.dual_head and r.bridge_collectors and r.power==model.power and
    r.max_track_speed==model.speed and r.total_length==24 and r.running_year_fp==model.annual)
  assert(#v.carrying_parts==1 and v.carrying_parts[1].capacity==40 and v.carrying_parts[1].role=="carriage")
  assert(v.units==v.carrying_parts[1].units and r.passengers_onboard==v.units)
  return s,r,v
end
local function work()
  local seen={}
  if not initial then
    lay({tool="track",first=tile(7),last=tile(28),track=Track.X})
    lay({tool="track",first=tile(34),last=tile(58),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({11,45}) do
      lay({tool="station",first=tile(x),last=tile(x+2),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    buy_or_build({mode="rail",operation="bridge",tile=bridge_first,last=bridge_last})
    wire(depot,tile(28));wire(tile(34),tile(58))
    local panel=ask("depot",{mode="rail",depot=depot})
    local offer
    for _,o in ipairs(panel.offers) do if o.request.parts[1]==model.id and o.request.parts[2]==27 then offer=o end end
    assert(offer and offer.price==model.price and offer.help.model:find(model.speed.." km/h",1,true))
    local train=buy_or_build(offer.request).id
    ask("checkpoint")
    local t=assert(checkpoint.read()).tiles
    local a,b=t[first].rail_station_id,t[second].rail_station_id
    local req={mode="rail",vehicle=train,first=a,second=b}
    assert(not cmd("transport_start",req,true).ok,"An unwired gap must block real electric service")
    wire(bridge_first)
    cmd("transport_start",req)
    for _=1,380 do
      ask("advance",{days=1})
      observe_collectors(seen,false)
      ask("checkpoint")
      local _,_,v=payload()
      if seen[1] and seen[3] and v.units>0 and not v.delivered then
        goal=("STOCK_ELECTRIC_EXPRESS_WORKER_NATIVE_SAVED paid route with %d riders; both heads have projected bridge wire"):format(v.units)
        return {kind="stop"}
      end
      if v.delivered and v.delivered>0 then error("First paid delivery before both projected wire samples") end
    end
    error("T.I.M. carriage did not reach powered bridge")
  end
  local s,r,v=payload()
  local passengers=v.units
  assert(passengers>0 and not v.delivered)
  for _=1,220 do
    ask("advance",{days=1})
    observe_collectors(seen,true)
    ask("checkpoint")
    s,r,v=payload()
    if seen[1] and seen[3] and (v.delivered or 0)>0 and r.shuttle.reversals>0 then
      local c=assert(s.companies[actor])
      assert(c.paid_units==v.delivered and c.revenue==v.route_profit and c.cash==balance-c.expense+c.revenue)
      goal=("STOCK_ELECTRIC_EXPRESS_WORKER_NATIVE_PASS restored %d riders, paid %d for $%d; reverses both projected collectors")
        :format(passengers,v.delivered,c.revenue)
      return {kind="stop"}
    end
  end
  error("Powered train did not continue to paid arrival")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary T.I.M. worker verified",false,0)
  end,file))
end)
