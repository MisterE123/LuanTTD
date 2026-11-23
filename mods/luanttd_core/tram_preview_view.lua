-- Dedicated pilot presentation. No fleet, cargo or payment semantics.
return function(api,Run,Pose,RoadVisual)
  local V={}
  local S=api.s
  local ref,last_yaw
  local function remove()
    if ref and ref:get_pos() then ref:remove() end
    ref,last_yaw=nil,nil
  end
  function V.step(dt,online)
    if not online then remove();return end
    local pilot=Run.current(S)
    if not pilot then remove();return end
    local f=Run.frame(pilot)
    if not f then remove();return end
    local x,z=Pose.xy(f[1],f[2],f[5])
    local _,level=api.terrain.tile(f[4])
    local target=RoadVisual.nose_yaw(Pose.yaw(f[3]))
    local p={x=x,y=level+.512,z=z}
    if api.vehicle_ui then api.vehicle_ui.track("tram",1,p) end
    if api.interest and not api.interest.near(p,ref~=nil) then remove();return end
    if not ref or not ref:get_pos() then
      ref=core.add_entity(p,"luanttd_core:tram_preview_vehicle")
      last_yaw=nil
    end
    if api.vehicle_ui then api.vehicle_ui.track("tram",1,p,ref) end
    if ref then
      ref:move_to(p,true)
      last_yaw=RoadVisual.turn(last_yaw,target,math.min(1.0,dt*9))
      ref:set_rotation({x=0,y=last_yaw,z=0})
    end
  end
  return V
end
