-- Transient decorative light fitted to the native RC1 roadside lamp.
-- The worker owns lamp placement; this reads painted tiles only.
return function(core,Sim,mount)
  local V={}
  local enter,leave,limit=28,34,56
  local refs,elapsed={},.42
  local function register(name,form)
    local full="luanttd_core:street_light_"..name
    local stem="bl_street_light_"..form
    core.register_entity(full,{initial_properties={visual="mesh",mesh=stem..".obj",textures={stem..".png"},
      visual_size={x=10,y=name=="grade" and 8.4 or 10,z=10},static_save=false,pointable=false,
      physical=false,collide_with_objects=false,shaded=false,glow=-1,backface_culling=false,use_texture_alpha=true}})
    return full
  end
  local cone,grade,pool=register("cone","cone"),register("grade","cone"),register("pool","pool")
  local function remove(key)
    local r=refs[key]
    if r then
      if r.ref:get_pos() then r.ref:remove() end
      if r.pool and r.pool:get_pos() then r.pool:remove() end
      refs[key]=nil
    end
  end
  local function center(x,z,base,slope,sub)
    -- Corresponds to Mesh.lamp in tools/build_roadside_temperate_art.py.
    local u,v=sub[1],sub[2]
    local lift=slope==3 and u/16 or slope==12 and 1-u/16
      or slope==6 and v/16 or slope==9 and 1-v/16 or 0
    local dx,dz=1-u/8,1-v/8
    local d=math.sqrt(dx*dx+dz*dz)
    return {x=2*x-.5+u/8+dx*.268/d,
      y=base+.5+lift+.929,z=2*z-.5+v/8+dz*.268/d}
  end
  function V.step(dt,s,viewers)
    local clock=core.get_timeofday()
    if not viewers[1] or (clock>=.235 and clock<=.765) then
      for key in pairs(refs) do remove(key) end
      elapsed=.42
      return
    end
    elapsed=elapsed+dt
    if elapsed<.42 then return end
    elapsed=0
    local checked,seen,candidates={},{},{}
    for _,p in ipairs(viewers) do
      for z=math.max(1,math.ceil((p.z-leave-1.5)/2)),math.min(Sim.H,math.floor((p.z+leave+.5)/2)) do
        for x=math.max(1,math.ceil((p.x-leave-1.5)/2)),math.min(Sim.W,math.floor((p.x+leave+.5)/2)) do
          local id=Sim.id(x,z)
          local tile=s.tiles[id]
          if tile and tile.roadside=="street_lights" then
            if checked[id]==nil then
              local name,base,slope,points=mount(tile,id)
              local node=name and core.get_node_or_nil({x=2*x+1,y=base+1,z=2*z+1})
              checked[id]=node and node.name==name and {base=base,slope=slope,points=points} or false
            end
            local row=checked[id]
            if row then
              for i,sub in ipairs(row.points) do
                local key=id*2+i
                local q=seen[key]
                if not q then
                  q={key=key,base=row.base,slope=row.slope,at=center(x,z,row.base,row.slope,sub),distance=math.huge}
                  seen[key]=q
                end
                local a=q.at
                q.distance=math.min(q.distance,(a.x-p.x)^2+(a.y-p.y)^2+(a.z-p.z)^2)
              end
            end
          end
        end
      end
    end
    for key,q in pairs(seen) do
      local r=refs[key]
      q.has=r and r.at.x==q.at.x and r.at.y==q.at.y and r.at.z==q.at.z and r.slope==q.slope and r.ref:get_pos()~=nil
      if q.distance<=(q.has and leave or enter)^2 then candidates[#candidates+1]=q end
    end
    table.sort(candidates,function(a,b)
      if a.distance==b.distance then return a.key<b.key end
      return a.distance<b.distance
    end)
    local keep,budget={},limit
    for _,q in ipairs(candidates) do
      local cost=q.slope==0 and 2 or 1
      if budget>=cost then
        budget=budget-cost
        keep[q.key]=true
      end
      if budget==0 then break end
    end
    for key in pairs(refs) do if not keep[key] then remove(key) end end
    for _,q in ipairs(candidates) do
      if keep[q.key] and not q.has then
        remove(q.key)
        local ref=core.add_entity(q.at,q.slope==0 and cone or grade)
        if ref then
          local ground=q.slope==0 and core.add_entity({x=q.at.x,y=q.base+.516,z=q.at.z},pool)
          refs[q.key]={ref=ref,pool=ground,at=q.at,slope=q.slope}
        end
      end
    end
  end
  return V
end
