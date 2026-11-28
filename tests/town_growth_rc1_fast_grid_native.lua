-- Real Luanti async authority, with a process restart on a 256x128 map.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
local ref=m("qa_native_goods")
local depth=ref.hills and 256 or 128
local industry_count=#ref.industries
local town_count=#ref.snapshots[1281]-1
for _,kind in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..kind,"air") end
local initial=Checkpoint.read()
if not initial then
  local gen=m("campaign_generation")(core,mod,Sim,m("world_setup"))
  local cfg=ref.hills and {seed=1,relief=3,coast=0,rivers=3,towns=3,larger_towns=4,layout="original",growth_rate=2}
    or {seed=98217,relief=1,coast=16,rivers=2,towns=4,custom_towns=6,larger_towns=3,layout="grid3",growth_rate=3}
  cfg.width,cfg.depth,cfg.year,cfg.sea,cfg.trees,cfg.industries,cfg.variety,cfg.smooth=256,depth,1950,0,2,4,0,1
  local s=gen.run(cfg)
  assert(#s.stock_generated_profile.industries==industry_count and #s.stock_town_growth.towns==town_count)
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  Checkpoint.write_state(s)
end
local thread,proof
local function resume(reply)
  local ok,next_query=coroutine.resume(thread,reply)
  assert(ok,next_query)
  if next_query then assert(client.query(next_query,resume)) end
end
local function ask(kind,days)
  local reply=assert(coroutine.yield({kind=kind,days=days,player="Native Grid QA"}))
  assert(reply.ok,reply.why)
end
local function run()
  if not initial then
    for _=1,32 do ask("advance",4) end
    ask("checkpoint")
    local s=assert(Checkpoint.read())
    assert(s.day==128 and #s.stock_generated_profile.industries==industry_count)
    proof=("ORDINARY_GOODS_SAVED: 256x%d region at day 128, %d industries"):format(depth,industry_count)
  else
    assert(initial.day==128)
    for _=1,59 do ask("advance",4) end
    ask("advance",1)
    ask("checkpoint")
    local s=assert(Checkpoint.read())
    local final=ref.snapshots[28290]
    assert(s.day==365 and s.passenger_house_clock.counter==28290 and s.passenger_house_clock.head==final[1][1])
    assert(s.passenger_rating_rng[1]==final[1][2] and s.passenger_rating_rng[2]==final[1][3])
    for i,t in ipairs(s.stock_town_growth.towns) do
      local row=final[i+1]
      assert(t.grow_counter==row[4] and t.growth_rate==row[5] and t.time_until_rebuild==row[6])
    end
    assert(#s.stock_town_growth.towns==town_count)
    proof=("ORDINARY_GOODS_PASS: all %d town clocks and exact RC1 final RNG after SQLite restart"):format(town_count)
  end
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(run)
  assert(client.start(cap,function(reply)
    assert(reply.ready)
    resume(reply)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,tostring(detail or reason))
    core.log("action",proof)
    core.request_shutdown("Fast-grid region QA complete",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
