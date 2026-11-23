-- Player-local repair smoke. The running engine owns fault timing; the
-- renderer never consumes the simulation RNG or restarts a failure.
return function(add)
  local V={now=0,due={}}
  function V.step(dt)
    V.now=V.now+dt
  end
  function V.draw_active(id,active,pos,yaw,players,paused)
    if not active then
      V.due[id]=nil
      return 0
    end
    if paused or not pos or V.now<(V.due[id] or 0) then return 0 end
    local emitted=0
    local texture={name="bl_road_breakdown_smoke.png",alpha_tween={.94,0},scale_tween={{x=.88,y=.91},{x=1.55,y=1.45}}}
    local sine,cosine=math.sin(yaw or 0),math.cos(yaw or 0)
    local at={x=pos.x+sine*.09,y=pos.y+.37,z=pos.z+cosine*.09}
    for _,p in ipairs(players) do
      local q=p:get_pos()
      if q and (q.x-at.x)^2+(q.y-at.y)^2+(q.z-at.z)^2<34^2 then
        add({pos=at,velocity={x=.10,y=.61,z=.08},
          acceleration={x=.036,y=.105,z=.018},size=3.05,expirationtime=1.05,
          texture=texture,playername=p:get_player_name(),collisiondetection=false})
        emitted=emitted+1
      end
    end
    if emitted>0 then V.due[id]=V.now+.22 end
    return emitted
  end
  function V.draw(id,state,pos,yaw,players,paused)
    return V.draw_active(id,state and state.breakdown_ctr==1 and state.breakdown_delay>0,
      pos,yaw,players,paused)
  end
  function V.remove(id) V.due[id]=nil end
  return V
end
