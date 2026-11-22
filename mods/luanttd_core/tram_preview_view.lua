-- Dedicated pilot presentation. No fleet, cargo or payment semantics.
return function(api,Run,Pose,RoadVisual,seconds_per_day)
  local V={}
  local S=api.s
  local ref,acc,last_yaw
  local function remove()
    if ref and ref:get_pos() then ref:remove() end
    ref,last_yaw=nil,nil
  end
  function V.step(dt,online)
    if not online then acc=0;return end
    local pilot=Run.current(S)
    if not pilot then remove();acc=0;return end
    if S.speed>0 then
      acc=math.min(148,(acc or 0)+dt*74*S.speed/seconds_per_day)
      local n=math.floor(acc)
      if n>0 then Run.advance(S,n);acc=acc-n end
    end
    local f=Run.frame(pilot)
    if not f then remove();return end
    local x,z=Pose.xy(f[1],f[2],f[5])
    local _,level=api.terrain.tile(f[4])
    local target=RoadVisual.nose_yaw(Pose.yaw(f[3]))
    local p={x=x,y=level+.512,z=z}
    if not ref or not ref:get_pos() then
      ref=core.add_entity(p,"luanttd_core:tram_preview_vehicle")
      last_yaw=nil
    end
    if ref then
      ref:move_to(p,true)
      last_yaw=RoadVisual.turn(last_yaw,target,math.min(1.0,dt*9))
      ref:set_rotation({x=0,y=last_yaw,z=0})
    end
  end
  return V
end
