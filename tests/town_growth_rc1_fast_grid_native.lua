-- Real Luanti async authority, with a process restart on a 256x128 map.
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local Sim=m("sim")
local Checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local client=m("campaign_authority_client")(core,mod)
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
local ref=m("qa_native_goods")
local width=ref.midyear and 128 or 256
local depth=ref.hills and 256 or 128
local industry_count=#ref.industries
local town_count=#ref.snapshots[1281]-1
local restart_day=ref.restart_day or 128
local final_day,final_tick=ref.days or 365,ref.final_tick or 28290
for _,kind in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..kind,"air") end
local initial=Checkpoint.read()
if not initial then
  local gen=m("campaign_generation")(core,mod,Sim,m("world_setup"))
  local cfg=ref.hills and {seed=1,relief=3,coast=0,rivers=3,towns=3,larger_towns=4,layout="original",growth_rate=2}
    or {seed=98217,relief=1,coast=16,rivers=2,towns=4,custom_towns=6,larger_towns=3,layout="grid3",growth_rate=3}
  if ref.midyear then cfg={seed=1751,relief=1,coast=16,rivers=2,towns=4,custom_towns=4,larger_towns=3,layout="original",growth_rate=2} end
  cfg.width,cfg.depth,cfg.year,cfg.sea,cfg.trees,cfg.industries,cfg.variety,cfg.smooth=width,depth,1950,0,2,4,0,1
  local s=gen.run(cfg)
  assert(#s.stock_generated_profile.industries==industry_count and #s.stock_town_growth.towns==town_count)
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  Checkpoint.write_state(s)
end
local thread,proof,revision
local function resume(reply)
  local ok,next_query=coroutine.resume(thread,reply)
  assert(ok,next_query)
  if next_query then assert(client.query(next_query,resume)) end
end
local function ask(kind,days,command)
  local reply=assert(coroutine.yield({kind=kind,days=days,player="Native Grid QA",command=command}))
  assert(reply.ok,reply.why)
  revision=reply.revision or revision
end
local function advance(days)
  for _=1,math.floor(days/4) do ask("advance",4) end
  if days%4~=0 then ask("advance",days%4) end
end
local function rate(n)
  ask("command",nil,{kind="town_growth_setting",rate=n,revision=revision,admin=true})
end
local function run()
  if not initial then
    if ref.midyear then
      advance(42)
      rate(0)
      advance(86)
    else advance(restart_day) end
    ask("checkpoint")
    local s=assert(Checkpoint.read())
    assert(s.day==restart_day and #s.stock_generated_profile.industries==industry_count)
    if ref.midyear then assert(s.stock_generated_profile.town_settings.growth_setting==0) end
    proof=("ORDINARY_GOODS_SAVED: %dx%d region at day %d, %d industries"):format(width,depth,restart_day,industry_count)
  else
    assert(initial.day==restart_day)
    if ref.midyear then
      assert(initial.stock_generated_profile.town_settings.growth_setting==0)
      advance(3)
      rate(4)
      advance(234)
    else advance(final_day-restart_day) end
    ask("checkpoint")
    local s=assert(Checkpoint.read())
    local final=ref.snapshots[final_tick]
    assert(s.day==final_day and s.passenger_house_clock.counter==final_tick and s.passenger_house_clock.head==final[1][1])
    assert(s.passenger_rating_rng[1]==final[1][2] and s.passenger_rating_rng[2]==final[1][3])
    for i,t in ipairs(s.stock_town_growth.towns) do
      local row=final[i+1]
      assert(t.grow_counter==row[4] and t.growth_rate==row[5] and t.time_until_rebuild==row[6])
    end
    assert(#s.stock_town_growth.towns==town_count)
    if ref.midyear then assert(s.stock_generated_profile.town_settings.growth_setting==4) end
    local last=ref.year_end_house
    if last then
      local house=assert(s.tiles[last.tile+1].source_house)
      assert(house.id==last.id and house.random_bits==last.random_bits and house.built_tick==last.tick)
    end
    proof=("ORDINARY_GOODS_PASS: all %d town clocks and exact RC1 final RNG after SQLite restart"):format(town_count)
  end
  return {kind="stop"}
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(run)
  assert(client.start(cap,function(reply)
    assert(reply.ready)
    revision=reply.revision
    resume(reply)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and proof,tostring(detail or reason))
    core.log("action",proof)
    core.request_shutdown("Fast-grid region QA complete",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
