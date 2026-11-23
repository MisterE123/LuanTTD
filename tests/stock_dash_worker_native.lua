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
local marker=assert(io.open(core.get_worldpath().."/qa-dmu-profile.txt"))
local variant=marker:read("*l");marker:close()
local mag=variant=="millennium"
local gauge=mag and 2 or nil
local engine=mag and 55 or 12
local art=mag and "millennium_z1" or "dash"
local model=assert(Roster.entry(engine))
local actor=mag and "RC1 Millennium Line" or "RC1 Dash Line"
local balance=250000
local function cell(x,z) return (z-1)*64+x end
local function tile(x) return cell(x,17) end
local first,second,depot=tile(11),tile(45),tile(6)
local cap={road={start_year=mag and 2010 or 1988,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready[art] and (not mag or cap.rail.advanced[engine]))
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
  p.railtype=gauge
  local q=ask("rail_quote",{request=p})
  return cmd("rail_commit",{token=q.token})
end
local captured
local function visual()
  local groups=ask("actor_frames",{windows={{x=5,z=15,w=26,h=4},{x=31,z=15,w=27,h=4}},fraction=1})
  for _,sector in ipairs(groups) do for _,r in ipairs(sector.actors) do
    if r.mode=="rail" and r.complete_parts and #r.parts==(mag and 2 or 3) then
      local p=r.parts
      assert(p[1].kind==art and p[#p].kind==art)
      if mag then
        assert(#p[1].bogies==2 and #p[2].bogies==2 and p[1].drawbar)
        assert(math.abs((p[1].rotation.y-p[2].rotation.y)%(2*math.pi)-math.pi)<.01)
        assert(p[1].stock_id==55 and p[2].stock_id==55 and p[1].body_id and p[2].body_id and p[1].body_id~=p[2].body_id)
        if not captured then
          assert(core.safe_file_write(core.get_worldpath().."/millennium-z1-frame.json",core.write_json({parts=p})))
          captured=true
        end
      else assert(p[2].kind=="wagon") end
      return true,p[1].reversed
    end
  end end
end
local function payload()
  local s=assert(checkpoint.read())
  local r=assert(s.stock_rail_dispatch.runs[1])
  local v=assert(s.stock_ship_commercial.service.vehicles[0x4000+r.paid_clock])
  local count=mag and 2 or 3
  local prototype=assert(Roster.stats(mag and {engine} or {engine,27}))
  assert(r.stock_engine==engine and r.dual_head and v.linked_heads and v.engine==engine and #v.carrying_parts==count,
    ("stock %s dual %s linked %s cargo engine %s physical bodies %s"):format(tostring(r.stock_engine),
      tostring(r.dual_head),tostring(v.linked_heads),tostring(v.engine),tostring(v.carrying_parts and #v.carrying_parts)))
  assert(not mag or r.advanced_gauge==2)
  assert(r.max_track_speed==model.speed and r.running_year_fp==prototype.running_year_fp and r.total_length==prototype.length)
  local bodies=v.carrying_parts
  local riders={}
  for i,c in ipairs(bodies) do riders[i]=c.units end
  assert(bodies[1].role=="front" and bodies[count].role=="rear")
  assert(bodies[1].capacity==model.capacity and bodies[count].capacity==model.capacity)
  if not mag then assert(bodies[2].capacity==40 and bodies[2].role=="carriage") end
  local spec={{stock_id=engine,cargo_count=riders[1],rear_cargo_count=riders[count]}}
  if not mag then spec[2]={stock_id=27,cargo_count=riders[2]} end
  local stats=assert(Roster.stats(spec))
  assert(v.units==riders[1]+riders[2]+(riders[3] or 0) and r.passengers_onboard==v.units and r.consist_mass==stats.weight)
  local p=riders
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
      if ids[1]==engine and not ids[2] then pure=offer
      elseif ids[1]==engine and ids[2]==27 then plus=offer end
    end
    assert(pure and pure.price==Roster.purchase_price(engine))
    assert(pure.help.model:find((model.capacity*2).." seats",1,true) and pure.help.model:find(model.speed.." km/h",1,true))
    if not mag then assert(plus and plus.price==23804 and plus.help.model:find("120 seats",1,true)) end
    local a=ask("rail_assembly",{depot=depot})
    local offer
    for _,o in ipairs(a.engines) do if o.id==engine then offer=o end end
    assert(offer and offer.quote.price==Roster.purchase_price(engine) and offer.help.model:find((model.capacity*2).." seats",1,true))
    cmd("rail_assembly",{token=a.token,operation="engine",stock=engine})
    a=ask("rail_assembly",{depot=depot})
    if not mag then cmd("rail_assembly",{token=a.token,operation="wagon",stock=27}) end
    a=ask("rail_assembly",{depot=depot})
    local train
    for k,u in pairs(a.units) do
      if u.stocks[1]==engine and u.stocks[2]==(not mag and 27 or nil) and not u.stocks[3] then train=k;assert(u.passenger) end
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
      if displayed and not v.delivered and p[1]>0 and p[2]>0 and (mag or p[3]>0) then
        goal=("DASH_WORKER_NATIVE_SAVED %s %s separate boarded counts"):format(art,table.concat(p,"/"))
        return {kind="stop"}
      end
    end
    error("No visible Dash boarded all three bodies")
  end
  local s,r,v,p=payload()
  local saved=initial.stock_ship_commercial.service.vehicles[v.id]
  for i,u in ipairs(p) do assert(u>0 and saved.carrying_parts[i].units==u) end
  assert(not v.delivered and visual())
  if mag then
    local before=assert(initial.stock_rail_dispatch.runs[1].matched_cab_ids)
    assert(r.matched_cab_ids[1]==before[1] and r.matched_cab_ids[2]==before[2])
  end
  local reversed,peak
  for _=1,180 do
    ask("advance",{days=1})
    local _,rev=visual();reversed=reversed or rev
    ask("checkpoint")
    s,r,v=payload()
    peak=math.max(peak or 0,r.speed)
    if reversed and (v.delivered or 0)==(mag and 50 or 120) and peak>64 then
      local c=assert(s.companies[actor])
      assert(c.paid_units==v.delivered and c.revenue==v.route_profit and c.cash==balance-c.expense+c.revenue)
      assert(r.passenger_finance.expense>0 and r.shuttle.reversals>0)
      goal=("DASH_WORKER_NATIVE_PASS native reversal, restored %d seats occupied, delivered %d for $%d, peak %d")
        :format(p[1]+p[2]+(p[3] or 0),v.delivered,c.revenue,peak)
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
