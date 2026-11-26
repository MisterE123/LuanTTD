-- Own a real pair of trains under Luanti's campaign worker. Save a
-- copied order draft in SQLite, edit the original, and start the copy.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local ck=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=ck.read()
local owner,other="Order Copy QA","Outside Owner"
local function tile(x) return 16*64+x end
local depot,west,middle,east=tile(6),tile(12),tile(28),tile(45)
local cap={road={start_year=1950,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
if not initial then
  local s=Sim.new(1725)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function() return 1 end)
  for i=1,4096 do s.tiles[i]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  Sim.company(s,owner).cash=220000;Sim.company(s,other).cash=220000
  ck.write_state(s)
end
local thread,rev,goal
local function next_(r)
  local ok,req=coroutine.resume(thread,r);assert(ok,req)
  if req then assert(client.query(req,next_)) end
end
local function ask(kind,f,raw)
  f=f or {};f.kind,f.player=kind,f.player or owner
  local reply=assert(coroutine.yield(f))
  rev=reply.revision or rev
  if raw then return reply end
  assert(reply.ok,tostring(reply.why))
  return reply.value
end
local function command(kind,p,raw,player)
  p.kind,p.revision=kind,rev
  return ask("command",{command=p,player=player},raw)
end
local function lay(req)
  command("rail_commit",{token=ask("rail_quote",{request=req}).token})
end
local function buy()
  local q=ask("transport_quote",{request={mode="rail",operation="buy",depot=depot,parts={0,27}}})
  return command("transport_commit",{token=q.token}).id
end
local function view(v,raw,player) return ask("orders",{mode="rail",vehicle=v,player=player,page=1},raw) end
local function set(v,operation,row,destination)
  command("vehicle_order",{mode="rail",vehicle=v,order_revision=view(v).revision,
    operation=operation,row=row,destination=destination})
end
local function work()
  if not initial then
    lay({tool="track",first=tile(7),last=tile(55),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({12,28,45}) do
      lay({tool="station",first=tile(x),last=tile(x+2),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    local orig,copy=buy(),buy()
    local a,b,c
    ask("checkpoint")
    local s=ck.read()
    a,b,c=s.tiles[west].rail_station_id,s.tiles[middle].rail_station_id,s.tiles[east].rail_station_id
    local empty=view(orig)
    assert(empty.parked and empty.can_insert and not empty.can_start and #empty.items==0)
    set(orig,"append",nil,a)
    local one=view(orig)
    assert(one.parked and #one.items==1 and not one.can_start)
    assert(not command("transport_start",{mode="rail",vehicle=orig,depot=depot,
      start_draft=true,draft_revision=one.revision},true).ok)
    command("vehicle_order",{mode="rail",vehicle=orig,order_revision=one.revision,operation="append",tile=east})
    set(orig,"append",nil,b)
    set(orig,"up",3)
    local draft=view(orig)
    assert(draft.parked and draft.can_start and #draft.items==3)
    assert(draft.items[1].id==a and draft.items[2].id==b and draft.items[3].id==c)
    ask("checkpoint")
    local unit=ck.read().stock_rail_fleet.units[orig]
    assert(unit.status=="depot" and unit.order_draft.orders[3].station==c)
    assert(not command("transport_start",{mode="rail",vehicle=orig,depot=depot,
      start_draft=true,draft_revision=one.revision},true).ok)
    command("transport_start",{mode="rail",vehicle=orig,depot=depot,start_draft=true,draft_revision=draft.revision})
    assert(view(orig).active==1 and #view(orig).items==3)
    core.log("action","RAIL_FRESH_DRAFT_NATIVE: list and tile picks persisted in three-stop order; no dispatch until explicit Start")
    set(orig,"load",1,4)
    set(orig,"unload",2,2)
    local function sources(player)
      return ask("depot_order_sources",{mode="rail",vehicle=copy,depot=depot,player=player},player~=nil)
    end
    assert(not sources(other).ok)
    local x=sources()
    assert(#x.sources==1 and x.sources[1].id==orig and x.sources[1].count==3 and x.count==0)
    local req={mode="rail",vehicle=copy,depot=depot,source=orig,source_revision=x.sources[1].revision,
      target_revision=x.revision}
    assert(not command("depot_copy_orders",req,true,other).ok)
    set(orig,"load",1,2)
    local r=command("depot_copy_orders",req,true)
    assert(not r.ok and r.why:find("changed",1,true))
    assert(#view(copy).items==0 and view(copy).parked)
    req.source_revision=sources().sources[1].revision
    command("depot_copy_orders",req)
    set(orig,"load",1,4) -- must not edit the other vehicle
    local o=view(copy)
    assert(#o.items==3 and o.items[1].id==a and o.items[1].cargo.load==2 and o.items[2].id==b
      and o.items[2].cargo.unload==2 and o.items[3].id==c and o.parked and o.can_insert)
    assert(view(orig).items[1].cargo.load==4 and not view(copy,true,other).ok)
    assert(not command("depot_copy_orders",req,true).ok)
    local row=ask("depot",{mode="rail",depot=depot}).vehicles[2]
    assert(row.id==copy and row.order_copy and row.copied==3 and row.draft_revision==o.revision)
    ask("checkpoint")
    local save=ck.read()
    assert(save.stock_rail_fleet.units[copy].order_draft.orders[2].unload_type==2)
    goal="RAIL_COPY_WORKER_NATIVE_SAVED three independent orders, Full load all + Transfer"
    return {kind="stop"}
  end
  local copy,orig
  for id,u in pairs(initial.stock_rail_fleet.units) do
    if u.order_draft then copy=id else orig=id end
  end
  assert(copy and orig)
  local o=view(copy)
  assert(#o.items==3 and o.items[1].cargo.load==2 and o.items[2].cargo.unload==2)
  assert(view(orig).items[1].cargo.load==4)
  local req={mode="rail",vehicle=copy,depot=depot,copied=true,draft_revision="rail-parked:0"}
  assert(not command("transport_start",req,true).ok)
  req.draft_revision=o.revision
  command("transport_start",req)
  local moved=view(copy)
  assert(#moved.items==3 and moved.items[1].cargo.load==2 and moved.items[2].cargo.unload==2
    and moved.can_insert and moved.active==1)
  local dest=ask("depot",{mode="rail",depot=depot}).vehicles[2]
  assert(not dest.copied and not dest.order_copy)
  ask("checkpoint")
  local s=ck.read()
  local r=s.stock_rail_dispatch.runs[2]
  assert(r and r.fleet_id==copy and r.order.load_type==2 and r.orders[2].unload_type==2
    and not s.stock_rail_fleet.units[copy].order_draft)
  goal="RAIL_COPY_WORKER_NATIVE_PASS parked draft survived restart; all three destinations and loading rules dispatched independently"
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(r) assert(r.ready);rev=r.revision;next_(r) end,function(why,_,_,error_)
    assert(why=="stopped" and goal,tostring(error_ or why))
    core.log("action",goal);core.request_shutdown("Rail depot copy test complete",false,0)
  end,file))
end)
