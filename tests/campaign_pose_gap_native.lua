-- Wall time across the real host/worker mailbox, including periodic saves.
local mod=core.get_modpath("luanttd_core")
for _,alias in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..alias,"air") end
local client=dofile(mod.."/campaign_authority_client.lua")(core,mod)
local projection=dofile(mod.."/campaign_authority_projection.lua")()
local playout=dofile(mod.."/campaign_actor_buffer.lua")()
core.after(0,function()
  local F=dofile(mod.."/road_fleet_perf.lua")(mod)
  local s=F.make(24,8,function(sim,world)
    world.road_stock_house_supply=true
    sim.mount_road_bus_market(world,dofile(mod.."/openttd/stock_engine_calendar.lua"),1950)
  end,function(i) return i%2==0 and "leopard_bus" or "bus" end)
  s.speed=4
  local store=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"))
  store.write_state(s);collectgarbage("collect")
  local subscribed,done,prev,prev_worker,last,vehicle
  local gaps,worker_gaps,batch_delays={}, {}, {}
  local updated,draws=0,0
  local start
  local function change(view)
    local at=view.actor_clock()
    if not at or at==prev_worker then return end
    local now=core.get_us_time()
    if prev and now-start>1e6 then
      gaps[#gaps+1]=(now-prev)/1000
      worker_gaps[#worker_gaps+1]=(at-prev_worker)/1000
      batch_delays[#batch_delays+1]=(now-at)/1000
    end
    prev,prev_worker=now,at
    local actors=view.actors()
    if not vehicle then
      for key,a in pairs(actors) do if a.pos and a.mode=="road" and a.tile then vehicle=key;break end end
    end
    playout.observe(actors,at)
  end
  local I=dofile(mod.."/campaign_authority_interest.lua")(client,projection,128,128,change)
  assert(client.start({autoplay=true,seconds_per_day=1.25,road={start_year=1950,service_interval=0,breakdowns=0}},function(r)
    assert(r.ready);start=core.get_us_time()
    I.update({{name="Fleet Company 0",x=121,z=99}})
    subscribed=true
  end,function(why,seq,day,detail)
    assert(done and why=="stopped",tostring(detail or why))
    core.request_shutdown("Live gap benchmark complete",false,0)
  end))
  core.register_globalstep(function(dt)
    if not subscribed or done then return end
    local now=core.get_us_time()
    I.step(dt,0)
    local q=vehicle and playout.sample(now)[vehicle]
    if q and q.pos and now-start>1e6 then
      draws=draws+1
      if last and (q.pos.x~=last.x or q.pos.z~=last.z) then updated=updated+1 end
      last=q.pos
    end
    if now-start>=14e6 then
      assert(#gaps>60 and draws>60 and updated>0)
      local function stats(name,g)
        table.sort(g)
        core.log("action",("LIVE GAP %s samples=%d p50=%.2f p95=%.2f p99=%.2f max=%.2f"):format(
          name,#g,g[math.ceil(#g*.50)],g[math.ceil(#g*.95)],g[math.ceil(#g*.99)],g[#g]))
      end
      stats("host",gaps);stats("worker",worker_gaps);stats("delivery",batch_delays)
      core.log("action",("LIVE GAP playout frames=%d moving_frames=%d"):format(draws,updated))
      done=true;assert(client.defer({kind="stop"},function() end))
    end
  end)
end)
