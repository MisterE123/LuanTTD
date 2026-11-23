-- One long-lived job owns the campaign, never one VM per command.
-- Only the worker opens the mounted checkpoint; IPC carries bounded
-- queries, commands and receipts. This is not yet the ordinary game mount.
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
  local Sim=dofile(mod.."/sim.lua")
  local A=endpoint(Sim,mounts(Sim,mod,s,cap))
  local inbox,outbox=channel..":request",channel..":reply"
  local seq=0
  core.ipc_set(outbox,{seq=seq,ready=true,day=s.day,revision=s.authority_revision or 0})
  local idle=0
  while idle<10 and not core.ipc_get(channel..":cancel") do
    if core.ipc_poll(inbox,650) then
      idle=0
      if core.ipc_get(channel..":cancel") then break end
      local q=assert(core.ipc_get(inbox))
      core.ipc_set(inbox,nil)
      local r
      if q.seq~=seq+1 then
        r={ok=false,why="UNEXPECTED_SEQUENCE"}
      else
        seq=q.seq
        if q.kind=="snapshot" then r=A.snapshot(q.x,q.z,q.w,q.h)
        elseif q.kind=="advance" then r=A.advance(q.days)
        elseif q.kind=="command" then r=A.command(q.player,q.command)
        elseif q.kind=="checkpoint" then
          storage.write_state(s)
          r={ok=true,day=s.day,revision=s.authority_revision or 0}
        elseif q.kind=="stop" then
          storage.write_state(s)
          return "stopped",seq,s.day
        else r={ok=false,why="UNKNOWN_OPERATION"} end
      end
      r.seq=q.seq
      core.ipc_set(outbox,r)
    else idle=idle+1 end
  end
  storage.write_state(s)
  return idle==10 and "idle" or "cancelled",seq,s.day
end
