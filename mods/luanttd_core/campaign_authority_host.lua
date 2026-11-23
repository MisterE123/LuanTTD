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
  function H.status() return state end
  function H.start(caps,width,depth)
    if state~="local" then return nil,"HANDOFF_ALREADY_STARTED" end
    state="sealing"
    callbacks.freeze_host()
    local sealed,filename=pcall(callbacks.seal_checkpoint)
    if not sealed or not filename then
      state="failed"
      callbacks.stopped("checkpoint_failed",nil,nil,filename)
      return nil,"HANDOFF_CHECKPOINT_FAILED"
    end
    view=ReadView()
    interest=Interest(client,view,width,depth,callbacks.present)
    state="opening"
    local started,reason=client.start(caps,function(receipt)
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
  function H.step(dt,positions,fraction)
    if state~="owned" then return false end
    interest.update(positions)
    return interest.step(dt,fraction)
  end
  function H.query(request,done)
    if state~="owned" then return nil,"CAMPAIGN_NOT_READY" end
    return client.defer(request,done)
  end
  return H
end
