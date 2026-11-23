-- Renderer for the single persisted platform pilot. Not legacy fleet or PBS.
return function(api,Run,Pose)
  local V={}
  local Sim,S=api.Sim,api.s
  local ref
  local function remove()
    if ref and ref:get_pos() then ref:remove() end
    ref=nil
  end
  function V.step(dt,online)
    if not online then remove();return end
    local run=Run.current(S)
    if not run then remove();return end
    local id,td,f=Run.sample(run)
    if not id then remove();return end
    local x,z,dx,dz
    if api.render and api.render.rail_diagonal_pose then x,z,dx,dz=api.render.rail_diagonal_pose(id,td,f) end
    if x==nil then x,z,dx,dz=Pose.sample(td,f) end
    local tx,tz=Sim.xy(id)
    local base=S.tiles[id].h
    if api.terrain then local _,level=api.terrain.tile(id);base=level end
    local p={x=2*tx+.5+x,y=base+.612,z=2*tz+.5+z}
    if api.interest and not api.interest.near(p,ref~=nil) then remove();return end
    if not ref or not ref:get_pos() then ref=core.add_entity(p,"luanttd_core:vehicle_"..run.visual) end
    if ref then
      ref:move_to(p,true)
      ref:set_rotation({x=0,y=math.pi-math.atan2(dx,dz),z=0})
    end
  end
  return V
end
