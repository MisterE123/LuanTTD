-- Native gear-contact presentation of the original Sampson-class aircraft.
return function(api,Run,RoadVisual,seconds_per_day)
  local V={}
  local S=api.s
  local mod=core.get_modpath("bayline")
  local files={}
  for _,subdir in ipairs({"models","textures"}) do
    for _,filename in ipairs(core.get_dir_list(mod.."/"..subdir,false)) do files[filename]=true end
  end
  local assets={}
  for _,art in pairs(dofile(mod.."/airport_airframe_art.lua")) do
    if files[art.mesh] and files[art.atlas] and (not art.flight or files[art.flight]) then
      assets[art.id]=art
      core.register_entity(art.entity,{initial_properties={physical=false,pointable=false,
        collide_with_objects=false,static_save=false,visual="mesh",mesh=art.mesh,
        textures={art.atlas},shaded=true,backface_culling=true,
        visual_size={x=art.scale,y=art.scale,z=art.scale}}})
    end
  end
  function V.has(id) return assets[id]~=nil end
  local views,acc={},0
  local function remove(id)
    local x=views[id]
    if x then
      if x.ref and x.ref:get_pos() then x.ref:remove() end
      views[id]=nil
    end
  end
  function V.step(dt,online,fraction)
    if not online then acc=0;return end
    local p=Run.current(S)
    if not p then
      for id in pairs(views) do remove(id) end
      acc=0;return
    end
    if S.speed>0 and not p.paid_clock then
      acc=math.min(148,acc+dt*74*S.speed/seconds_per_day)
      local n=math.floor(acc)
      if n>0 then Run.tick(S,n,V.observe);acc=acc-n end
    end
    local active={}
    for _,run in ipairs(Run.all(S)) do
      local id=run.paid_clock or 0
      local pos,dir,airborne
      if run.paid_clock then pos,dir,airborne=api.Sim.air_paid_pose(S,fraction,id)
      else pos,dir=Run.pose(run) end
      if airborne==nil then airborne=run.vehicle.airborne end
      local art=assets[run.engine_id or 215]
      if pos and art then
        active[id]=true
        local x=views[id]
        if not x or not x.ref or not x.ref:get_pos() then
          local ref=core.add_entity(pos,art.entity)
          x={ref=ref,pitch=0,shown=art.mesh}
          if ref then ref:get_luaentity().paid_clock=id end
          views[id]=x
        end
        if x.ref then
          local mesh=airborne and art.flight or art.mesh
          if mesh~=x.shown then x.ref:set_properties({mesh=mesh});x.shown=mesh end
          x.yaw=RoadVisual.turn(x.yaw,RoadVisual.nose_yaw(dir),math.min(.8,dt*7.2))
          local target=0
          if x.last and airborne then
            local d=math.sqrt((pos.x-x.last.x)^2+(pos.z-x.last.z)^2)
            if d>0.01 then target=math.max(-.25,math.min(.25,-math.atan2(pos.y-x.last.y,d)))
            else target=x.pitch end
          end
          x.pitch=airborne and x.pitch+(target-x.pitch)*math.min(1,4*dt) or 0
          x.ref:move_to(pos,true)
          x.ref:set_rotation({x=x.pitch,y=x.yaw,z=0})
          x.last=pos
        end
      end
    end
    for id in pairs(views) do if not active[id] then remove(id) end end
    if V.observe then
      for _,e in ipairs(api.Sim.air_paid_motion_events(S)) do
        local run=Run.current(S,e.paid_clock)
        if run then V.observe(e.kind,run,S.stock_small_airports[e.airport],e) end
      end
    end
  end
  return V
end
