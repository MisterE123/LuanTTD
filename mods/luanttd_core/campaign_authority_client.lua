-- Non-blocking host-side client for the campaign owner.
-- Only one request is outstanding so the mailbox applies in sequence.
local function run(path,session,cap,filename)
  local ok,reason,seq,day=pcall(core.luanttd_own_campaign,path,session,cap,filename)
  if not ok then return "failed",nil,nil,tostring(reason):sub(1,512) end
  return reason,seq,day
end
return function(engine,mod)
  engine.register_async_dofile(mod.."/campaign_authority_worker.lua")
  local running,closed
  local sequence=0
  engine.register_on_shutdown(function()
    closed=true
    if running then engine.ipc_set(running.session..":cancel",true) end
  end)
  local C={}
  local function send(t,req,receive)
    t.next_seq=t.next_seq+1
    local message={}
    for k,v in pairs(req) do message[k]=v end
    message.seq=t.next_seq
    t.reply=receive
    engine.ipc_set(t.session..":request",message)
  end
  local function flush(t)
    if running~=t or closed or t.reply or #t.deferred==0 then return end
    local next_=table.remove(t.deferred,1)
    send(t,next_.req,next_.receive)
  end
  function C.start(cap,on_ready,on_stop,filename)
    if closed or running then return nil,"AUTHORITY_ALREADY_RUNNING" end
    sequence=sequence+1
    local t={session="luanttd_core:authority:"..sequence,next_seq=0,reply=on_ready,deferred={}}
    running=t
    local function done(why,seq,day,detail)
      if running~=t then return end
      running=nil
      for _,suffix in ipairs({":cancel",":request",":reply"}) do engine.ipc_set(t.session..suffix,nil) end
      if not closed then on_stop(why,seq,day,detail) end
    end
    local ok,accepted=pcall(engine.handle_async,run,done,engine.get_worldpath(),t.session,cap,filename)
    if not ok or not accepted then running=nil;return nil,"AUTHORITY_JOB_REJECTED" end
    local function poll()
      if closed or running~=t then return end
      local r=engine.ipc_get(t.session..":reply")
      if r then
        engine.ipc_set(t.session..":reply",nil)
        if not t.reply or r.seq~=t.next_seq then
          engine.ipc_set(t.session..":cancel",true)
        else
          local receiver=t.reply
          t.reply=nil
          receiver(r)
          flush(t)
        end
      end
      engine.after(.035,poll)
    end
    engine.after(.035,poll)
    return true
  end
  function C.query(req,receive)
    if closed or not running or running.reply or #running.deferred>0 then return nil,"AUTHORITY_BUSY" end
    assert(type(req)=="table" and type(receive)=="function")
    send(running,req,receive)
    return true
  end
  -- Observations are disposable; deliberate inputs must not vanish when
  -- a viewport request is already using the mailbox.
  function C.defer(req,receive)
    if closed or not running then return nil,"CAMPAIGN_NOT_READY" end
    assert(type(req)=="table" and type(receive)=="function")
    local t=running
    if #t.deferred>=24 then return nil,"Too many pending campaign actions. Try again in a moment." end
    t.deferred[#t.deferred+1]={req=req,receive=receive}
    flush(t)
    return true
  end
  return C
end
