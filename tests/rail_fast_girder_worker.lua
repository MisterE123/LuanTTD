-- Run the ordinary worker's inspector, track, picker, depot and order API
-- in a disposable SQLite world, without commands in the player UI.
local mod=core.get_modpath(core.get_current_modname())
local function m(p)return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local C=m("campaign_authority_client")(core,mod)
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local owner="Bridge Railway"
local phase=core.settings:get("luanttd_qa_bridge_phase")
local function id(x,z)return (z-1)*64+x end
local upgrade=tonumber(core.settings:get("luanttd_qa_bridge_style")) or 9
local bridge_specs=m("openttd/road_bridge")(m("openttd/slope")).catalog
local spec=assert(bridge_specs[upgrade])
local speed=spec.speed
local a,b,depot=id(21,27),id(22+math.max(2,spec.min_length),27),id(8,27)
local west,east=id(13,27),id(32,27)
local cap={road={start_year=1950,breakdowns=0,service_interval=0},ferry={},air={},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),durable_actions=true}
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local previous=cp.read()
if phase=="start" then
  assert(not previous)
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function()return 1 end)
  for i=1,4096 do s.tiles[i]={h=1,variant=1,terrain="grass"} end
  s.tiles[id(22,27)].terrain="water"
  s.rail_paid_service,s.rail_owned_service=true,true
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  for i,x in ipairs({13,32}) do
    s.sites[i]={id=i,kind="town",name="Steel Town "..i,tile=id(x,29),population=520,
      stock={},produced={},received={},service=0}
    for z=28,30 do for col=x-2,x+2 do
      local t=s.tiles[id(col,z)]
      t.house=true;t.source_house={id=col%2==0 and 4 or 1,town=i,completed=true}
    end end
  end
  Sim.company(s,owner).cash=150000
  cp.write_state(s)
end
local routine,revision,goal
local function resume(r)
  local ok,q=coroutine.resume(routine,r);assert(ok,q)
  if q then assert(C.query(q,resume)) end
end
local function ask(kind,q)
  q=q or {};q.kind,q.player=kind,owner
  local r=assert(coroutine.yield(q))
  revision=r.revision or revision
  assert(r.ok,kind..": "..tostring(r.why))
  return r.value
end
local function commit(kind,fields)
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields})
end
local function build(request)
  local quote=ask("rail_quote",{request=request})
  commit("rail_commit",{token=quote.token})
end
local function chosen(style)
  local quote=ask("bridge_picker",{mode="rail",first=a,last=b})
  for _,o in ipairs(quote.offers) do
    if o.style==style then
      assert(o.speed==(style==upgrade and speed or 32))
      commit("bridge_picker",{style=style,token=quote.token})
      return o.price
    end
  end
  error("Missing bridge offer "..style)
end
local function state()
  ask("checkpoint")
  return assert(cp.read())
end
local function run()
  if not previous then
    chosen(0)
    build{tool="track",track=0,first=id(9,27),last=id(20,27)}
    build{tool="track",track=0,first=b+1,last=id(37,27)}
    build{tool="depot",first=depot,direction=2}
    for _,at in ipairs{west,east} do
      build{tool="station",first=at,last=at+2,axis=0,length=3,tracks=1,separate=true,drag=true}
    end
    local purchase=ask("transport_quote",{request={mode="rail",operation="buy",depot=depot,parts={0,27}}})
    local v=commit("transport_commit",{token=purchase.token})
    commit("transport_start",{mode="rail",vehicle=v.id,first=1,second=2})
    for _=1,200 do
      ask("advance",{days=1})
      local s=state()
      local dispatch=s.stock_rail_dispatch
      local train=dispatch and dispatch.runs[1]
      local active=train and train.consist.parts[1]
      if active and active.wormhole and active.tile==a then
        local key=s.tiles[a].rail_span_id
        local oldfrom,oldto=dispatch.life.claims[a],dispatch.life.claims[b]
        assert(oldfrom and oldto and oldfrom[0]==oldto[0])
        local quote=chosen(upgrade)
        local next_=state()
        local changed=next_.stock_rail_spans[key]
        local newd=next_.stock_rail_dispatch
        local fresh=newd.runs[1].consist.parts[1]
        assert(changed.bridge_type==upgrade and next_.rail_bridge_above[id(22,27)]==key)
        assert(next_.companies[owner].cash==s.companies[owner].cash-quote)
        assert(newd.life.claims[a][0]==oldfrom[0] and newd.life.claims[b][0]==oldto[0])
        assert(fresh.pose.x==active.pose.x and fresh.pose.y==active.pose.y and fresh.wormhole)
        goal="FAST_GIRDER_RAIL_SAVED train and both live reservations retained over replacement"
        return {kind="stop"}
      end
    end
    error("Train never used the bridge")
  end
  for _=1,180 do
    local s=state()
    local bridge=s.stock_rail_spans[s.tiles[a].rail_span_id]
    assert(bridge.bridge_type==upgrade and bridge.head.bridge_speed==speed and s.tiles[id(22,27)].terrain=="water")
    local c=assert(s.companies[owner])
    if c.paid_units>0 and c.revenue>0 then
      goal=("FAST_GIRDER_RAIL_NATIVE_PASS delivered %d paying units for $%d after reopening"):format(c.paid_units,c.revenue)
      return {kind="stop"}
    end
    ask("advance",{days=1})
  end
  error("Train did not resume paid service")
end
core.register_on_mods_loaded(function()
  routine=coroutine.create(run)
  assert(C.start(cap,function(info) assert(info.ready);revision=info.revision;resume(info) end,
    function(why,_,_,detail)
      assert(why=="stopped" and goal,tostring(detail or why))
      core.log("action",goal);core.request_shutdown(goal,false,0)
    end,"luanttd-wide-campaign.chk"))
end)
