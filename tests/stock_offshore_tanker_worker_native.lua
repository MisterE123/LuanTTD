-- SPDX-License-Identifier: GPL-2.0-only
-- Disposable campaign fixture; real authority, stock loading and SQLite.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local actor="North Reach Tanker"
local wage=100000
local function cell(x,z) return (z-1)*64+x end
local rigs,refinery,depot=cell(12,47),cell(31,32),cell(17,35)
local cap={road={start_year=1965,foster=true,breakdowns=0,service_interval=0},ferry={[204]=true,[205]=true},
  air={},oil_tanker=true,durable_actions=true}
for _,id in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..id,"air") end
if not initial then
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
  for z=1,64 do for x=1,64 do
    s.tiles[cell(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
      water_class=z>=33 and "sea" or nil}
  end end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.ship_paid_service,s.road_oil=true,true
  s.stock_serve_neutral_industries=false
  local land=assert(Sim.mount_oil_world(s,T,true))
  assert(land.place(s,assert(land.plan(s,12,28,31,28))))
  s.sites[3]={id=3,name="North Reach",kind="town",tile=cell(9,14),population=280,stock={},produced={},received={},service=0}
  s.tiles[cell(9,14)].site=3
  s.next_stock_oil_industry=0x3002
  local Rig=m("openttd/oil_rig")
  local W=m("offshore_rig_world")(Sim,T,Rig,Sim.oil_rules())
  local options={economy_year=1965,name="North Reach Oil Rig",random=function() return 0 end,initial_random=122}
  local stock=assert(W.place(s,assert(W.quote(s,rigs,options)),options))
  assert(not stock.neutral_station and stock.tiles[1].stage==0)
  Sim.company(s,actor).cash=wage
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
  assert(r.ok,kind..":"..tostring(r.why))
  revision=r.revision or revision
  return r.value
end
local function commit(q)
  local offer=ask("transport_quote",{request=q})
  return ask("command",{command={kind="transport_commit",token=offer.token,revision=revision}})
end
local function inspect()
  local s=assert(checkpoint.read())
  local rig=assert(s.stock_oil_industries[0x3002])
  assert(rig.neutral_station==1 and s.stock_neutral_stations[1].industry==rig.id)
  assert(s.stock_small_airports[1].layout=="oilrig" and not s.stock_small_airports[1].owner)
  assert(s.tiles[rigs].ship.kind=="oilrig")
  local v=assert(s.stock_oil_ship_service.vehicle)
  assert(not s.stock_oil_ship_route.failure,s.stock_oil_ship_route.failure)
  return s,v
end
local function visible()
  local frames=ask("actor_frames",{windows={{x=6,z=29,w=31,h=25}},fraction=1})
  for _,frame in ipairs(frames) do
    for _,r in ipairs(frame.actors) do
      if r.mode=="ship" and r.id=="oil" then
        assert(r.engine==204 and r.owner==actor)
        return true
      end
    end
  end
end
local function work()
  if initial and initial.stock_oil_ship_service.vehicle.delivered==220 then
    ask("checkpoint")
    local s,v=inspect()
    assert(v.delivered==220 and s.companies[actor].revenue==initial.companies[actor].revenue)
    goal="OFFSHORE_TANKER_NATIVE_CONFIRMED no duplicate payout after reopening again"
    return {kind="stop"}
  end
  if not initial then
    -- Only the real landscape loop may finish construction and activate
    -- the neutral depot-less station. No forced test support on restart.
    local rig
    for _=1,150 do
      ask("advance",{days=1});ask("checkpoint")
      rig=assert(checkpoint.read().stock_oil_industries[0x3002])
      if rig.neutral_station then break end
    end
    assert(rig.neutral_station==1 and rig.tiles[1].completed,"Authority did not finish the rig")
    local b=commit({mode="ship",operation="build",kind="dock",tile=refinery}).id
    local d=commit({mode="ship",operation="build",kind="depot",tile=depot,axis=0}).id
    local panel=ask("depot",{mode="ship",depot=d})
    local selected,offer
    for _,row in ipairs(panel.offers) do if row.request.engine==204 then offer=row end end
    for _,row in ipairs(panel.targets) do if row.id==1 and row.role=="load" and row.cargo=="oil" then selected=row end end
    assert(selected and selected.label=="North Reach Oil Rig")
    assert(offer and offer.price==40625)
    assert(commit(offer.request).id=="oil")
    ask("command",{command={kind="transport_start",mode="ship",vehicle="oil",cargo="oil",depot=d,first=1,second=b,
        revision=revision}})
    ask("checkpoint")
    local initial=inspect()
    local typed=assert(initial.stock_oil_ship_route.transport_orders)
    assert(typed[1].kind=="station" and typed[1].id==1 and typed[1].cargo_order=="full")
    assert(typed[2].kind=="station" and typed[2].id==b and typed[2].cargo_order=="no_load")
    local orders=ask("orders",{mode="ship",vehicle="oil",page=1})
    assert(orders.items[1].id==1 and orders.items[1].label:find("Oil Rig",1,true))
    local seen=false
    for _=1,180 do
      ask("advance",{days=1}); seen=visible() or seen
      ask("checkpoint")
      local s,v=inspect()
      if seen and v.units>0 and v.units<220 and (v.delivered or 0)==0 then
        assert(v.load_state and #v.batches>0 and v.batches[1].source==0x3002)
        goal=("OFFSHORE_TANKER_NATIVE_SAVED %d kL from the rig"):format(v.units)
        return {kind="stop"}
      end
    end
    error("Native tanker never boarded real oil rig cargo")
  else
    local s,v=inspect()
    assert(v.units==initial.stock_oil_ship_service.vehicle.units and v.batches[1].source==0x3002)
    for _=1,200 do
      ask("advance",{days=1})
      ask("checkpoint")
      s,v=inspect()
      if v.delivered==220 then
        local refinery=assert(s.stock_oil_industries[0x3001])
        assert(refinery.received.oil==220 and s.companies[actor].revenue==v.revenue and v.revenue>0,
          ("%s kL, %s revenue/%s ship"):format(refinery.received.oil,s.companies[actor].revenue,v.revenue))
        assert(s.stock_owned_oil_ship.expense>0)
        goal=("OFFSHORE_TANKER_NATIVE_PASS restored real rig cargo and paid $%d for 220 kL at the refinery"):format(v.revenue)
        return {kind="stop"}
      end
    end
    error("Native tanker never paid real refinery after rig load")
  end
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Stock offshore ship verified",false,0)
  end,file))
end)
