-- Two real Luanti authority-worker processes. Commands and cargo are
-- ordinary paid gameplay, not an imported stock save or seeded packets.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local owner="Stock Ferry QA"
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local previous=Checkpoint.read()
local client=m("campaign_authority_client")(core,mod)
local files={}
for _,kind in ipairs({"models","textures"}) do
  for _,name in ipairs(core.get_dir_list(mod.."/"..kind,false)) do files[name]=true end
end
local cap={road={start_year=1985,breakdowns=1,service_interval=150,foster=true},ferry={},air={},
  oil_tanker=true,durable_actions=true}
cap.ferry[207]=files["bl_ffp_passenger_ferry.obj"] and files["bl_harbor_ferry_palette.png"]
assert(cap.ferry[207])
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
if not previous then
  local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
    width=256,depth=256,year=1985,seed=1751,relief=0,sea=0,coast=0,rivers=2,trees=2,
    towns=3,larger_towns=4,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
  })
  s.ship_paid_service=true
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  Checkpoint.write_state(s)
end
local co,revision,result
local function resumed(r)
  local ok,req=coroutine.resume(co,r)
  assert(ok,req)
  if req then assert(client.query(req,resumed)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,owner
  local r=assert(coroutine.yield(fields))
  assert(r.ok,r.why)
  revision=r.revision or revision
  return r.value
end
local function command(kind,fields)
  fields=fields or {}
  fields.kind,fields.revision=kind,revision
  return ask("command",{command=fields})
end
local function transport(req)
  local q=ask("transport_quote",{request=req})
  return command("transport_commit",{token=q.token})
end
local function counts()
  ask("checkpoint")
  local s=assert(Checkpoint.read())
  local p=assert(s.ship_pilot)
  local unit=assert(s.stock_owned_ferry)
  assert(p.phase~="blocked" and p.owned and unit.stock_pool_id==12,p.failure)
  local c=assert(s.companies[owner])
  local hull=assert(s.stock_ship_commercial.service.vehicles[p.paid_clock])
  return s,p,hull.boarded or 0,c.revenue or 0
end
local function work()
  local first=previous and previous.companies[owner]
  if not first then
    ask("advance",{days=4})
    command("company_open")
    local da=transport({mode="ship",operation="build",kind="dock",tile=29757,separate=true})
    local db=transport({mode="ship",operation="build",kind="dock",tile=31026,separate=true})
    local dp=transport({mode="ship",operation="build",kind="depot",tile=29760,axis=0})
    assert(transport({mode="ship",operation="buy",depot=dp.id,engine=207}).id=="ferry")
    command("transport_start",{mode="ship",vehicle="ferry",depot=dp.id,first=da.id,second=db.id})
  end
  local prior_ferry=first and previous.stock_ship_commercial.service.vehicles[previous.ship_pilot.paid_clock]
  local baseline_boarded,baseline_money=prior_ferry and prior_ferry.boarded or 0,first and first.revenue or 0
  local baseline_tick=previous and previous.passenger_house_clock.counter or 0
  if first then
    local s,p,boarded,money=counts()
    assert(s.passenger_house_clock.counter==baseline_tick and boarded==baseline_boarded and money==baseline_money)
    assert(p.arrivals==previous.ship_pilot.arrivals)
  end
  for _=1,22 do
    ask("advance",{days=4})
    local state,p,boarded,revenue=counts()
    if boarded>baseline_boarded then
      assert(state.stock_owned_ferry.stock_fault.reliability<65535 and p.arrivals>=2 and revenue==0)
      result=("NATIVE RC1 FERRY %s: %d boarded, VehicleID %d, elapsed tick %d"):format(
        first and "REOPEN" or "SERVICE",boarded,state.stock_owned_ferry.stock_pool_id,state.passenger_house_clock.counter)
      return {kind="stop"}
    end
  end
  error("No ordinary ferry boarding")
end
core.register_on_mods_loaded(function()
  co=coroutine.create(work)
  assert(client.start(cap,function(start)
    assert(start.ready);revision=start.revision;resumed(start)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and result,tostring(detail or reason))
    core.log("action",result)
    core.request_shutdown("Stock ferry worker verified",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
