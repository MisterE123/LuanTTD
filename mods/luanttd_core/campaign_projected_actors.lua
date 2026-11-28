-- Luanti presentation only. Stock poses and membership are supplied by
-- the authority; this module never opens the world or advances a tick.
return function(core,api,motion,models,airframes)
  local A={}
  local active,rail_members={},{}
  local base=(core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local road_art=dofile(base.."/road_stock_media.lua")
  local rotors=dofile(base.."/airport_rotor_view.lua")(core)
  local repair_smoke=dofile(base.."/road_fault_view.lua")(core.add_particle)
  local boats={[204]="stock_mps_oil_tanker",[205]="stock_cs_inc_oil_tanker",[206]="stock_harbor_ferry",[207]="stock_ffp_passenger_ferry",[208]="stock_bakewell_300_hovercraft"}
  local function remove(id)
    local a=active[id]
    rotors.clear(a)
    if a and a.ref:get_pos() then a.ref:remove() end
    active[id]=nil
    repair_smoke.remove(id)
  end
  local function definition(row)
    if row.mode=="road" and models[row.engine] and row.pos then
      local e=row.engine
      return "luanttd_core:vehicle_"..e,road_art.payload(e,models[e],row.loaded),row.yaw,row.pitch
    elseif row.mode=="tram" then
      return "luanttd_core:tram_preview_vehicle",nil,row.yaw,row.pitch
    elseif row.mode=="ship" then
      local name=row.id=="coal" and (row.engine==212 and "stock_bakewell_cargo_ship" or "stock_yate_cargo_ship")
        or boats[row.engine or 206]
      if name then return "luanttd_core:"..name,nil,row.dir end
    elseif row.mode=="air" then
      local art=airframes[row.engine or 215]
      if art then return art.entity,(row.airborne and art.flight or art.mesh),row.dir,row.pitch end
    end
  end
  local collector
  local Guide=dofile(base.."/rail_guideway_profiles.lua")
  local geometry={}
  for id,kind in pairs(Guide.visuals) do geometry[kind]=Guide.by_stock[id] end
  local rail_engines={locomotive=true}
  for _,kind in pairs(dofile(base.."/rail_dispatch_manifest.lua").stock_kind) do rail_engines[kind]=true end
  local passenger_bodies={wagon=true,manley=true,dash=true,mono_passenger=true,maglev_passenger=true}
  function A.render(rows,dt,signals)
    if api.stock_audio then api.stock_audio.observe_vehicles(rows) end
    local visible,viewers={},nil
    repair_smoke.step(dt)
    local function present(key,row,name,mesh,pos,target,pitch,part,sync)
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
      local function differs(a,b)
        return not a or math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z)>.0001
      end
      local snap=part and (sync or v.flip~=nil and part.flip~=v.flip)
      if snap and v.ref.set_pos then v.ref:set_pos(pos)
      elseif differs(v.pos,pos) then v.ref:move_to(pos,true) end
      v.pos=pos
      local rotation=part and part.rotation or {x=pitch or 0,y=motion.nose_yaw(target),z=0}
      if differs(v.rotation,rotation) then v.ref:set_rotation(rotation) end
      v.rotation=rotation
      if row.mode=="air" then rotors.step(v,airframes[row.engine],pos,row.rotor_period,dt) end
      if part then
        v.flip=part.flip
        if part.length and (not v.scale or math.abs(v.scale-part.length)>.002) then
          v.ref:set_properties({visual_size={x=1,y=1,z=part.length}})
          v.scale=part.length
        elseif part.scale and (not v.scale or math.abs(v.scale-part.scale)>.002) then
          v.ref:set_properties({visual_size={x=1,y=part.scale,z=1}})
          v.scale=part.scale
        end
      end
      if row.mode=="road" or row.mode=="air" then
        if row.breakdown_smoke then
          viewers=viewers or core.get_connected_players()
          repair_smoke.draw_active(key,true,pos,rotation.y,viewers)
        else
          repair_smoke.remove(key)
        end
      end
      if api.vehicle_ui then
        if not (part and part.visual_only) then
          api.vehicle_ui.track(row.mode,row.id,pos,v.ref,not part or part.index==1,part and part.body_index or 1)
        end
        if api.vehicle_ui.ride_track and (row.mode=="road" or row.mode=="rail" or row.mode=="air" or
          row.mode=="ship" and row.id=="ferry") then
          api.vehicle_ui.ride_track(row.mode,row.id,v.ref,pos,rotation,{running=row.running,
            passenger=row.passenger or part and passenger_bodies[part.kind],
            engine=part and rail_engines[part.kind],mesh=row.mode=="air" and mesh or nil,
            body=part and part.body_index or 1,travel=part and part.index or 1,
            auxiliary=part and part.visual_only})
        end
      end
    end
    local next_rail={}
    for key,row in pairs(rows) do
      if row.mode=="rail" then
        -- The client interpolates individual entities. When a rear head
        -- emerges, a sector reveals another body, or the order reverses,
        -- interpolate none of this train's bodies for that update rather
        -- than stretching the temporary distance between old and new actors.
        local last=rail_members[key] or {}
        local members,snap={},false
        for _,p in ipairs(row.parts) do
          members[p.body_index]=true
          if not last[p.body_index] then snap=true end
          local prev=active[key..":"..p.body_index]
          if prev and prev.flip~=nil and p.flip~=prev.flip then snap=true end
        end
        for i in pairs(last) do if not members[i] then snap=true end end
        next_rail[key]=members
        for _,p in ipairs(row.parts) do
          local body=key..":"..p.body_index
          local name="luanttd_core:dispatch_"..p.kind
          local c=p.collector
          if c and vector then
            collector=collector or dofile(core.get_modpath("luanttd_core").."/rail_pantograph.lua")
            local move=c.rows and collector.mount(c.rows,c.axis,c.side,p.pos,p.rotation,vector.rotate,.03,.45)
            local heel=move and move.heel or vector.add(p.pos,vector.rotate(collector.heel,p.rotation))
            local scale=move and move.scale_y or c.rows and .03/collector.nominal_extension or 1
            present(body,row,name.."_body",nil,p.pos,nil,nil,p,snap)
            present(body..":collector",row,name.."_collector",nil,heel,nil,nil,
              {visual_only=true,rotation=p.rotation,flip=p.flip,scale=scale,
                index=p.index,body_index=p.body_index,kind=p.kind},snap)
          elseif p.bogies and geometry[p.kind] then
            local profile=geometry[p.kind]
            present(body,row,name.."_body",nil,p.pos,nil,nil,p,snap)
            for j,gear in ipairs(p.bogies) do
              present(body..":bogie:"..j,row,"luanttd_core:dispatch_"..profile.suspension,nil,gear.pos,nil,nil,
                {visual_only=true,rotation=gear.rotation,flip=p.flip,index=p.index,body_index=p.body_index,kind=p.kind},snap)
            end
            local draw=p.drawbar
            if draw then
              present(body..":drawbar",row,"luanttd_core:dispatch_"..profile.coupler,nil,draw.pos,nil,nil,
                {visual_only=true,rotation=draw.rotation,flip=p.flip,length=draw.length,
                  index=p.index,body_index=p.body_index,kind=p.kind},snap)
            end
          else
            present(body,row,name,nil,p.pos,nil,nil,p,snap)
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
    rail_members=next_rail
    for key,lamp in pairs(signals or {}) do
      present("signal:"..key,{},"luanttd_core:dispatch_signal_"..lamp.model,nil,lamp.pos,nil,nil,
        {visual_only=true,rotation=lamp.rotation})
    end
    for key in pairs(active) do if not visible[key] then remove(key) end end
  end
  return A
end
