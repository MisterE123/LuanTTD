-- Presentation only: a translated Blender mesh on the stock office's
-- exact node anchor and orientated with its painted road-facing façade.
return function(core,Sim,frontage,house_deck)
  local V={}
  local refs={}
  local name="luanttd_core:town_office_lift"
  local node_name="luanttd_core:town_stock_04"
  local step=.0475 -- original shaft landings in tools/build_stock_town_art.py
  core.register_entity(name,{
    initial_properties={visual="mesh",mesh="bl_town_stock_04_lift.obj",textures={"bl_scenery_palette.png"},
      visual_size={x=10,y=10,z=10},physical=false, -- authored in node units
      pointable=false,collide_with_objects=false,
      collisionbox={0,0,0,0,0,0},static_save=false},
    static_save=false,
  })
  local function remove(id)
    local record=refs[id]
    if record and record.ref:get_pos() then record.ref:remove() end
    refs[id]=nil
  end
  function V.clear()
    for id in pairs(refs) do remove(id) end
  end
  local function close(viewers,x,y,z)
    for _,p in ipairs(viewers) do
      local q=p:get_pos()
      if q and (q.x-x)^2+(q.y-y)^2+(q.z-z)^2<=64^2 then return true end
    end
    return false
  end
  function V.observe(s,lifts)
    local keep={}
    local viewers=core.get_connected_players()
    for id,position in pairs(lifts or {}) do
      local t=s.tiles[id]
      local h=t and t.house and t.source_house
      local deck=h and h.id==0x04 and h.completed and house_deck(id,t)
      if deck then
        local x,z=Sim.xy(id)
        local dx,dz=frontage.placement(Sim,s,id,t,false,h.render_parcel or t.parcel)
        local pos={x=2*x+dx,y=deck+1,z=2*z+dz}
        if close(viewers,pos.x,pos.y,pos.z) then
          local node=core.get_node_or_nil(pos)
          if node and node.name==node_name then
            keep[id]=true
            local yaw=-(node.param2%4)*math.pi/2
            local target=position*step
            local r=refs[id]
            if not r or not r.ref:get_pos() then
              local ref=core.add_entity({x=pos.x,y=pos.y+target,z=pos.z},name)
              if ref then r={ref=ref,current=target};refs[id]=r end
            end
            if r then
              if r.yaw~=yaw then r.ref:set_yaw(yaw);r.yaw=yaw end
              r.base,r.target=pos,target
            end
          end
        end
      end
    end
    for id in pairs(refs) do if not keep[id] then remove(id) end end
  end
  function V.step(dt)
    for id,r in pairs(refs) do
      local p=r.ref:get_pos()
      local target=r.target
      if p and target then
        local f=math.min(1,dt*14)
        r.current=r.current+(target-r.current)*f
        if math.abs(target-r.current)<.0005 then r.current=target end
        local b=r.base
        local y=b.y+r.current
        if p.x~=b.x or p.z~=b.z or math.abs(p.y-y)>.00025 then
          r.ref:move_to({x=b.x,y=y,z=b.z},false)
        end
      else
        remove(id)
      end
    end
  end
  return V
end
