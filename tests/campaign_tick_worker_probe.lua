-- Native ownership proof for real road/town state, not an ordinary gameplay mount.
local mod=assert(core.get_modpath(core.get_current_modname()))
local channel="luanttd_core:real_tick_probe"
if not core.get_player_by_name then
  function core.luanttd_probe_campaign(phase,path)
    local Sim=dofile(mod.."/sim.lua")
    local Bind=dofile(mod.."/campaign_simulation_bindings.lua")(Sim,mod)
    local T=dofile(mod.."/openttd/terrain.lua")
    local H=dofile(mod.."/openttd/town_passengers.lua")
    local F=dofile(mod.."/town_growth_live_fixture.lua")
    local disk=dofile(mod.."/campaign_checkpoint.lua")(
      setmetatable({get_worldpath=function()return path end},{__index=core}),
      dofile(mod.."/packed_campaign.lua"),"worker-economy.chk")
    local function bind(s)
      Bind.road(s,{start_year=1950,foster=true,craighead=true,breakdowns=0,service_interval=150})
      Bind.flood(s);Bind.towns(s)
    end
    local s,qa
    if phase==1 then
      s=Sim.new(1751)
      dofile(mod.."/town_layout.lua")(Sim,s)
      s.corner_grid=dofile(mod.."/terrain_preview.lua")(Sim,T,s)
      bind(s)
      qa=F.first(Sim,s)
      core.ipc_set(channel..":status",{tick=qa.tick,day=s.day,fare=s.fleet[qa.id].revenue})
      -- Hold live state on this worker across independent engine steps.
      assert(core.ipc_poll(channel..":save",3000),"main did not request checkpoint")
      assert(core.ipc_get(channel..":save")==qa.tick,"checkpoint request does not match the current tick")
      s.authority_native_fixture=qa
      disk.write_state(s)
      return qa.tick
    end
    s=assert(disk.read())
    qa=assert(s.authority_native_fixture)
    Sim.restore_road_orders(s)
    bind(s)
    local h=F.second(Sim,s,qa,H.specs)
    return qa.tick,h.completed_tick,h.first_cargo_tick,s.fleet[qa.id].revenue
  end
  return
end

core.register_async_dofile(mod.."/init.lua")
for _,group in ipairs({"stone","water_source","river_water_source"}) do
  core.register_alias("mapgen_"..group,"air")
end
local function job(phase,path) return core.luanttd_probe_campaign(phase,path) end
local steps=0
core.register_globalstep(function() steps=steps+1 end)
core.register_on_mods_loaded(function()
  local path=core.get_worldpath()
  local observed
  assert(core.handle_async(job,function(tick)
    assert(observed and tick==observed.tick and observed.fare>0)
    assert(core.handle_async(job,function(saved,complete,production,fare)
      assert(tick==saved and complete==5115 and production>complete and fare>=observed.fare)
      core.log("action",("PASS NATIVE WORKER CAMPAIGN: bus $%d; live checkpoint tick %d; house completed %d, produced cargo %d; no world returned"):format(fare,tick,complete,production))
      core.request_shutdown("Worker campaign checks passed",false,0)
    end,2,path))
  end,1,path))
  local limit=core.get_us_time()+5000000
  local function poll()
    local data=core.ipc_get(channel..":status")
    if data then
      assert(data.fare>0 and data.tick==74*data.day)
      observed=data
      local before=steps
      core.after(.25,function()
        assert(steps>before,"simulation worker stopped the engine")
        core.ipc_set(channel..":save",data.tick)
      end)
    else
      assert(core.get_us_time()<limit,"worker did not report paid service")
      core.after(.03,poll)
    end
  end
  core.after(.03,poll)
end)
