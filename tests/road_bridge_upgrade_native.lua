-- The actual authority worker uses its normal bridge picker and road depot.
-- The only fixture work is the reproducible strip of land and two towns.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Speed=m("road_speed_runtime")()
local client=m("campaign_authority_client")(core,mod)
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local owner="Ordinary Bridge Construction"
local function id(x,z) return (z-1)*64+x end
local upgrade=tonumber(core.settings:get("luanttd_qa_bridge_style")) or 9
local speed=({[3]=80,[4]=96,[5]=112,[9]=256})[upgrade]
local a,b,water=id(18,22),id((upgrade==4 or upgrade==5) and 22 or 21,22),id(19,22)
local rails=id(20,22)
local depot,west,east=id(9,21),id(12,22),id(29,22)
local phase=core.settings:get("luanttd_qa_bridge_phase")
local cap={road={start_year=1950,breakdowns=0,service_interval=0},ferry={},air={},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),durable_actions=true}
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local earlier=cp.read()
if phase=="start" then
  assert(not earlier)
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function()return 1 end)
  for i=1,64*64 do s.tiles[i]={h=1,variant=1,terrain="grass"} end
  s.tiles[water].terrain="water"
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.rail_paid_service,s.rail_owned_service=true,true
  for i,x in ipairs({12,29}) do
    s.sites[i]={id=i,kind="town",name="Bridge Town "..i,tile=id(x,24),
      population=520,stock={},produced={},received={},service=0}
    for y=23,25 do for j=x-2,x+2 do
      local t=s.tiles[id(j,y)]
      t.house=true;t.source_house={id=j%2==0 and 4 or 1,town=i,completed=true}
    end end
  end
  Sim.company(s,owner).cash=120000
  cp.write_state(s)
end
local co,revision,goal
local function resume(r)
  local ok,q=coroutine.resume(co,r);assert(ok,q)
  if q then assert(client.query(q,resume)) end
end
local function ask(kind,q)
  q=q or {};q.kind,q.player=kind,owner
  local r=assert(coroutine.yield(q))
  revision=r.revision or revision
  assert(r.ok,kind..": "..tostring(r.why))
  return r.value
end
local function commit(kind,q)
  q.kind,q.revision=kind,revision
  return ask("command",{command=q})
end
local function build(which,at)
  local request={tool=which,first=at}
  local quote=ask("road_quote",{request=request})
  commit("road_commit",{request=request,quote=quote,token=quote.token})
end
local function bridge(style,begin_,finish)
  local q=ask("bridge_picker",{mode="road",first=begin_ or a,last=finish or b})
  local offer
  for _,o in ipairs(q.offers) do if o.style==style then offer=o end end
  assert(offer,"Missing real picker bridge style "..style)
  commit("bridge_picker",{style=style,token=q.token})
  return offer.price
end
local function state()
  ask("checkpoint")
  return assert(cp.read())
end
local function run()
  if not earlier then
    -- Bulldoze a separate ordinary span by its overhead layer. The
    -- worker must display the actual fee and not touch the lower road.
    local x1,x2,lower=id(39,26),id(42,26),id(40,26)
    bridge(0,x1,x2)
    commit("road_build",{first=id(40,24),last=id(40,28)})
    local initial=state()
    local demo=ask("demolition",{tile=lower})
    local option
    for _,offer in ipairs(demo.options) do if offer.key=="road_bridge" then option=offer;break end end
    assert(option and option.ok and option.detail:find("$520",1,true))
    commit("demolition",{token=demo.token,layer=option.key})
    local removed=state()
    assert(removed.companies[owner].cash==initial.companies[owner].cash-520)
    assert(removed.tiles[lower].build=="road" and removed.tiles[lower].road_bits==initial.tiles[lower].road_bits)
    assert(not removed.bridge_above[lower] and not removed.tiles[x1].road_bridge_id)
    core.log("action","BRIDGE_BULLDOZER_NATIVE_PASS stock fee and existing road preserved")
    local rail=rails
    local track=ask("rail_quote",{request={tool="track",track=1,first=id(20,20),last=id(20,24)}})
    commit("rail_commit",{token=track.token})
    local old_rail=assert(state().tiles[rail].rail_tracks)
    bridge(0)
    assert(state().tiles[rail].rail_tracks==old_rail)
    commit("road_build",{first=id(8,22),last=a})
    commit("road_build",{first=b,last=id(32,22)})
    build("road_depot",depot);build("road_station",west);build("road_station",east)
    local disk=state()
    local panel=ask("depot",{mode="road",depot=depot})
    local bus
    for _,o in ipairs(panel.offers) do
      if o.request.cargo=="passenger" then bus=commit("road_buy",o.request);break end
    end
    assert(bus)
    for _,tile in ipairs({west,east}) do
      commit("road_order_add",{vehicle=bus,station=assert(disk.tiles[tile].station)})
    end
    commit("road_toggle",{vehicle=bus})
    local bridge_id=disk.tiles[a].road_bridge_id
    local v,sample
    for _=1,120 do
      ask("advance",{days=1})
      disk=state()
      v=disk.fleet[bus]
      sample=Sim.road_motion_frame(disk,v)
      if sample and sample[10]==bridge_id and (v.delivered or 0)==0 then break end
    end
    assert(sample and sample[10]==bridge_id and (v.delivered or 0)==0,"No real bus entered the timber span")
    assert(Speed.bridge_limit(disk,sample)==64)
    local before=disk.companies[owner].cash
    local price=bridge(upgrade)
    local after=state()
    local changed=after.stock_road_bridges[bridge_id]
    local same=after.fleet[bus]
    local remained=Sim.road_motion_frame(after,same)
    assert(Speed.bridge_limit(after,remained)==speed*2)
    assert(changed.bridge_type==upgrade and changed.spec.speed==speed and after.bridge_above[water]==bridge_id)
    assert(after.bridge_above[rail]==bridge_id and after.tiles[rail].rail_tracks==old_rail)
    assert(after.companies[owner].cash==before-price and remained[10]==bridge_id and remained[1]==sample[1] and remained[2]==sample[2])
    goal="BRIDGE_UPGRADE_NATIVE_SAVED occupied span retained its ID and live bus pose"
    return {kind="stop"}
  end
  local disk=state()
  local bridge_id=disk.tiles[a].road_bridge_id
  local _,v=next(disk.fleet)
  assert(v and v.running and #v.orders==2 and disk.stock_road_bridges[bridge_id].bridge_type==upgrade)
  assert(Sim.road_motion_frame(disk,v)[10]==bridge_id and disk.tiles[water].terrain=="water")
  assert(disk.tiles[rails].rail_tracks==2 and disk.bridge_above[rails]==bridge_id)
  for _=1,80 do
    ask("advance",{days=1})
    disk=state();v=disk.fleet[v.id]
    if (v.delivered or 0)>0 then
      goal=("BRIDGE_UPGRADE_NATIVE_PASS same bus and orders resumed across upgraded stock bridge, carrying %d passengers for $%d"):format(v.delivered,v.revenue)
      return {kind="stop"}
    end
  end
  error("Restored bridge service did not pay")
end
core.register_on_mods_loaded(function()
  co=coroutine.create(run)
  assert(client.start(cap,function(info) assert(info.ready);revision=info.revision;resume(info) end,
    function(why,_,_,detail)
      assert(why=="stopped" and goal,tostring(detail or why))
      core.log("action",goal);core.request_shutdown(goal,false,0)
    end,"luanttd-wide-campaign.chk"))
end)
