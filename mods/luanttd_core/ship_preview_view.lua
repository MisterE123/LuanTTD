-- Native waterline presentation of the purchased MPS and FFP ferries.
return function(api,Run,RoadVisual)
  local M={}
  local names={[206]="luanttd_core:stock_harbor_ferry",[207]="luanttd_core:stock_ffp_passenger_ferry"}
  local meshes={[206]="bl_harbor_ferry.obj",[207]="bl_ffp_passenger_ferry.obj"}
  if api.capabilities and api.capabilities.ferry[208] then
    names[208]="luanttd_core:stock_bakewell_300_hovercraft"
    meshes[208]="bl_stock_bakewell_300_hovercraft.obj"
  end
  for id,name in pairs(names) do
    core.register_entity(name,{initial_properties={physical=false,pointable=false,
      collide_with_objects=false,static_save=false,visual="mesh",mesh=meshes[id],
      textures={id==208 and "bl_stock_bakewell_300_hovercraft_atlas.png" or "bl_harbor_ferry_palette.png"},shaded=true,backface_culling=true,
      visual_size={x=1,y=1,z=1}}})
  end
  local ref,yaw
  local function stop()
    if ref and ref:get_pos() then ref:remove() end
    ref,yaw=nil,nil
  end
  function M.step(dt,online,fraction)
    if not online then stop();return end
    local s=api.s
    local p=Run.current(s)
    if not p or Run.paid_art_ready and not Run.paid_art_ready(s,p) then stop();return end
    local name=names[p.engine_id or 206]
    if not name then stop();return end
    local pos,dir
    if p.paid_clock then pos,dir=api.Sim.ferry_paid_pose(s,fraction)
    else pos,dir=Run.pose(p) end
    if not pos then stop();return end
    if api.vehicle_ui then api.vehicle_ui.track("ship","ferry",pos) end
    local nearby=api.interest and api.interest.near(pos,ref~=nil) or false
    if not api.interest then for _,player in ipairs(core.get_connected_players()) do
      local a=player:get_pos()
      if a and (a.x-pos.x)^2+(a.z-pos.z)^2<112^2 then nearby=true;break end
    end
    end
    if not nearby then stop();return end
    if ref then
      -- An ObjectRef can outlive its Lua entity during deactivation or
      -- removal. Rebuild only the disposable mesh, not the ferry run.
      local entity=ref:get_luaentity()
      if not entity or entity.name~=name or not ref:get_pos() then stop() end
    end
    if not ref then ref=core.add_entity(pos,name);yaw=nil end
    if ref and ref:get_pos() then
      if api.vehicle_ui then api.vehicle_ui.track("ship","ferry",pos,ref) end
      ref:move_to(pos,true)
      yaw=RoadVisual.turn(yaw,RoadVisual.nose_yaw(dir),math.min(.8,dt*7))
      ref:set_rotation({x=0,y=yaw,z=0})
    end
  end
  return M
end
