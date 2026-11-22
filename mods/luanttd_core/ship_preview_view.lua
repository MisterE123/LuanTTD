-- Native waterline presentation of the original Harbor Ferry.
return function(api,Run,RoadVisual,seconds_per_day)
  local M={}
  local name="luanttd_core:stock_harbor_ferry"
  core.register_entity(name,{initial_properties={physical=false,pointable=false,
    collide_with_objects=false,static_save=false,visual="mesh",mesh="bl_harbor_ferry.obj",
    textures={"bl_harbor_ferry_palette.png"},shaded=true,backface_culling=true,
    visual_size={x=1,y=1,z=1}}})
  local acc,ref,yaw=0,nil,nil
  local function stop()
    if ref and ref:get_pos() then ref:remove() end
    ref,yaw=nil,nil
  end
  function M.step(dt,online,fraction)
    if not online then acc=0;return end
    local s=api.s
    local p=Run.current(s)
    if not p then stop();acc=0;return end
    if s.speed>0 and not p.paid_clock then
      acc=math.min(148,acc+dt*74*s.speed/seconds_per_day)
      local ticks=math.floor(acc)
      if ticks>0 then Run.tick(s,ticks);acc=acc-ticks end
    end
    local pos,dir
    if p.paid_clock then pos,dir=api.Sim.ferry_paid_pose(s,fraction)
    else pos,dir=Run.pose(p) end
    if not pos then stop();return end
    local nearby=false
    for _,player in ipairs(core.get_connected_players()) do
      local a=player:get_pos()
      if a and (a.x-pos.x)^2+(a.z-pos.z)^2<112^2 then nearby=true;break end
    end
    if not nearby then stop();return end
    if not ref or not ref:get_pos() then ref=core.add_entity(pos,name);yaw=nil end
    if ref then
      ref:move_to(pos,true)
      yaw=RoadVisual.turn(yaw,RoadVisual.nose_yaw(dir),math.min(.8,dt*7))
      ref:set_rotation({x=0,y=yaw,z=0})
    end
  end
  return M
end
