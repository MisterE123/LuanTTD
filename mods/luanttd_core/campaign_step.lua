-- Playback time belongs to the authoritative campaign, not the client.
-- The same daily entry point is used both with a player and on an
-- explicitly enabled headless server; no second economy/routing clock.
local M={}
local min=math.min
function M.new(s,interval,hooks)
  assert(interval>0 and hooks.advance and hooks.refresh)
  local U={}
  local persistent=hooks.persist_fraction
  local speed_before=s.speed
  local elapsed=persistent and (s.campaign_day_fraction or 0)*interval/math.max(1,speed_before or 0) or 0
  local function remember(step)
    local fraction=min(1,elapsed/step)
    if persistent then s.campaign_day_fraction=fraction end
    return fraction
  end
  local function note(ids)
    if not ids or #ids==0 then return end
    local set=s.offscreen_terrain_dirty or {}
    for _,id in ipairs(ids) do set[id]=true end
    s.offscreen_terrain_dirty=set
  end
  local function flush()
    local set=s.offscreen_terrain_dirty
    if not set then return end
    local ids={}
    for id in pairs(set) do ids[#ids+1]=id end
    table.sort(ids)
    if #ids>0 then hooks.refresh(ids) end
    s.offscreen_terrain_dirty=nil
  end
  function U.step(dt,online,headless)
    local speed=s.speed or 0
    if online then flush() end
    if persistent and speed>0 and speed~=speed_before then
      -- Switching playback changes the seconds per day, not the fraction
      -- of today that has already run. Also restores a saved paused game.
      elapsed=(s.campaign_day_fraction or 0)*interval/speed
      speed_before=speed
    elseif persistent and speed<=0 then
      speed_before=0
    end
    if not online and not headless or speed<=0 then
      if not persistent then elapsed=0 end
      return 1,0
    end
    if hooks.prepare then hooks.prepare(s) end
    elapsed=min(elapsed+dt,5*interval)
    local step=interval/speed
    local n=0
    while elapsed>=step and n<12 do
      local plan
      if hooks.take then
        local ready,result=hooks.take(s)
        if not ready then break end
        plan=result
      end
      if online and hooks.capture then hooks.capture() end
      hooks.advance(s,plan)
      if hooks.prepare then hooks.prepare(s) end
      elapsed=elapsed-step;n=n+1
      local edits=s.changed
      if edits then
        if online then hooks.refresh(edits) else note(edits) end
        s.changed=nil
      end
      if not online and hooks.discard_effects then hooks.discard_effects() end
    end
    return remember(step),n
  end
  return U
end
return M
