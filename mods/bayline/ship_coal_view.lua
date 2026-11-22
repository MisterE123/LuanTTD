-- Render the actual independent stock Yate actor. The model and steering
-- are presentation only; never create a load, claim a berth or step time.
return function(api,RoadVisual)
  local V={}
  local name="bayline:stock_yate_cargo_ship"
  core.register_entity(name,{initial_properties={physical=false,pointable=false,static_save=false,
    collide_with_objects=false,visual="mesh",mesh="bl_yate_cargo_ship.obj",
    textures={"bl_yate_cargo_ship_atlas.png"},shaded=true,backface_culling=true,
    visual_size={x=1,y=1,z=1}}})
  local ref,yaw
  local function clear()
    if ref and ref:get_pos() then ref:remove() end
    ref,yaw=nil,nil
  end
  function V.step(dt,online,fraction)
    if not online then return end
    for _,event in ipairs(api.ship_coal.take_events() or {}) do
      if event.tile and event.owner then
        if event.kind=="fare" and event.amount then
          api.render.float(event.owner,event.tile,"+$"..math.floor(event.amount),0xa6ee89)
        elseif event.kind=="board" and event.units then
          api.render.float(event.owner,event.tile,event.units.." t loaded aboard",0x9bdce8)
        end
      end
    end
    local pos,dir=api.ship_coal.pose(fraction)
    if not pos or not dir then clear();return end
    local nearby=false
    for _,p in ipairs(core.get_connected_players()) do
      local a=p:get_pos()
      if a and (a.x-pos.x)^2+(a.z-pos.z)^2<112^2 then nearby=true;break end
    end
    if not nearby then clear();return end
    if not ref or not ref:get_pos() then ref=core.add_entity(pos,name);yaw=nil end
    if ref then
      ref:move_to(pos,true)
      yaw=RoadVisual.turn(yaw,RoadVisual.nose_yaw(dir),math.min(.8,dt*7))
      ref:set_rotation({x=0,y=yaw,z=0})
    end
  end
  return V
end
