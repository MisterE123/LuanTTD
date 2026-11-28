-- Run the ordinary paid Found Town command on the actual Luanti worker,
-- close SQLite immediately after founding, then continue a stock year.
local mod=core.get_modpath(core.get_current_modname())
local function m(n)return dofile(mod.."/"..n..".lua")end
local Sim=m("sim")
local ref=m("qa_native_goods")
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true,durable_actions=true}
local file="luanttd-wide-campaign.chk"
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local owner="Builder"
local initial=Checkpoint.read()
for _,k in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..k,"air") end
if not initial then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,
    trees=2,towns=4,custom_towns=4,larger_towns=3,industries=0,variety=0,smooth=1,layout="original",growth_rate=2,found_town=2,
  })
  m("campaign_authority_runtime")(Sim,mod,s,cap)
  s.stock_economy_subsidies.duration=0
  assert(Sim.open_company(s,owner))
  s.companies[owner].cash=80000000
  Checkpoint.write_state(s)
end
local thread,proof
local client=m("campaign_authority_client")(core,mod)
local function resume(reply)
  local ok,req=coroutine.resume(thread,reply)
  assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(req)
  req.player=owner
  local reply=assert(coroutine.yield(req))
  assert(reply.ok,reply.why)
  return reply
end
local function state(tick)
  local s=assert(Checkpoint.read())
  local t=assert(s.stock_town_growth.towns[5])
  local expected=ref[tick]
  assert(s.sites[5].name=="Rivermark" and t.stock_id==4)
  assert(s.passenger_house_clock.counter==tick and s.passenger_house_clock.head==expected[1][1])
  assert(s.passenger_rating_rng[1]==expected[1][2] and s.passenger_rating_rng[2]==expected[1][3])
  assert(t.grow_counter==expected[6][4] and t.growth_rate==expected[6][5])
  return s
end
local function run()
  if not initial then
    local r={tile=8133,size="medium",city=true,layout="random",name="Rivermark",nameparts=0xC0FFEE}
    local q=ask({kind="town_found_quote",request=r})
    assert(q.value.cost==26250000 and q.value.affordable)
    local found=ask({kind="command",command={kind="town_found",request=r,cost=q.value.cost,revision=q.revision}})
    assert(found.value.id==5 and found.value.population==804)
    local s=state(1280) -- verifies durable command before receipt
    assert(s.companies[owner].cash==53750000)
    local stories=ask({kind="news",page=1})
    local function found_story(node)
      if type(node)~="table" then return false end
      if node.headline=="Rivermark founded" then return true end
      for _,value in pairs(node) do if found_story(value) then return true end end
      return false
    end
    assert(found_story(stories.value))
    proof="ORDINARY_GOODS_SAVED: stock command founded Rivermark at the quoted price, durable immediately"
  else
    assert(initial.day==0 and initial.sites[5].name=="Rivermark")
    for _=1,91 do ask({kind="advance",days=4}) end
    ask({kind="advance",days=1})
    ask({kind="checkpoint"})
    state(28290)
    proof="ORDINARY_GOODS_PASS: exact RC1 year-end growth and RNG after restarting the founded city"
  end
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(run)
  assert(client.start(cap,function(ready)
    assert(ready.ready)
    resume(ready)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,detail or reason)
    core.log("action",proof)
    core.request_shutdown("Stock Found Town verified",false,0)
  end,file))
end)
