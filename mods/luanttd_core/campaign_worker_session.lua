-- Native server lifecycle around a single worker writer. The engine owns
-- joining, input, UI, and nearby presentation; only the worker owns money,
-- topology and time once the checkpoint is sealed.
return function(core,mod,api,ui,render,checkpoint,filename,bootstrap,callbacks)
  local Host=dofile(mod.."/campaign_authority_host.lua")
  local Session={}
  local H
  local queue,admitted={},{}
  local closing,retry_scheduled,first_ready,attempts=false,false,false,0
  core.register_on_shutdown(function() closing=true end)
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
  local function present(projection,motion_only)
    if motion_only then
      render.sample_worker_actors(projection)
      return
    end
    painting.present(projection)
    render.draw_worker_actors(projection)
    ui.use_worker_projection(projection)
    if api.stock_audio and projection.take_cash_sounds then
      for _,e in ipairs(projection.take_cash_sounds()) do
        local top=render.host_terrain_top(e.tile)
        if admitted[e.owner] and top then
          local x,z=api.Sim.xy(e.tile)
          api.stock_audio.effect("CASHTILL",{player=e.owner,pos={x=2*x+.5,y=top+.7,z=2*z+.5}})
        end
      end
    end
    ui.hud()
  end
  H=Host(core,mod,{
    freeze_host=function() api.authority_handoff=true end,
    seal_checkpoint=function()
      if bootstrap then checkpoint.write_state(api.s) end
      -- The host is frozen and the worker will read the durable file.
      -- Release dense bootstrap tiles before a second VM decodes them.
      if callbacks.compact_bootstrap and #api.s.tiles>=256*256 then
        api.s.tiles=callbacks.compact_bootstrap(api.s.tiles)
        collectgarbage("collect")
      end
      return filename
    end,
    ready=function(_,projection)
      local recovered=attempts>0
      attempts=0
      core.log("action",recovered and "LuanTTD campaign worker recovered from its checkpoint" or "LuanTTD campaign worker ready")
      if not first_ready then
        first_ready=true
        ui.install_worker_controls(H)
        present(projection)
      end
      for _,p in ipairs(core.get_connected_players()) do
        local n=p:get_player_name()
        if not admitted[n] and not queue[n] then admit(p)
        elseif recovered and callbacks.connection then callbacks.connection(p,"Simulation resumed.") end
      end
    end,
    present=present,
    stopped=function(why,_,_,detail)
      if closing or why=="stopped" then return end
      core.log("warning","LuanTTD campaign worker interrupted; attempting checkpoint recovery: "..tostring(detail or why))
      if retry_scheduled then return end
      if attempts==0 then
        for _,p in ipairs(core.get_connected_players()) do
          if admitted[p:get_player_name()] then
            if callbacks.connection then callbacks.connection(p,"Simulation reconnecting…") end
          else callbacks.wait(p,"Reconnecting to your saved campaign…") end
        end
      end
      local delay=math.min(8,.25*2^math.min(attempts,5))
      attempts=attempts+1
      retry_scheduled=true
      core.after(delay,function()
        retry_scheduled=false
        if not closing and H.status()=="failed" then H.recover() end
      end)
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
        if pos then positions[#positions+1]={x=pos.x,y=pos.y,z=pos.z,name=n} end
      end
    end
    H.step(dt,positions)
    painting.step()
    if api.farm_view then api.farm_view.step(dt,positions) end
    render.step_ambient_particles(dt,positions)
    render.step_worker_actors(dt)
    render.step_local_optics(dt,positions)
    if api.coal_view then
      local sample=#positions>0 and H.solar_clock()
      api.coal_view.step(dt,#positions>0,sample and math.min(6,sample.rate*.55) or 0)
    end
    if H.status()=="owned" and api.crowd then api.crowd.update(core.get_connected_players(),dt) end
  end
  function Session.solar_clock() return H.solar_clock() end
  function Session.status() return H.status() end
  function Session.place_labels(name,x,z,range,done)
    return H.observe({kind="place_labels",player=name,x=x,z=z,range=range},done)
  end
  function Session.query(request,done) return H.query(request,done) end
  return Session
end
