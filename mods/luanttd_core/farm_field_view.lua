-- Bounded presentation of actual stock farm perimeter edges. All fence
-- state and generation remain in the simulation's clear-land field board.
return function(api,Terrain)
  local F={}
  local S,Sim=api.s,api.Sim
  local projected=false
  function F.use_worker_projection(state)
    S,projected=state,true
  end
  local refs,elapsed={},0
  local hulls={}
  local name_hull="luanttd_core:farm_fence_walk_hull"
  local heights
  if core.get_modpath then
    heights=dofile(core.get_modpath("luanttd_core").."/walk_collision_art.lua").farm
    core.register_entity(name_hull,{initial_properties={
      physical=true,collide_with_objects=true,pointable=false,static_save=false,
      visual="sprite",textures={"bl_sightseeing_hidden_player.png"},visual_size={x=.001,y=.001},
      collisionbox={0,0,0,0,0,0},
    }})
  end
  local spec={
    [0]={0,0,0,1,"v"},[1]={0,1,1,1,"h"},
    [2]={1,0,1,1,"v"},[3]={0,0,1,0,"h"},
  }
  local function name(style,rise)return ("luanttd_core:farm_fence_%d_%d"):format(style,rise) end
  local detail={}
  local slope_sample=api.slope and api.slope.surface
  for i=2,8 do
    detail[i]={}
    for k,suffix in ipairs({"","_patch"}) do
      local asset="crop_growth_"..i..suffix
      local entity="luanttd_core:"..asset
      detail[i][k]=entity
      core.register_entity(entity,{initial_properties={
        visual="mesh",mesh="bl_"..asset..".obj",
        textures={"bl_crop_growth_atlas.png"},physical=false,collide_with_objects=false,
        static_save=false,pointable=false,shaded=false,backface_culling=false,visual_size={x=1,y=1,z=1}
      }})
    end
  end
  for style=1,6 do for rise=0,1 do
    core.register_entity(name(style,rise),{initial_properties={
      visual="mesh",mesh=("bl_farm_fence_%d_%d.obj"):format(style,rise),
      textures={"bl_farm_fence_atlas.png"},physical=false,collide_with_objects=false,
      static_save=false,pointable=false,shaded=true,backface_culling=true,visual_size={x=1,y=1,z=1}
    }})
  end end
  local function wanted(positions)
    local local_interest=not projected and api.interest
    if not positions then
      positions={}
      for _,p in ipairs(core.get_connected_players()) do
        local pos=p:get_pos()
        if pos then positions[#positions+1]=pos end
      end
    end
    local active,crops={},{}
    local fields=S.stock_farm_fields or {}
    local function visit(id)
      local field=fields[id] and api.farm_world.field(S,id)
      if field then
        local x,z=Sim.xy(id)
        local nearby=local_interest and local_interest.near({x=2*x+.5,z=2*z+.5},false,64) or false
        if not local_interest then
          for _,at in ipairs(positions) do
            if (at.x-(2*x+.5))^2+(at.z-(2*z+.5))^2<64^2 then nearby=true;break end
          end
        end
        local crop=detail[field.variant]
        if nearby and crop and slope_sample then
          local cx,cz=2*x+.5,2*z+.5
          local function add(key,m,x,z,y)
            local shown=refs[key]~=nil
            local reach,altitude=shown and 23 or 18,shown and 14 or 11
            local best
            for _,at in ipairs(positions) do
              local dy=at.y and math.abs(at.y-y) or 0
              local distance=(at.x-x)^2+(at.z-z)^2
              if dy<altitude and distance<reach^2 then
                local rank=distance+dy*dy
                if not best or rank<best then best=rank end
              end
            end
            if best then crops[#crops+1]={key=key,id=id,name=m,x=x,y=y,z=z,yaw=0,
              rank=best-(shown and 16 or 0)} end
          end
          if field.slope==0 then
            add("crop:"..id,crop[1],cx,cz,field.base+.504)
          else
            -- Reuse four smaller stands anchored to the exact RC1 height
            -- field. Buried stem roots match even diagonal crossfalls.
            -- Keep harvested straw on the flatter lowlands.
            if field.variant~=8 then
              for a=0,3 do
                local dx,dz=a%2-.5,math.floor(a/2)-.5
                add("crop:"..id..":"..a,crop[2],cx+dx,cz+dz,
                  field.base+.504+slope_sample(.5+dx/2,.5+dz/2,field.slope))
              end
            end
          end
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
                active[key]={id=id,name=name(style,rise),x=xa+xb-.5,y=math.min(low,high)+.5,z=za+zb-.5,
                  yaw=yaw,style=style,rise=rise,dx=dx,dz=dz}
              end
            end
          end
        end end
      end
    end
    if local_interest then local_interest.each_tile(Sim,64,visit)
    else for id in pairs(fields) do visit(id) end end
    table.sort(crops,function(a,b) return a.rank==b.rank and a.key<b.key or a.rank<b.rank end)
    -- Bound per-world presentation work even in very large multiplayer maps.
    for i=1,math.min(#crops,64) do active[crops[i].key]=crops[i] end
    return active
  end
  -- Farm perimeters are rendered entities, so attach a few native
  -- collision-only boxes only near pedestrians, never the whole map.
  local function collision(keep)
    if not heights or not api.world then return end
    local walkers={}
    for _,p in ipairs(core.get_connected_players()) do
      local a=api.world.avatar_state(p)
      if a and a.mode=="walk" and not a.leaving then walkers[#walkers+1]=p:get_pos() end
    end
    local choices={}
    if #walkers>0 then
      for key,w in pairs(keep) do
        if w.style then
          local distance=81
          for _,p in ipairs(walkers) do
            distance=math.min(distance,(p.x-w.x)^2+(p.z-w.z)^2)
          end
          if distance<81 then choices[#choices+1]={key=key,record=w,distance=distance} end
        end
      end
      table.sort(choices,function(a,b) return a.distance==b.distance and a.key<b.key or a.distance<b.distance end)
    end
    local current={}
    for i=1,math.min(48,#choices) do
      local key,w=choices[i].key,choices[i].record
      local old=hulls[key]
      if old and old.name==w.name and old.y==w.y and old.yaw==w.yaw then
        current[key]=old;hulls[key]=nil
      else
        w.objects={}
        local n=w.rise==0 and 1 or 4
        local half=1/n
        local h=heights[w.style]
        for j=0,n-1 do
          local u=-1+(j+.5)*2/n
          local at={x=w.x+u*w.dx,y=w.y+w.rise*(j/n),z=w.z+u*w.dz}
          local bounds=w.dx==0 and {.028,half} or {half,.028}
          local ref=core.add_entity(at,name_hull)
          if ref then
            ref:set_properties({collisionbox={-bounds[1],-.11,-bounds[2],bounds[1],h,bounds[2]}})
            w.objects[#w.objects+1]=ref
          end
        end
        current[key]=w
      end
    end
    for _,v in pairs(hulls) do for _,ref in ipairs(v.objects) do
      if ref:get_pos() then ref:remove() end
    end end
    hulls=current
  end
  function F.step(dt,positions)
    elapsed=elapsed+dt
    if elapsed<.35 then return end
    elapsed=0
    local keep=wanted(positions)
    collision(keep)
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
