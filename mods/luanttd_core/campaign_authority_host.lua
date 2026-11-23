-- Handoff/lifecycle wrapper: the old authority must be frozen before the
-- checkpoint is sealed and cannot resume as a fallback to a lost worker.
-- The caller owns engine painting and the visible company UI.
return function(engine,mod,callbacks)
  local client=dofile(mod.."/campaign_authority_client.lua")(engine,mod)
  local ReadView=dofile(mod.."/campaign_authority_projection.lua")
  local Interest=dofile(mod.."/campaign_authority_interest.lua")
  local H={}
  local state="local"
  local view,interest
  local idle=0
  local config,filename
  function H.status() return state end
  local function open()
    if not filename then
      state="sealing"
      local sealed,path=pcall(callbacks.seal_checkpoint)
      if not sealed or not path then
        state="failed"
        callbacks.stopped("checkpoint_failed",nil,nil,path)
        return nil,"HANDOFF_CHECKPOINT_FAILED"
      end
      filename=path
    end
    view=ReadView()
    idle=0
    interest=Interest(client,view,config.width,config.depth,callbacks.present)
    state="opening"
    local started,reason=client.start(config.caps,function(receipt)
      if not receipt.ready or state~="opening" then return end
      state="owned"
      callbacks.ready(receipt,view)
    end,function(why,seq,day,detail)
      state=why=="stopped" and "closed" or "failed"
      interest.update({})
      callbacks.stopped(why,seq,day,detail)
    end,filename)
    if not started then
      state="failed"
      callbacks.stopped(reason)
      return nil,reason
    end
    return true
  end
  function H.start(caps,width,depth)
    if state~="local" then return nil,"HANDOFF_ALREADY_STARTED" end
    config={caps=caps,width=width,depth=depth}
    callbacks.freeze_host()
    return open()
  end
  function H.recover()
    -- Only the old async completion callback can set "failed". A lease
    -- still owned by a live worker never starts a competing writer.
    if state~="failed" or not config then return nil,"CAMPAIGN_NOT_RECOVERABLE_YET" end
    return open()
  end
  function H.step(dt,positions,fraction)
    if state~="owned" then return false end
    interest.update(positions)
    if #positions>0 then idle=0;return interest.step(dt,fraction) end
    -- Only finite manual harnesses retain the keepalive watchdog.
    if not config.caps.autoplay then
      idle=idle+dt
      if idle>=2 and client.query({kind="clock"},function() end) then idle=0 end
    end
    return false
  end
  function H.solar_clock()
    if state=="owned" then return client.solar_clock() end
  end
  function H.observe(request,done)
    if state~="owned" then return nil,"CAMPAIGN_NOT_READY" end
    return client.query(request,done)
  end
  function H.query(request,done)
    if state~="owned" then return nil,"CAMPAIGN_NOT_READY" end
    return client.defer(request,done)
  end
  return H
end
