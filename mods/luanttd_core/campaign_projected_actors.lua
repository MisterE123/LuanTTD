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
  local collector
  function A.render(rows,dt,signals)
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
        if part.scale and (not v.scale or math.abs(v.scale-part.scale)>.002) then
          v.ref:set_properties({visual_size={x=1,y=part.scale,z=1}})
          v.scale=part.scale
        end
      else
        v.ref:move_to(pos,true)
        v.yaw=motion.turn(v.yaw,motion.nose_yaw(target),math.min(.8,dt*7.2))
        v.ref:set_rotation({x=pitch or 0,y=v.yaw,z=0})
      end
      if api.vehicle_ui and not (part and part.visual_only) then
        api.vehicle_ui.track(row.mode,row.id,pos,v.ref,not part or part.index==1)
      end
    end
    for key,row in pairs(rows) do
      if row.mode=="rail" then
        for _,p in ipairs(row.parts) do
          local body=key..":"..p.body_index
          local name="luanttd_core:dispatch_"..p.kind
          local c=p.collector
          if c and vector then
            collector=collector or dofile(core.get_modpath("luanttd_core").."/rail_pantograph.lua")
            local move=c.rows and collector.mount(c.rows,c.axis,c.side,p.pos,p.rotation,vector.rotate,.03,.45)
            local heel=move and move.heel or vector.add(p.pos,vector.rotate(collector.heel,p.rotation))
            local scale=move and move.scale_y or c.rows and .03/collector.nominal_extension or 1
            present(body,row,name.."_body",nil,p.pos,nil,nil,p)
            present(body..":collector",row,name.."_collector",nil,heel,nil,nil,
              {visual_only=true,rotation=p.rotation,flip=p.flip,scale=scale})
          else
            present(body,row,name,nil,p.pos,nil,nil,p)
          end
        end
      elseif row.mode=="rail_pilot" then
        present(key,row,"luanttd_core:vehicle_"..row.model,nil,row.pos,nil,nil,
          {visual_only=true,rotation={x=0,y=row.yaw,z=0}})
      else
        local name,mesh,target,pitch=definition(row)
        if type(target)=="number" then present(key,row,name,mesh,row.pos,target,pitch) end
      end
    end
    for key,lamp in pairs(signals or {}) do
      present("signal:"..key,{},"luanttd_core:dispatch_signal_"..lamp.model,nil,lamp.pos,nil,nil,
        {visual_only=true,rotation=lamp.rotation})
    end
    for key in pairs(active) do if not visible[key] then remove(key) end end
  end
  return A
end
