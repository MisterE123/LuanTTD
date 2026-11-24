-- Native gear-contact presentation of the original Sampson-class aircraft.
return function(api,Run,RoadVisual,verified_art)
  local V={}
  local S=api.s
  local mod=core.get_modpath("luanttd_core")
  local rotors=dofile(mod.."/airport_rotor_view.lua")(core)
  local assets=verified_art or dofile(mod.."/airport_manifest.lua")(core,mod)
  for _,art in pairs(assets) do
    rotors.register(art)
    core.register_entity(art.entity,{initial_properties={physical=false,pointable=false,
      collide_with_objects=false,static_save=false,visual="mesh",mesh=art.mesh,
      textures={art.atlas},shaded=true,backface_culling=true,
      visual_size={x=art.scale,y=art.scale,z=art.scale}}})
  end
  function V.has(id) return assets[id]~=nil end
  local views={}
  local function remove(id)
    local x=views[id]
    if x then
      rotors.clear(x)
      if x.ref and x.ref:get_pos() then x.ref:remove() end
      views[id]=nil
    end
  end
  function V.step(dt,online,fraction)
    if not online then for id in pairs(views) do remove(id) end;return end
    local p=Run.current(S)
    if not p then
      for id in pairs(views) do remove(id) end
      return
    end
    local active={}
    for _,run in ipairs(Run.all(S)) do
      local id=run.paid_clock or 0
      local pos,dir,airborne
      if run.paid_clock then pos,dir,airborne=api.Sim.air_paid_pose(S,fraction,id)
      else pos,dir=Run.pose(run) end
      if airborne==nil then airborne=run.vehicle.airborne end
      local art=assets[run.engine_id or 215]
      local identity=id~=0 and id or 1
      if api.vehicle_ui then api.vehicle_ui.track("air",identity,pos) end
      if pos and art and (not api.interest or api.interest.near(pos,views[id]~=nil,144,164)) then
        active[id]=true
        local x=views[id]
        if not x or not x.ref or not x.ref:get_pos() then
          local ref=core.add_entity(pos,art.entity)
          x={ref=ref,pitch=0,shown=art.mesh}
          local entity=ref and ref:get_luaentity()
          if entity then entity.paid_clock=id end
          views[id]=x
        end
        if api.vehicle_ui then api.vehicle_ui.track("air",identity,pos,x.ref) end
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
          local rotation={x=art.rotor and 0 or x.pitch,y=x.yaw,z=0}
          x.ref:set_rotation(rotation)
          if api.vehicle_ui and api.vehicle_ui.ride_track then
            local v=run.vehicle
            local engine=Run.engine_for and Run.engine_for(run)
            api.vehicle_ui.ride_track("air",identity,x.ref,pos,rotation,{
              mesh=mesh,passenger=not v.helicopter and not (engine and engine.passengers==0),
              running=not (v.stopped or v.crashed or v.hidden or run.phase=="blocked")})
          end
          rotors.step(x,art,pos,math.floor((run.vehicle.rotor_speed or 0)/16),dt)
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
