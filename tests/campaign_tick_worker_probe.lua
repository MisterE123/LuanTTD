-- Native ownership proof for real road/town state, not an ordinary gameplay mount.
local mod=assert(core.get_modpath(core.get_current_modname()))
local channel="luanttd_core:real_tick_probe"
if not core.get_player_by_name then
  function core.luanttd_probe_campaign(phase,path)
    if phase==3 then
      assert(dofile(mod.."/campaign_transport_commands_fixture.lua"))
      return assert(loadfile(mod.."/rail_paid_runtime_fixture.lua"))({"authority"})
    end
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
    if phase==1 or phase==4 then
      s=Sim.new(1751)
      dofile(mod.."/town_layout.lua")(Sim,s)
      s.corner_grid=dofile(mod.."/terrain_preview.lua")(Sim,T,s)
      bind(s)
      qa=F.first(Sim,s)
      if phase==4 then
        -- Verify the reopened async result against the same fixture run
        -- continuously, rather than a pre-town-art absolute tick number.
        local h=F.second(Sim,s,qa,H.specs)
        return qa.tick,h.completed_tick,h.first_cargo_tick,s.fleet[qa.id].revenue
      end
      local endpoint=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,
        {world=s,terrain=T,day=function() Sim.daily(s) end})
      core.ipc_set(channel..":status",{tick=qa.tick,day=s.day,fare=s.fleet[qa.id].revenue})
      -- Keep the live world private while the host requests its visible area.
      assert(core.ipc_poll(channel..":view",3000),"main did not request viewport")
      local request=core.ipc_get(channel..":view")
      local view=endpoint.snapshot(request.x,request.z,request.w,request.h)
      core.ipc_set(channel..":projection",view)
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
local client=dofile(mod.."/campaign_authority_client.lua")(core,mod)
-- The real vehicle formspec consumes the same worker mailbox as the probe.
-- Only nearby actor identity is mirrored, never a route or company state.
local host_view={fleet={},tiles={}}
local host_player={get_player_name=function() return "GrowthQA" end}
local original_receive=core.register_on_player_receive_fields
local ui_fields
core.register_on_player_receive_fields=function(f) ui_fields=f;original_receive(f) end
local vehicle_ui=dofile(mod.."/vehicle_ui.lua")({s=host_view,Sim={},
  save=function() error("The worker order formspec must not save the main thread's view.") end})
core.register_on_player_receive_fields=original_receive
local route_proxy=dofile(mod.."/campaign_authority_order_proxy.lua")(client,"road")
vehicle_ui.orders.road=route_proxy
local caps={road={start_year=1950,foster=true,craighead=true,breakdowns=0,service_interval=150}}
local steps=0
local function owner_run(base_day)
  local sequence=0
  local function ask(request,callback)
    sequence=sequence+1
    local wanted=sequence
    assert(client.query(request,function(r)
      assert(r.seq==wanted)
      callback(r)
    end))
  end
  local function advance()
    ask({kind="advance",days=1},function(r)
      assert(r.ok and r.day==base_day+1 and r.revision==3)
      -- Stop is acknowledged only by the end-of-job callback, after disk.
      ask({kind="stop"},function() error("Stop reply must be durable on job completion.") end)
    end)
  end
  assert(client.start(caps,function(ready)
    assert(ready.ready and ready.day==base_day and ready.revision==0)
    ask({kind="snapshot",x=9,z=8,w=16,h=12},function(view)
      assert(view.ok and #view.value.tiles==192 and #view.value.vehicles==1)
      local id=view.value.vehicles[1].id
      local station
      for _,tile in ipairs(view.value.tiles) do if tile.station then station=tile.station;break end end
      assert(station and view.value.vehicles[1].order_count==2)
      local stop={kind="road_toggle",vehicle=id,revision=0}
      ask({kind="command",player="Stranger",command=stop},function(denied)
        assert(denied.why=="NOT_YOUR_ROAD_VEHICLE" and denied.revision==0)
        ask({kind="command",player="GrowthQA",command=stop},function(accepted)
          assert(accepted.ok and accepted.revision==1)
          ask({kind="command",player="GrowthQA",command=stop},function(stale)
            assert(stale.why=="STALE_COMMAND" and stale.revision==1)
            ask({kind="command",player="GrowthQA",command={kind="road_toggle",vehicle=id,revision=1}},function(resumed)
              assert(resumed.ok and resumed.revision==2)
              local actor
              for _,row in ipairs(view.value.actors) do if row.mode=="road" and row.id==id then actor=row end end
              assert(actor and actor.owner=="GrowthQA")
              host_view.fleet[id]={id=id,owner=actor.owner,name=actor.label,home_depot=actor.home_depot}
              local show=core.show_formspec
              local form,markup
              core.show_formspec=function(_,key,body) form,markup=key,body end
              assert(vehicle_ui.open(host_player,"road",id) and markup:find("Loading vehicle orders",1,true))
              sequence=sequence+1 -- formspec read
              local function wait_cargo()
                local append=markup:match("(v%d+_append);")
                if not append then core.after(.03,wait_cargo);return end
                assert(markup:find("Available destinations",1,true))
                assert(ui_fields(host_player,form,{[append]=true}))
                sequence=sequence+2 -- accepted edit plus automatic refresh
                local function outcome()
                  if not markup:find("Added ",1,true) then core.after(.03,outcome);return end
                  core.show_formspec=show
                  core.log("action","PASS NATIVE WORKER FORMSPEC: existing vehicle panel adds a real worker-owned route order")
                  advance()
                end
                core.after(.03,outcome)
              end
              core.after(.03,wait_cargo)
            end)
          end)
        end)
      end)
    end)
  end,function(why,seq,day)
    assert(why=="stopped" and seq==sequence and day==base_day+1)
    assert(client.start(caps,function(ready)
      assert(ready.ready and ready.day==day and ready.revision==3)
      assert(client.query({kind="snapshot",x=9,z=8,w=16,h=12},function(view)
        assert(view.ok and view.value.vehicles[1].order_count==3)
        assert(client.query({kind="stop"},function() end))
      end))
    end,function(why2,seq2,day2)
      assert(why2=="stopped" and seq2==2 and day2==day)
      core.log("action","PASS NATIVE OWNER MAILBOX: snapshot, real stop/resume/order, stale edit refused, authoritative day and revision reopened")
      caps.autoplay,caps.seconds_per_day=true,.15
      assert(client.start(caps,function(ready)
        assert(ready.ready and ready.day==day2)
        -- The host sends no Advance commands or viewport during this time.
        local before=steps
        core.after(.75,function()
          assert(steps>before)
          assert(client.query({kind="clock"},function(value)
            assert(value.ok and value.day>=day2+2 and value.tick==74*value.day)
            assert(client.query({kind="stop"},function() end))
          end))
        end)
      end,function(reason,seq3,end_day)
        assert(reason=="stopped" and seq3==2 and end_day>day2)
        core.log("action","PASS NATIVE AUTONOMOUS ECONOMY: worker advances stock days independently of main loop and viewport")
        core.request_shutdown("Worker campaign checks passed",false,0)
      end,"worker-economy.chk"))
    end,"worker-economy.chk"))
  end,"worker-economy.chk"))
end
for _,group in ipairs({"stone","water_source","river_water_source"}) do
  core.register_alias("mapgen_"..group,"air")
end
local function job(phase,path) return core.luanttd_probe_campaign(phase,path) end
core.register_globalstep(function() steps=steps+1 end)
core.register_on_mods_loaded(function()
  local path=core.get_worldpath()
  local observed
  assert(core.handle_async(job,function(tick)
    assert(observed and tick==observed.tick and observed.fare>0)
    assert(core.handle_async(job,function(saved,complete,production,fare)
      assert(core.handle_async(job,function(ref,ref_complete,ref_production,ref_fare)
        assert(tick==saved and saved==ref and complete==ref_complete and production==ref_production
          and fare==ref_fare and production>complete and fare>=observed.fare,
          ("Checkpoint diverged from continuous simulation: saved %s / %s / %s / %s, native %s / %s / %s / %s")
            :format(saved,complete,production,fare,ref,ref_complete,ref_production,ref_fare))
        core.log("action",("PASS NATIVE WORKER CAMPAIGN: bus $%d; checkpoint tick %d; house completed %d, produced cargo %d, identical across reload"):format(fare,tick,complete,production))
        assert(core.handle_async(job,function(fares)
          assert(fares.Coach>0 and fares.Rail>0 and fares.Ferry>0 and fares.Air>0)
          core.log("action",("PASS NATIVE FOUR-MODE ECONOMY: road $%d, rail $%d, ferry $%d, air $%d; one clock through reload")
            :format(fares.Coach,fares.Rail,fares.Ferry,fares.Air))
          owner_run(observed.day)
        end,3,path))
      end,4,path))
    end,2,path))
  end,1,path))
  local limit=core.get_us_time()+5000000
  local function poll()
    local data=core.ipc_get(channel..":status")
    if data then
      assert(data.fare>0 and data.tick==74*data.day)
      observed=data
      local before=steps
      core.ipc_set(channel..":view",{x=9,z=8,w=16,h=12})
      local function projected()
        local view=core.ipc_get(channel..":projection")
        if view then
          assert(steps>before,"simulation worker stopped the engine")
          assert(view.ok and view.tick==data.tick and #view.value.tiles==192 and #view.value.vehicles==1)
          assert(view.value.vehicles[1].running and not view.value.fleet and not view.value.corner_grid)
          core.ipc_set(channel..":save",data.tick)
        else
          assert(core.get_us_time()<limit,"worker did not project the viewport")
          core.after(.03,projected)
        end
      end
      core.after(.09,projected)
    else
      assert(core.get_us_time()<limit,"worker did not report paid service")
      core.after(.03,poll)
    end
  end
  core.after(.03,poll)
end)
