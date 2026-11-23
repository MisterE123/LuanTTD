-- Native server lifecycle around a single worker writer. The engine owns
-- joining, input, UI, and nearby presentation; only the worker owns money,
-- topology and time once the checkpoint is sealed.
return function(core,mod,api,ui,render,checkpoint,filename,bootstrap,callbacks)
  local Host=dofile(mod.."/campaign_authority_host.lua")
  local Session={}
  local H
  local queue,admitted={},{}
  local speed=0
  local painting=dofile(mod.."/campaign_projection_painter.lua")(render,function(_,ok,why)
    if not ok then core.log("warning","LuanTTD viewport placement: "..tostring(why)) end
  end)
  local function admit(p)
    local n=p:get_player_name()
    local tag={}
    queue[n]=tag
    local sent,why=H.query({kind="command",player=n,command={kind="company_open"}},function(r)
      if queue[n]~=tag then return end
      queue[n]=nil
      local live=core.get_player_by_name(n)
      if not live then return end
      if r.ok then
        admitted[n]=true
        callbacks.open(live)
      else callbacks.wait(live,r.why or "Could not open your company.") end
    end)
    if not sent then
      queue[n]=nil;callbacks.wait(p,why)
      if H.status()=="owned" then
        core.after(.4,function()
          local live=core.get_player_by_name(n)
          if live and H.status()=="owned" and not queue[n] and not admitted[n] then admit(live) end
        end)
      end
    end
  end
  local function present(projection)
    painting.present(projection)
    render.draw_worker_actors(projection,.2)
    ui.use_worker_projection(projection)
    ui.hud()
    for n in pairs(admitted) do
      local v=projection.company(n)
      if v then speed=v.speed;break end
    end
  end
  H=Host(core,mod,{
    freeze_host=function() api.authority_handoff=true end,
    seal_checkpoint=function()
      if bootstrap then checkpoint.write_state(api.s) end
      return filename
    end,
    ready=function(_,projection)
      ui.install_worker_controls(H)
      present(projection)
      for _,p in ipairs(core.get_connected_players()) do admit(p) end
    end,
    present=present,
    stopped=function(why,_,_,detail)
      speed=0
      core.log("error","LuanTTD simulation owner stopped: "..tostring(detail or why))
      for _,p in ipairs(core.get_connected_players()) do
        callbacks.wait(p,"The simulation worker stopped. Reopen the world to resume from its checkpoint.")
      end
    end,
  })
  function Session.start(cap,width,depth)
    return H.start(cap,width,depth)
  end
  function Session.join(p)
    if H.status()=="owned" then admit(p)
    else callbacks.wait(p,"Opening the simulation worker…") end
  end
  function Session.leave(n)
    queue[n]=nil;admitted[n]=nil
  end
  function Session.step(dt)
    local positions={}
    for _,p in ipairs(core.get_connected_players()) do
      local n=p:get_player_name()
      if admitted[n] then
        local pos=p:get_pos()
        if pos then positions[#positions+1]={x=pos.x,z=pos.z,name=n} end
      end
    end
    H.step(dt,positions)
    painting.step()
  end
  function Session.speed() return speed end
  function Session.status() return H.status() end
  function Session.query(request,done) return H.query(request,done) end
  return Session
end
