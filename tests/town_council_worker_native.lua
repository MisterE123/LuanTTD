-- A controlled treasury and RNG in a disposable real Luanti worker.
-- The normal Local Authority commands own all subsequent mutations.
for _,alias in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..alias,"air") end
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local S,T,G=m("sim"),m("openttd/terrain"),m("openttd/town_growth")
local file="council-native.chk"
local buyer,rival="Buyer","Rival"
local disk=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local previous=disk.read()
if not previous then
  S.W,S.H=64,64
  local s=S.new(1751)
  for id in ipairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=1} end
  s.corner_grid=T.new(64,64,function()return 1 end)
  s.stock_generated_profile={width=64,depth=64,map_height_limit=30,town_settings={growth_setting=0}}
  S.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),1950)
  s.day=10
  s.passenger_house_clock=m("openttd/town_passengers").new_clock(6,6,nil,s.day*74)
  s.passenger_rating_rng={8,1} -- next Chance16 word is zero
  s.sites={{id=1,kind="town",name="Westbridge",tile=S.id(18,20),population=0,stock={},produced={},received={}}}
  s.stock_town_growth={version=1,order={1},towns={[1]=G.new(1,18,20,{layout="original"})}}
  for _,who in ipairs({buyer,rival}) do S.company(s,who).cash=1500000 end
  disk.write_state(s)
end
local client=m("campaign_authority_client")(core,mod)
local co,result
local function step(r)
  local ok,q=coroutine.resume(co,r)
  assert(ok,q)
  if q then assert(client.query(q,step)) end
end
local function ask(q)
  local r=assert(coroutine.yield(q))
  assert(r.ok,r.why)
  return r
end
local function inspect(who)
  return ask({kind="town_authority",player=who,town=1})
end
local function buy(who,i)
  local v=inspect(who)
  local q=v.value.council.offers[i]
  assert(q.affordable)
  return ask({kind="command",player=who,command={kind="town_council_campaign",action=q.key,town=1,
    cost=q.cost,revision=v.revision}}).value
end
local function work()
  if not previous then
    local a=buy(buyer,1)
    assert(a.cost==457031 and a.holder==buyer and a.months==12 and a.accepted)
    local b=buy(rival,2)
    assert(b.cost==683593 and not b.accepted and b.rating==-50 and b.unwanted==6)
    local blocked=inspect(rival).value
    assert(not blocked.funding and not blocked.reconstruction and not blocked.statue and not blocked.advertising)
    result="SERVICE signed failure and 12-month rights"
  else
    local v=inspect(rival).value
    assert(v.rating==-50 and v.council.holder==buyer and v.council.months==12 and v.council.unwanted==6)
    for _=1,8 do ask({kind="advance",days=4}) end
    local q=inspect(rival).value.council
    assert(q.holder==buyer and q.months==11 and q.unwanted==5)
    result="REOPEN signed failure persists and both monthly timers advance"
  end
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  co=coroutine.create(work)
  assert(client.start({autoplay=false,durable_actions=true,road={start_year=1950,breakdowns=0,service_interval=0},oil_tanker=true},
    function(r) assert(r.ready);step(r) end,
    function(why,_,_,detail)
      assert(why=="stopped" and result,detail or why)
      core.log("action","PASS NATIVE COUNCIL "..result)
      core.request_shutdown("Stock council behavior verified",false,0)
    end,file))
end)
