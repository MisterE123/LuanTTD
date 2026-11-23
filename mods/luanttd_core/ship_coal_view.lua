-- Render the actual independent stock Yate actor. The model and steering
-- are presentation only; never create a load, claim a berth or step time.
return function(api,RoadVisual)
  local V={}
  local name="luanttd_core:stock_yate_cargo_ship"
  core.register_entity(name,{initial_properties={physical=false,pointable=false,static_save=false,
    collide_with_objects=false,visual="mesh",mesh="bl_yate_cargo_ship.obj",
    textures={"bl_yate_cargo_ship_atlas.png"},shaded=true,backface_culling=true,
    visual_size={x=1,y=1,z=1}}})
  local bakewell_name="luanttd_core:stock_bakewell_cargo_ship"
  if api.capabilities and api.capabilities.ferry[212] then
    core.register_entity(bakewell_name,{initial_properties={physical=false,pointable=false,static_save=false,
      collide_with_objects=false,visual="mesh",mesh="bl_stock_bakewell_cargo_ship.obj",
      textures={"bl_stock_bakewell_cargo_ship_atlas.png"},shaded=true,backface_culling=true,
      visual_size={x=1,y=1,z=1}}})
  end
  local ref,yaw,shown
  local function clear()
    if ref and ref:get_pos() then ref:remove() end
    ref,yaw,shown=nil,nil,nil
  end
  function V.step(dt,online,fraction)
    if not online then clear();return end
    for _,event in ipairs(api.ship_coal.take_events() or {}) do
      if event.tile and event.owner then
        if event.kind=="fare" and event.amount then
          api.render.float(event.owner,event.tile,"+$"..math.floor(event.amount),0xa6ee89)
        elseif event.kind=="board" and event.units then
          api.render.float(event.owner,event.tile,event.units.." t loaded aboard",0x9bdce8)
        end
      end
    end
    local status=api.ship_coal.status()
    local current=status and (status.engine==212 and bakewell_name or name)
    if current~=shown then clear() end
    if not current then return end
    local pos,dir=api.ship_coal.pose(fraction)
    if not pos or not dir then clear();return end
    if api.vehicle_ui then api.vehicle_ui.track("ship","coal",pos) end
    local nearby=api.interest and api.interest.near(pos,ref~=nil) or false
    if not api.interest then for _,p in ipairs(core.get_connected_players()) do
      local a=p:get_pos()
      if a and (a.x-pos.x)^2+(a.z-pos.z)^2<112^2 then nearby=true;break end
    end
    end
    if not nearby then clear();return end
    if not ref or not ref:get_pos() then ref=core.add_entity(pos,current);yaw=nil;shown=current end
    if ref then
      if api.vehicle_ui then api.vehicle_ui.track("ship","coal",pos,ref) end
      ref:move_to(pos,true)
      yaw=RoadVisual.turn(yaw,RoadVisual.nose_yaw(dir),math.min(.8,dt*7))
      ref:set_rotation({x=0,y=yaw,z=0})
    end
  end
  return V
end
