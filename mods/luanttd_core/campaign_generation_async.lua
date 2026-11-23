-- One outstanding generation per setup server. The worker writes the
-- packed checkpoint directly; the only callback values are status/error.
local function run(cfg,path,topic)
  return core.luanttd_generate_campaign(cfg,path,topic)
end

return function(core,mod)
  core.register_async_dofile(mod.."/campaign_generation_worker.lua")
  local active,closed,sequence
  sequence=0
  core.register_on_shutdown(function()
    closed=true
    if active then core.ipc_set(active..":cancel",true) end
  end)
  return function(cfg,progress,done)
    if closed or active then return nil,"Interactive generator is unavailable or still busy." end
    sequence=sequence+1
    local topic="luanttd_core:generation:"..sequence
    active=topic
    local last_pct,last_stage
    local function read_progress()
      local data=core.ipc_get(topic..":progress")
      if data and (data.pct~=last_pct or data.stage~=last_stage) then
        last_pct,last_stage=data.pct,data.stage
        progress(data.pct,data.stage)
      end
    end
    local function poll()
      if closed or active~=topic then return end
      read_progress()
      core.after(.08,poll)
    end
    local function complete(ok,why)
      if closed or active~=topic then return end
      read_progress()
      active=nil
      core.ipc_set(topic..":progress",nil)
      core.ipc_set(topic..":cancel",nil)
      done(ok==true,why)
    end
    local sent,accepted=pcall(core.handle_async,run,complete,cfg,core.get_worldpath(),topic)
    if not sent or not accepted then
      active=nil
      return nil,sent and "Luanti rejected the interactive generator job." or tostring(accepted)
    end
    core.after(.05,poll)
    return true
  end
end
