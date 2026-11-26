-- Real stationary mast in the airport tile; lightweight
-- animated cloth (Luanti skinning), mounted only near painted airports.
return function(core,Sim,Wind,painted)
  local V={}
  local name="luanttd_core:airport_windsock"
  local refs,clock,poll={},0,.3
  local enter,leave=38,46
  -- Native OBJ exported from the same art datum; Luanti reflects OBJ X.
  local pole={x=-.282,y=.411,z=-.185}
  local function definition()
    return {visual="mesh",mesh="bl_airport_windsock.glb",textures={"bl_airport_windsock.png"},
      visual_size={x=10,y=10,z=10},static_save=false,physical=false,collide_with_objects=false,
      pointable=false,backface_culling=false}
  end
  core.register_entity(name,{initial_properties=definition()})
  local function remove(id)
    local r=refs[id]
    if r.ref:get_pos() then r.ref:remove() end
    refs[id]=nil
  end
  local function orient(r,at)
    local x,z,speed=Wind.sample(at.x,at.z,clock)
    local heading=math.atan2(-x,z) -- Luanti yaw rotates local +Z toward -X
    if not r.yaw or math.abs(heading-r.yaw)>.012 then
      r.ref:set_yaw(heading)
      r.yaw=heading
    end
    local rate=math.floor(11+speed*7+.5)
    if not r.rate then
      r.ref:set_animation({x=0,y=60},rate,0,true)
    elseif rate~=r.rate then
      r.ref:set_animation_frame_speed(rate)
    end
    r.rate=rate
  end
  function V.step(dt,s,viewers)
    clock,poll=clock+dt,poll+dt
    if not viewers[1] then
      for id in pairs(refs) do remove(id) end
      poll=.3
      return
    end
    if poll<.3 then return end
    poll=poll%.3
    local seen,visit={},{}
    for _,p in ipairs(viewers) do
      local a,b=math.max(1,math.floor((p.x-leave)/2)),math.min(Sim.W,math.ceil((p.x+leave)/2))
      local c,d=math.max(1,math.floor((p.z-leave)/2)),math.min(Sim.H,math.ceil((p.z+leave)/2))
      for z=c,d do for x=a,b do
        local id=Sim.id(x,z)
        local t=id and s.tiles[id]
        local field=t and t.airfield
        if field and (field.layout==nil or field.layout=="country") and field.x==0 and field.z==1 then
          local old=refs[id]
          if visit[id]==nil then visit[id]=painted(id,x,z,field) or false end
          local level=visit[id]
          if level then
            local at={x=2*x+pole.x,y=level+1+pole.y,z=2*z+pole.z}
            if (p.x-at.x)^2+(p.y-at.y)^2+(p.z-at.z)^2<=(old and leave or enter)^2 then
              seen[id]=at
            end
          end
        end
      end end
    end
    for id,r in pairs(refs) do
      local a=seen[id]
      if not a or a.y~=r.y or not r.ref:get_pos() then remove(id) end
    end
    for id,at in pairs(seen) do
      local r=refs[id]
      if not r then
        local ref=core.add_entity(at,name)
        if ref then r={ref=ref,y=at.y};refs[id]=r end
      end
      if r then orient(r,at) end
    end
  end
  return V
end
