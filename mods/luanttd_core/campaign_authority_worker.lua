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
  if cap.autoplay and s.stock_generated_profile then
    Sim.mount_live_sea_cache(s)
    runtime.invalidate_sea=function() Sim.clear_live_sea_cache(s) end
  end
  local A=endpoint(Sim,runtime)
  local auto,interval
  local tick_mode=cap.autoplay and s.stock_generated_profile and s.passenger_house_clock and
    Sim.road_stock_service_active(s)
  if cap.autoplay then
    interval=cap.seconds_per_day or 1.25
    assert(type(interval)=="number" and interval>=.05 and interval<=15,"invalid worker day interval")
    local clock=dofile(mod..(tick_mode and "/campaign_tick_step.lua" or "/campaign_step.lua"))
    auto=clock.new(s,interval,{
      now=core.get_us_time,
      persist_fraction=true,
      -- The authored-scenario fallback still advances completed days.
      -- Never block the host through a backlog of several days.
      day_budget=1,
      advance=function(pulse)
        runtime.day(tick_mode and pulse or nil)
        -- Until the UI subscribes to notifications, do not retain
        -- transient loads, arrivals or effects for an invisible world.
        runtime.passengers.collect()
        Sim.rail_paid_motion_events(s)
        runtime.passengers.collect_fares(Sim.rail_coal_loading_events(s),"rail")
        runtime.passengers.collect_fares(Sim.rail_goods_loading_events(s),"rail")
        runtime.passengers.collect_fares(Sim.rail_oil_loading_events(s),"rail")
        for _,cargo in ipairs({"wood","grain","livestock","steel","iron_ore","valuables"}) do
          local take=Sim["rail_"..cargo.."_loading_events"]
          if take then runtime.passengers.collect_fares(take(s),"rail") end
        end
        Sim.air_paid_motion_events(s)
        if runtime.water and runtime.water.coal then
          runtime.passengers.collect_fares(runtime.water.coal.take(s),"ship")
        end
      end,
      refresh=function() end,
    })
  end
  local inbox,outbox,cancel=channel..":request",channel..":reply",channel..":cancel"
  local seq=0
  local prior=core.get_us_time()
  local publish
  if auto then
    local solar=dofile(mod.."/campaign_solar_clock.lua")
    local sample=solar.new(Sim,s,interval)
    local last_us,last_speed
    publish=function(now)
      if s.speed~=last_speed or now-last_us>=solar.sample_interval*1000000 then
        -- Completed actor frames use fraction 1 so they never jump
        -- backwards to the start of that trajectory. A paused sun must
        -- instead use the calendar fraction that will actually reopen.
        local visual_fraction=tick_mode and (s.speed or 0)>0 and auto.sample() or nil
        core.ipc_set(channel..":solar_clock",sample(now,visual_fraction))
        last_us,last_speed=now,s.speed
      end
    end
    publish(prior)
  end
  core.ipc_set(outbox,{seq=seq,ready=true,day=s.day,revision=s.authority_revision or 0})
  local heartbeat,last_saved=prior,prior
  local fraction,overdue=nil,false
  -- The first periodic checkpoint still saves mount-time normalization.
  local dirty=true
  -- Navigation reads the latest completed stock tick, like a viewport;
  -- teleporting the player is host-side, not a campaign edit.
  local navigation={place_labels=true,jump_map=true,jump_tile=true}
  local presentation_only={snapshot=true,snapshots=true,actor_frames=true,clock=true}
  for kind in pairs(navigation) do presentation_only[kind]=true end
  local live_view={snapshots=true,actor_frames=true}
  local function read_only_hover(q)
    -- These two inspected planners read live geometry, occupancy and
    -- cash without changing the saved graph or making a commit ticket.
    -- Facility planners and explicit quotes keep their normal turn.
    if q.peek~=true or type(q.request)~="table" then return false end
    local tool=q.request.tool
    if q.kind=="road_quote" then return tool=="drag" or tool=="bend" end
    if q.kind=="rail_quote" then return tool=="autotrack" end
    return false
  end
  local function passive_news(q)
    -- Automatic headlines follow the already-published HUD head. This
    -- bounded stream detaches rows and neither advances the news clock
    -- nor changes order/finance state. Explicit history stays unchanged.
    return q.kind=="news" and q.page==nil and q.action==nil and type(q.after)=="number"
  end
  local function sample_news(q)
    return A.news(q.player,q.page,q.after,q)
  end
  local function sample_navigation(q)
    if q.kind=="place_labels" then return A.place_labels(q.player,q.x,q.z,q.range) end
    if q.kind=="jump_map" then return A.jump_map(q.player,q.zoom,q.here,q.focus) end
    return A.jump_tile(q.player,q.tile,q.x,q.z)
  end
  local function sample_hover(q)
    if q.kind=="rail_quote" then return A.rail_quote(q.player,q.request,true) end
    return A.road_quote(q.player,q.request)
  end
  local long_turn_us=150000 -- longer than a normal mailbox poll and host frame
  local function advance(dt)
    if (s.speed or 0)>0 then dirty=true end
    local days
    fraction,days,overdue=auto.step(dt,true,true)
  end
  local function sample_view(q,sample)
    if q.kind=="actor_frames" then return A.actor_frames(q.windows,sample or q.fraction,tick_mode) end
    return A.snapshots(q.windows,sample or q.fraction,q.players,tick_mode)
  end
  local function send(q,r,now)
    if live_view[q.kind] then
      r.actor_us=now
      -- Measurements and the render observer can identify exactly
      -- which completed stock state a live sample represents.
      if tick_mode then r.actor_tick=auto.completed_tick() end
    end
    r.seq=q.seq
    core.ipc_set(outbox,r)
  end
  local function checkpoint(pulse)
    storage.write_state(s,pulse)
    last_saved=core.get_us_time()
    dirty=false
  end
  local function periodic_checkpoint()
    local check_at=0
    local blocked=false
    checkpoint(function()
      if blocked then return end
      local now=core.get_us_time()
      if now<check_at then return end
      check_at=now+25000
      if core.ipc_get(cancel) then blocked=true;return end
      local q=core.ipc_get(inbox)
      if not q then return end
      -- Encoding reads one stable graph. Bounded view/navigation
      -- reads and inspected hovers can use it between encoding chunks.
      -- Never read past any edit, shutdown, or other waiting request.
      local hover=read_only_hover(q)
      local nav,news=navigation[q.kind],passive_news(q)
      if q.seq~=seq+1 or not (live_view[q.kind] or hover or nav or news) then blocked=true;return end
      heartbeat=now
      core.ipc_set(inbox,nil)
      seq=q.seq
      local r
      if hover then r=sample_hover(q)
      elseif nav then r=sample_navigation(q)
      elseif news then r=sample_news(q)
      else r=sample_view(q,auto.sample((now-prior)/1000000)) end
      send(q,r,now)
    end)
  end
  -- A paused or unfocused native singleplayer host can stop asking for
  -- view updates completely, even while Luanti's async job stays alive.
  -- The ordinary simulation is a session-lifetime owner, not a view
  -- subscription. Only the explicit shutdown/cancel ends that ownership.
  -- Keep the short fail-safe solely for finite, manual test jobs.
  while (auto or prior-heartbeat<6500000) and not core.ipc_get(cancel) do
    local timeout=tick_mode and auto.poll_ms() or (auto and (overdue and 1 or 35) or 650)
    local q
    if timeout==0 then
      -- There is already a whole stock tick due. Check the mailbox
      -- without a sleep, then continue with the same bounded work.
      q=core.ipc_get(inbox)
    elseif core.ipc_poll(inbox,timeout) then
      q=assert(core.ipc_get(inbox))
    end
    local now=core.get_us_time()
    if core.ipc_get(cancel) then break end
    local deferred
    local read=q and (presentation_only[q.kind] or read_only_hover(q) or passive_news(q))
    if auto then
      local dt=(now-prior)/1000000
      if (s.speed or 0)>0 then dirty=true end
      runtime.frame(dt)
      runtime.passengers.frame(dt)
      -- Already at a completed day with more overdue work. Reply from
      -- this stable boundary before starting the next full batch.
      -- A complete autosave or slow game day can put a view request
      -- behind another full day even if the previous turn wasn't
      -- overdue. Deliver the last complete view before catching up.
      -- Never skip or reorder a simulation tick or a paid edit.
      local late_view=q and q.seq==seq+1 and now-prior>=long_turn_us and live_view[q.kind]
      -- A view due right at the stock-day boundary can already use the
      -- final pose of the completed trajectory. Let that receipt leave
      -- the mailbox before starting the upcoming synchronous stock day.
      -- The very same day advances below without moving any edit.
      local boundary_view=q and q.seq==seq+1 and live_view[q.kind] and
        (s.speed or 0)>0 and auto.sample(dt)==1
      if tick_mode then
        if q and not read then
          -- Cached daily bindings cannot tolerate a mutable command
          -- midway through the stock loop. Complete that transaction,
          -- then service this one request before starting another day.
          if auto.flush() then dirty=true end
          deferred=dt
        else advance(dt) end
      elseif q and (overdue or late_view or boundary_view) then
        deferred=dt
      else advance(dt) end
    end
    prior=now
    if q then
      heartbeat=now
      local sampled_at=tick_mode and live_view[q.kind] and core.get_us_time() or now
      core.ipc_set(inbox,nil)
      local r
      if q.seq~=seq+1 then
        r={ok=false,why="UNEXPECTED_SEQUENCE"}
      else
        seq=q.seq
        -- Do not assume an uncommon panel or command cannot lazily
        -- touch saved state. Only skip the proven display-only traffic.
        if not read then dirty=true end
        if q.kind=="snapshot" then
          r=A.snapshot(q.x,q.z,q.w,q.h,fraction or q.fraction,tick_mode and {road={},rail={},live_tick=true} or nil)
        elseif live_view[q.kind] then
          -- The preceding save may already have sampled ahead within this
          -- completed trajectory. Do not send an older interpolated pose.
          r=sample_view(q,deferred and auto.sample(deferred) or fraction)
        elseif q.kind=="orders" then r=A.orders(q.player,q.mode,q.vehicle,q.page)
        elseif q.kind=="road_quote" then r=A.road_quote(q.player,q.request)
        elseif q.kind=="road_join_choices" then r=A.road_join_choices(q.player,q.request)
        elseif q.kind=="dock_join_choices" then r=A.dock_join_choices(q.player,q.request)
        elseif q.kind=="road_place" then
          local before=s.authority_revision or 0
          r=A.road_place(q.player,q.request,q.quote)
          if r.ok and cap.durable_actions and r.revision~=before then checkpoint() end
        elseif q.kind=="rail_place" then
          local before=s.authority_revision or 0
          r=A.rail_place(q.player,q.request,q.ticket)
          if r.ok and cap.durable_actions and r.revision~=before then checkpoint() end
        elseif q.kind=="rail_quote" then r=A.rail_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="transport_quote" then r=A.transport_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="terrain_quote" then r=A.terrain_quote(q.player,q.request,q.peek==true)
        elseif q.kind=="town_authority" then r=A.town_authority(q.player,q.town)
        elseif q.kind=="company" then r=A.company(q.player)
        elseif q.kind=="news" then r=sample_news(q)
        elseif q.kind=="lesson_progress" then r=A.lesson_progress(q.player,q.lesson)
        elseif navigation[q.kind] then r=sample_navigation(q)
        elseif q.kind=="rail_assembly" then r=A.rail_assembly(q.player,q.depot)
        elseif q.kind=="signal_panel" then r=A.signal_panel(q.player,q.tile,q.hit,q.signal,q.inspect==true,q.peek==true)
        elseif q.kind=="bridge_picker" then r=A.bridge_picker(q.player,q.mode,q.first,q.last,q.peek==true,q.railtype)
        elseif q.kind=="company_fleet" then r=A.company_fleet(q.player,q.page,q.mode)
        elseif q.kind=="vehicle" then r=A.vehicle(q.player,q.mode,q.vehicle,q.locate==true)
        elseif q.kind=="demolition" then r=A.demolition(q.player,q.tile)
        elseif q.kind=="depot" then r=A.depot(q.player,q.mode,q.depot,q.hangar_tile)
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
      send(q,r,sampled_at)
    end
    if deferred then advance(deferred) end
    if publish then publish(now) end
    if auto and dirty and now-last_saved>=8000000 and (not tick_mode or not auto.partial()) then periodic_checkpoint() end
  end
  if tick_mode then auto.flush() end
  storage.write_state(s)
  return not auto and prior-heartbeat>=6500000 and "idle" or "cancelled",seq,s.day
end
