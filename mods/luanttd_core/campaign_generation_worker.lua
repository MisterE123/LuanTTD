-- Interactive setup runs the same generator and checkpoint writer as the
-- host. This VM never sees a player, ObjectRef, map, or ModStorageRef.
local mod=assert(core.get_modpath(core.get_current_modname() or "luanttd_core"))
local Setup=dofile(mod.."/world_setup.lua")
local Checkpoints=dofile(mod.."/campaign_checkpoint.lua")
local Codec=dofile(mod.."/packed_campaign.lua")
local cancelled={}
function core.luanttd_generate_campaign(cfg,path,topic)
  local last_check,pct_sent,stage_sent
  local function pulse(pct,stage)
    local now=core.get_us_time()
    if not last_check or now-last_check>=20000 or stage~=stage_sent then
      if core.ipc_get(topic..":cancel") then error(cancelled,0) end
      last_check=now
    end
    if stage==stage_sent and pct==pct_sent then return end
    pct_sent,stage_sent=pct,stage
    core.ipc_set(topic..":progress",{pct=pct,stage=stage})
  end
  local ok,why=pcall(function()
    -- Fresh modules isolate each job's mutable Sim dimensions and mounts.
    local sim=dofile(mod.."/sim.lua")
    local generate=dofile(mod.."/campaign_generation.lua")(core,mod,sim,Setup)
    local state=generate.run(cfg,pulse)
    pulse(87,"Saving your new world")
    local host=setmetatable({get_worldpath=function() return path end},{__index=core})
    Checkpoints(host,Codec,"luanttd-prepared-campaign.chk").write_state(state,function()
      pulse(87,"Saving your new world")
    end)
    return true
  end)
  if ok then return true end
  if why==cancelled then return false,"Generation cancelled" end
  return false,tostring(why):sub(1,768)
end
