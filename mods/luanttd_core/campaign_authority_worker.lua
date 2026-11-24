-- One long-lived job owns the campaign, never one VM per command.
-- Only the worker opens the mounted checkpoint; IPC carries bounded
-- queries, commands and receipts. Ordinary ownership is tied to the engine session.
local mod=assert(core.get_modpath(core.get_current_modname() or "luanttd_core"))
local mounts=dofile(mod.."/campaign_authority_runtime.lua")
local endpoint=dofile(mod.."/campaign_authority_endpoint.lua")
local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
local Codec=dofile(mod.."/packed_campaign.lua")

function core.luanttd_own_campaign(path,channel,cap,filename)
  assert(type(channel)=="string" and channel:match("^luanttd_core:authority:%d+$"),"invalid authority channel")
  local storage=Checkpoints(setmetatable({get_worldpath=function() return path end},{__index=core}),
    Codec,filename or "luanttd-wide-campaign.chk")
  local s=assert(storage.read(),"authority requires a prepared checkpoint")
  if cap.road_town_policy then s.stock_road_town_policy=cap.road_town_policy end
  local Sim=dofile(mod.."/sim.lua")
  local runtime=mounts(Sim,mod,s,cap)
  local A=endpoint(Sim,runtime)
  local auto,interval
  if cap.autoplay then
    interval=cap.seconds_per_day or 1.25
    assert(type(interval)=="number" and interval>=.05 and interval<=15,"invalid worker day interval")
    auto=dofile(mod.."/campaign_step.lua").new(s,interval,{
      persist_fraction=true,
      advance=function()
        runtime.day()
        -- Until the UI subscribes to notifications, do not retain
        -- transient loads, arrivals or effects for an invisible world.
        runtime.passengers.collect()
        Sim.rail_paid_motion_events(s);Sim.rail_coal_loading_events(s)
        Sim.air_paid_motion_events(s)
        if runtime.water and runtime.water.coal then runtime.water.coal.take(s) end
      end,
      refresh=function() end,
    })
  end
  local inbox,outbox=channel..":request",channel..":reply"
  local seq=0
  local prior=core.get_us_time()
  local publish
  if auto then
    local solar=dofile(mod.."/campaign_solar_clock.lua")
    local sample=solar.new(Sim,s,interval)
    local last_us,last_speed
    publish=function(now)
      if s.speed~=last_speed or now-last_us>=solar.sample_interval*1000000 then
        core.ipc_set(channel..":solar_clock",sample(now))
        last_us,last_speed=now,s.speed
      end
    end
    publish(prior)
  end
  core.ipc_set(outbox,{seq=seq,ready=true,day=s.day,revision=s.authority_revision or 0})
  local heartbeat,last_saved=prior,prior
  local function checkpoint()
    storage.write_state(s)
    last_saved=core.get_us_time()
  end
  -- A paused or unfocused native singleplayer host can stop asking for
  -- view updates completely, even while Luanti's async job stays alive.
  -- The ordinary simulation is a session-lifetime owner, not a view
  -- subscription. Only the explicit shutdown/cancel ends that ownership.
  -- Keep the short fail-safe solely for finite, manual test jobs.
  while (auto or prior-heartbeat<6500000) and not core.ipc_get(channel..":cancel") do
    local available=core.ipc_poll(inbox,auto and 35 or 650)
    local now=core.get_us_time()
    if core.ipc_get(channel..":cancel") then break end
    local fraction
    if auto then
      local dt=(now-prior)/1000000
      runtime.frame(dt)
      runtime.passengers.frame(dt)
      fraction=auto.step(dt,true,true)
    end
    prior=now
    if available then
      heartbeat=now
      local q=assert(core.ipc_get(inbox))
      core.ipc_set(inbox,nil)
      local r
      if q.seq~=seq+1 then
        r={ok=false,why="UNEXPECTED_SEQUENCE"}
      else
        seq=q.seq
        if q.kind=="snapshot" then r=A.snapshot(q.x,q.z,q.w,q.h,fraction or q.fraction)
        elseif q.kind=="snapshots" then r=A.snapshots(q.windows,fraction or q.fraction,q.players)
        elseif q.kind=="actor_frames" then r=A.actor_frames(q.windows,fraction or q.fraction)
        elseif q.kind=="orders" then r=A.orders(q.player,q.mode,q.vehicle,q.page)
        elseif q.kind=="road_quote" then r=A.road_quote(q.player,q.request)
        elseif q.kind=="road_join_choices" then r=A.road_join_choices(q.player,q.request)
        elseif q.kind=="road_place" then
          local before=s.authority_revision or 0
          r=A.road_place(q.player,q.request,q.quote)
          if r.ok and cap.durable_actions and r.revision~=before then checkpoint() end
        elseif q.kind=="rail_quote" then r=A.rail_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="transport_quote" then r=A.transport_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="terrain_quote" then r=A.terrain_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="town_authority" then r=A.town_authority(q.player,q.town)
        elseif q.kind=="company" then r=A.company(q.player)
        elseif q.kind=="news" then r=A.news(q.player,q.page,q.after,q)
        elseif q.kind=="lesson_progress" then r=A.lesson_progress(q.player,q.lesson)
        elseif q.kind=="place_labels" then r=A.place_labels(q.player,q.x,q.z,q.range)
        elseif q.kind=="jump_map" then r=A.jump_map(q.player,q.zoom,q.here,q.focus)
        elseif q.kind=="jump_tile" then r=A.jump_tile(q.player,q.tile,q.x,q.z)
        elseif q.kind=="rail_assembly" then r=A.rail_assembly(q.player,q.depot)
        elseif q.kind=="signal_panel" then r=A.signal_panel(q.player,q.tile,q.hit,q.signal,q.inspect==true,q.peek==true)
        elseif q.kind=="bridge_picker" then r=A.bridge_picker(q.player,q.mode,q.first,q.last,q.peek==true,q.railtype)
        elseif q.kind=="company_fleet" then r=A.company_fleet(q.player,q.page)
        elseif q.kind=="vehicle" then r=A.vehicle(q.player,q.mode,q.vehicle,q.locate==true)
        elseif q.kind=="demolition" then r=A.demolition(q.player,q.tile)
        elseif q.kind=="depot" then r=A.depot(q.player,q.mode,q.depot)
        elseif q.kind=="depot_order_sources" then r=A.depot_order_sources(q.player,q.mode,q.vehicle,q.depot)
        elseif q.kind=="rail_mail_station" then r=A.rail_mail_station(q.player,q.tile)
        elseif q.kind=="truck_stop" then r=A.truck_stop(q.player,q.tile)
        elseif q.kind=="advance" and not auto then r=A.advance(q.days)
        elseif q.kind=="clock" then r={ok=true,day=s.day,tick=s.passenger_house_clock and
          s.passenger_house_clock.counter or 0,revision=s.authority_revision or 0}
        elseif q.kind=="command" then
          local before=s.authority_revision or 0
          r=A.command(q.player,q.command)
          if publish and r.ok and q.command.kind=="speed" then publish(now) end
          if r.ok and cap.durable_actions and r.revision~=before then checkpoint() end
        elseif q.kind=="checkpoint" then
          checkpoint()
          r={ok=true,day=s.day,revision=s.authority_revision or 0}
        elseif q.kind=="stop" then
          checkpoint()
          return "stopped",seq,s.day
        else r={ok=false,why="UNKNOWN_OPERATION"} end
      end
      if q.kind=="snapshots" or q.kind=="actor_frames" then r.actor_us=now end
      r.seq=q.seq
      core.ipc_set(outbox,r)
    end
    if publish then publish(now) end
    if auto and now-last_saved>=8000000 then checkpoint() end
  end
  storage.write_state(s)
  return not auto and prior-heartbeat>=6500000 and "idle" or "cancelled",seq,s.day
end
