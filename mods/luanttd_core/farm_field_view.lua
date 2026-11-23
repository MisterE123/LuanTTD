-- Bounded presentation of actual stock farm perimeter edges. All fence
-- state and generation remain in the simulation's clear-land field board.
return function(api,Terrain)
  local F={}
  local S,Sim=api.s,api.Sim
  local refs,elapsed={},0
  local spec={
    [0]={0,0,0,1,"v"},[1]={0,1,1,1,"h"},
    [2]={1,0,1,1,"v"},[3]={0,0,1,0,"h"},
  }
  local function name(style,rise)return ("luanttd_core:farm_fence_%d_%d"):format(style,rise) end
  local detail={}
  for _,i in ipairs({5,6,8}) do
    detail[i]="luanttd_core:farm_field_detail_"..i
    core.register_entity(detail[i],{initial_properties={
      visual="mesh",mesh="bl_farm_field_detail_"..i..".obj",
      textures={"bl_farm_fence_atlas.png"},physical=false,collide_with_objects=false,
      static_save=false,pointable=false,shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}
    }})
  end
  for style=1,6 do for rise=0,1 do
    core.register_entity(name(style,rise),{initial_properties={
      visual="mesh",mesh=("bl_farm_fence_%d_%d.obj"):format(style,rise),
      textures={"bl_farm_fence_atlas.png"},physical=false,collide_with_objects=false,
      static_save=false,pointable=false,shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}
    }})
  end end
  local function wanted()
    local players=core.get_connected_players()
    local active={}
    for id in pairs(S.stock_farm_fields or {}) do
      local field=api.farm_world.field(S,id)
      if field then
        local x,z=Sim.xy(id)
        local nearby=false
        for _,p in ipairs(players) do
          local at=p:get_pos()
          if (at.x-(2*x+.5))^2+(at.z-(2*z+.5))^2<64^2 then nearby=true;break end
        end
        if nearby and field.slope==0 and detail[field.variant] then
          active["field:"..id]={id=id,name=detail[field.variant],x=2*x+.5,y=field.base+.504,z=2*z+.5,yaw=0}
        end
        if nearby then for side,style in pairs(field.fences or {}) do
          local e=spec[side]
          if e and style>=1 and style<=6 then
            local xa,za,xb,zb=x+e[1],z+e[2],x+e[3],z+e[4]
            local key=e[5]..":"..xa..":"..za
            if not active[key] or id<active[key].id then
              local low,high=Terrain.corner(S.corner_grid,xa,za),Terrain.corner(S.corner_grid,xb,zb)
              local rise=math.abs(high-low)
              if rise<=1 then
                -- Luanti entity yaw turns model +X toward world +Z
                -- at +pi/2. The graded OBJ's +X end must be uphill.
                local dx,dz=xb-xa,zb-za
                if low>high then dx,dz=-dx,-dz end
                local yaw=math.atan2(dz,dx)
                active[key]={id=id,name=name(style,rise),x=xa+xb-.5,y=math.min(low,high)+.5,z=za+zb-.5,yaw=yaw}
              end
            end
          end
        end end
      end
    end
    return active
  end
  function F.step(dt)
    elapsed=elapsed+dt
    if elapsed<.35 then return end
    elapsed=0
    local keep=wanted()
    for k,v in pairs(refs) do
      local w=keep[k]
      if not w or w.name~=v.name or w.y~=v.y or w.yaw~=v.yaw or not v.ref:get_pos() then
        if v.ref:get_pos() then v.ref:remove() end
        refs[k]=nil
      end
    end
    for k,w in pairs(keep) do
      if not refs[k] then
        local ref=core.add_entity({x=w.x,y=w.y,z=w.z},w.name)
        if ref then
          ref:set_yaw(w.yaw)
          w.ref=ref
          refs[k]=w
        end
      end
    end
  end
  return F
end
