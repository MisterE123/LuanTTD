-- SPDX-License-Identifier: GPL-2.0-only
-- Real native campaign worker: authored industry geography, paid rail and
-- stock cargo. Every shop, track, station and service goes through authority.
local mod=core.get_modpath(core.get_current_modname())
local function m(path) return dofile(mod.."/"..path..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track,Roster=m("openttd/rail_track"),m("openttd/rail_roster")
local client=m("campaign_authority_client")(core,mod)
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local file=assert(io.open(core.get_worldpath().."/rail-oil-guideway.txt"))
local phase,gauge=file:read("*l","*n");file:close()
assert(gauge==2 or gauge==3)
local profile=assert(m("rail_guideway_profiles").by_gauge[gauge])
local stock=assert(Roster.entry(profile.oil))
local name,opening="Oil Guideway Works",300000
local cap={road={start_year=gauge==3 and 2025 or 2010,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.advanced[profile.oil])
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local prior=cp.read()
local function id(x,z) return (z-1)*64+x end
local depot,a,b=id(7,26),id(11,26),id(30,26)
if not prior then
  assert(phase=="start")
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function()return 1 end)
  for i=1,64*64 do s.tiles[i]={h=1,variant=1,terrain="grass"} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_oil,s.rail_oil_service,s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true,true,true
  local W=assert(Sim.mount_oil_world(s,T,true))
  assert(W.place(s,assert(W.plan(s,12,28,31,28))))
  Sim.company(s,name).cash=opening
  cp.write_state(s)
end
local revision,thread,goal
local function resume(r)
  local ok,req=coroutine.resume(thread,r);assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(k,req)
  req=req or {};req.kind=k;req.player=name
  local r=assert(coroutine.yield(req))
  revision=r.revision or revision
  assert(r.ok,tostring(r.why))
  return r.value
end
local function cmd(kind,value)
  value.kind,value.revision=kind,revision
  return ask("command",{command=value})
end
local function lay(p)
  p.railtype=gauge
  local q=ask("rail_quote",{request=p})
  cmd("rail_commit",{token=q.token})
end
local function current()
  local s=assert(cp.read())
  local v=assert(s.stock_rail_oil and s.stock_rail_oil.vehicle)
  local r=assert(s.stock_rail_dispatch and s.stock_rail_dispatch.runs[1])
  return s,v,r
end
local expected=stock.capacity
local function work()
  if phase=="start" then
    lay({tool="track",first=id(8,26),last=id(42,26),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,pos in ipairs({a,b}) do
      lay({tool="station",first=pos,last=pos+2,axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    local q,sink,source
    cmd("rail_freight_stage",{tile=a,cargo="oil",role="load"})
    cmd("rail_freight_stage",{tile=b,cargo="oil",role="unload"})
    local panel=ask("depot",{mode="rail",depot=depot})
    for _,o in ipairs(panel.offers) do
      local p=o.request.parts
      if p and #p==2 and p[1]==profile.engine and p[2]==profile.oil then q=o end
    end
    assert(q and q.price==Roster.purchase_price(profile.engine)+Roster.purchase_price(profile.oil))
    local offer=ask("transport_quote",{request=q.request})
    cmd("transport_commit",{token=offer.token})
    panel=ask("depot",{mode="rail",depot=depot})
    for _,x in ipairs(panel.targets) do
      if x.cargo=="oil" then
        if x.role=="load" then source=x.id elseif x.role=="unload" then sink=x.id end
      end
    end
    assert(source and sink and panel.vehicles[1].cargo=="oil")
    cmd("transport_start",{mode="rail",cargo="oil",vehicle=panel.vehicles[1].id,first=source,second=sink})
    for _=1,320 do
      ask("advance",{days=1});ask("checkpoint")
      local s,v,r=current()
      if v.units>0 and v.units<expected and v.delivered==0 then
        assert(v.wagon==stock.stock_id and r.advanced_gauge==gauge and r.traction_railtypes[gauge])
        local pos=ask("actor_frames",{windows={{x=6,z=24,w=25,h=6},{x=31,z=24,w=18,h=6}},fraction=1})
        for _,sector in ipairs(pos) do for _,actor in ipairs(sector.actors) do
          if actor.mode=="rail" and actor.complete_parts and #actor.parts==2 then
            assert(actor.parts[1].kind==profile.engine_visual and actor.parts[2].kind==profile.oil_visual)
            assert(#actor.parts[2].bogies==2 and actor.parts[1].drawbar)
            assert(actor.parts[1].body_id==r.freight_engine_body_id and actor.parts[2].body_id==r.freight_wagon_body_id)
            assert(actor.parts[1].stock_id==profile.engine and actor.parts[2].stock_id==profile.oil)
            assert(core.safe_file_write(core.get_worldpath().."/guideway-oil-loaded-frame.json",
              core.write_json({parts=actor.parts,gauge=gauge,oil=v.units})))
            goal=("GUIDEWAY_OIL_SAVED gauge=%d stock=%d oil=%d"):format(gauge,v.wagon,v.units)
            return {kind="stop"}
          end
        end end
      end
    end
    error("No partial loaded native guideway Tanker")
  end
  local old=assert(prior and prior.stock_rail_oil and prior.stock_rail_oil.vehicle)
  local s,v,r=current()
  assert(v.units==old.units and v.wagon==profile.oil and v.delivered==0)
  local former=assert(prior.stock_rail_dispatch.runs[1])
  assert(r.freight_engine_body_id==former.freight_engine_body_id and r.freight_wagon_body_id==former.freight_wagon_body_id)
  for _=1,250 do
    ask("advance",{days=1});ask("checkpoint")
    s,v,r=current()
    if v.delivered>0 then
      local company=s.companies[name]
      assert(v.delivered==expected and v.revenue>0 and v.revenue==company.revenue and company.paid_units==expected)
      assert(s.stock_oil_industries[0x3001].received.oil==expected)
      assert(company.expense>0 and company.cash==opening+company.revenue-company.expense)
      goal=("GUIDEWAY_OIL_NATIVE_PASS gauge=%d stock=%d refinery received %d kL exactly once for $%d")
        :format(gauge,v.wagon,v.delivered,v.revenue)
      return {kind="stop"}
    end
  end
  error("No paid guideway Oil deliverable")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal);core.request_shutdown(goal,false,0)
  end,"luanttd-wide-campaign.chk"))
end)
