-- Luanti presentation only. Stock poses and membership are supplied by
-- the authority; this module never opens the world or advances a tick.
return function(core,api,motion,models,airframes)
  local A={}
  local active={}
  local boats={[206]="stock_harbor_ferry",[207]="stock_ffp_passenger_ferry"}
  local function remove(id)
    local a=active[id]
    if a and a.ref:get_pos() then a.ref:remove() end
    active[id]=nil
  end
  local function definition(row)
    if row.mode=="road" and models[row.engine] and row.pos then
      local e=row.engine
      local loaded=(e=="coal_tipper" and row.loaded>0) or
        ((e=="wood_truck" or e=="grain_truck") and row.loaded>=10)
      local special=e=="coal_tipper" or e=="wood_truck" or e=="grain_truck"
      return "luanttd_core:vehicle_"..e,special and "bl_"..models[e]..(loaded and "_loaded" or "")..".obj",
        row.yaw,row.pitch
    elseif row.mode=="tram" then
      return "luanttd_core:tram_preview_vehicle",nil,row.yaw
    elseif row.mode=="ship" then
      local name=row.id=="coal" and "stock_yate_cargo_ship" or boats[row.engine or 206]
      if name then return "luanttd_core:"..name,nil,row.dir end
    elseif row.mode=="air" then
      local art=airframes[row.engine or 215]
      if art then return art.entity,(row.airborne and art.flight or art.mesh),row.dir,row.pitch end
    end
  end
  function A.render(rows,dt)
    local visible={}
    local function present(key,row,name,mesh,pos,target,pitch,part)
      if not name or not pos or core.registered_entities and not core.registered_entities[name] then return end
      local v=active[key]
      if v and (v.name~=name or not v.ref:get_pos()) then remove(key);v=nil end
      if not v then
        local ref=core.add_entity(pos,name)
        if ref then v={ref=ref,name=name};active[key]=v end
      end
      if not v then return end
      visible[key]=true
      if mesh and v.mesh~=mesh then v.ref:set_properties({mesh=mesh});v.mesh=mesh end
      if part then
        if v.flip~=nil and part.flip~=v.flip then v.ref:set_pos(pos)
        else v.ref:move_to(pos,true) end
        v.flip=part.flip
        v.ref:set_rotation(part.rotation)
      else
        v.ref:move_to(pos,true)
        v.yaw=motion.turn(v.yaw,motion.nose_yaw(target),math.min(.8,dt*7.2))
        v.ref:set_rotation({x=pitch or 0,y=v.yaw,z=0})
      end
      if api.vehicle_ui then api.vehicle_ui.track(row.mode,row.id,pos,v.ref,not part or part.index==1) end
    end
    for key,row in pairs(rows) do
      if row.mode=="rail" then
        for _,p in ipairs(row.parts) do
          present(key..":"..p.body_index,row,"luanttd_core:dispatch_"..p.kind,nil,p.pos,nil,nil,p)
        end
      else
        local name,mesh,target,pitch=definition(row)
        if type(target)=="number" then present(key,row,name,mesh,row.pos,target,pitch) end
      end
    end
    for key in pairs(active) do if not visible[key] then remove(key) end end
  end
  return A
end
