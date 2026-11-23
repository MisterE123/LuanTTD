-- Seated sightseeing is presentation only; never change a worker vehicle,
-- sim time, camera yaw after boarding, or anyone else's vehicle visibility.
return function(core,api,path)
  local R={}
  local rooms,tracked,riders,settling={},{},{},{}
  local masks=setmetatable({},{__mode="k"})
  local now,roster=0,{}
  local anchor_name="luanttd_core:seated_camera"
  local names={"bus_interior","train_interior","train_cab"}
  -- Standard ride interiors are authored in node units with +Z facing out
  -- the windscreen. Stock exteriors are authored nose -Z. The limited
  -- body envelope is enforced for every private variant.
  local interiors={
    bus_interior={eye={x=-.020,y=.117,z=-.042},floor=.071},
    train_interior={eye={x=-.091,y=.207,z=-.080},floor=.202,depth=.80},
    train_cab={eye={x=.075,y=.228,z=-.228},floor=.247},
  }
  local function alive(o) return o and o:get_pos()~=nil end
  local function copy(x)
    if not x then return end
    local t={};for k,v in pairs(x) do t[k]=v end;return t
  end
  local axes,zero={x=0,y=0,z=1},{x=0,y=0,z=0}
  local degrees=180/math.pi
  local function diff(a,b)
    return not a or math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z)>.0001
  end
  local function name(p) return p:get_player_name() end
  local function key(mode,id) return mode..":"..id end
  local function register(entity,props)
    core.register_entity(entity,{initial_properties=props})
  end
  local function assets(folder)
    local files={}
    if core.get_dir_list then
      for _,file in ipairs(core.get_dir_list(path.."/"..folder,false)) do files[file]=true end
    end
    return files
  end
  local models,textures=assets("models"),assets("textures")
  for _,design in ipairs(names) do
    local stem="bl_ride_"..design
    if design=="bus_interior" then stem="bl_ride_bus_interior"
    elseif design=="train_interior" then stem="bl_ride_train_interior"
    else stem="bl_ride_train_cab" end
    local mesh,texture=stem..".obj",stem..".png"
    if models[mesh] and textures[texture] then
      local id="luanttd_core:ride_"..design
      register(id,{physical=false,collide_with_objects=false,pointable=false,static_save=false,
        visual="mesh",mesh=mesh,textures={texture},backface_culling=true,shaded=true,
        visual_size={x=1,y=1,z=interiors[design].depth or 1}})
      rooms[design]=id
    end
  end
  if next(rooms) then
    register(anchor_name,{physical=false,collide_with_objects=false,pointable=false,
      -- An invisible parent also hides child meshes on native 5.10.
      -- Use a genuinely transparent sprite to keep both on one transform.
      static_save=false,is_visible=true,visual="sprite",textures={"bl_sightseeing_hidden_player.png"}})
  end
  function R.capable(kind,mode)
    if mode=="cab" then return kind=="rail" and rooms.train_cab~=nil end
    return kind=="road" and rooms.bus_interior~=nil or kind=="rail" and rooms.train_interior~=nil
  end

  local function rebuild_mask(ref,m)
    if not alive(ref) then masks[ref]=nil;return end
    if not next(m.hidden) then
      ref:set_observers(m.original and copy(m.original) or nil)
      masks[ref]=nil;return
    end
    local users={}
    for n in pairs(m.original or roster) do if not m.hidden[n] then users[n]=true end end
    ref:set_observers(users)
  end
  local function hide(ref,n)
    if not alive(ref) or not ref.set_observers or not ref.get_observers then return false end
    local m=masks[ref]
    if not m then
      m={original=copy(ref:get_observers()),hidden={}}
      masks[ref]=m
    end
    if m.hidden[n] then return true end
    m.hidden[n]=true;rebuild_mask(ref,m)
    return true
  end
  local function reveal(ref,n)
    local m=masks[ref]
    if not m then return end
    m.hidden[n]=nil;rebuild_mask(ref,m)
  end
  local function restore_bodies(state,n)
    for ref in pairs(state.hidden) do reveal(ref,n) end
    state.hidden={}
  end
  local function remove_interior(state,n)
    if alive(state.interior) then state.interior:remove() end
    state.interior,state.interior_pos,state.rotation=nil,nil,nil
    restore_bodies(state,n)
  end

  function R.track(kind,id,ref,pos,rotation,meta)
    if (kind~="road" and kind~="rail") or not id or not alive(ref) or not meta or not rotation then return end
    local k=key(kind,id)
    local list=tracked[k]
    if not list then list={};tracked[k]=list end
    local body=meta.body or 1
    local b=list[body]
    if not b then b={};list[body]=b end
    if meta.auxiliary then
      b.auxiliary=ref
    else
      b.ref,b.pos,b.rotation,b.meta,b.at=ref,pos,rotation,meta,now
    end
  end
  local function live(b)
    return b and b.at and now-b.at<.55 and alive(b.ref)
  end
  local function chosen(kind,id,body,mode)
    local list=tracked[key(kind,id)]
    if not list then return nil,"Aim at a nearby running bus or train first." end
    if kind=="road" then
      local b=list[1]
      if live(b) and b.meta.passenger and b.meta.running then return b,1,"bus_interior" end
      return nil,"Choose a running passenger bus."
    end
    local function okay(b)
      return live(b) and b.meta.running and (mode=="cab" and b.meta.engine or mode~="cab" and b.meta.passenger)
    end
    if body and okay(list[body]) then return list[body],body,mode=="cab" and "train_cab" or "train_interior" end
    local i,closest,score
    for which,b in pairs(list) do
      if okay(b) then
        local d=mode=="cab" and b.meta.travel or body and math.abs(body-which) or which
        if not closest or d<score then i,closest,score=which,b,d end
      end
    end
    if closest then return closest,i,mode=="cab" and "train_cab" or "train_interior" end
    return nil,mode=="cab" and "Choose a running train with a visible cab." or "Choose a running train with passenger seats."
  end

  local function orientation(b)
    return {x=-b.rotation.x,y=(b.rotation.y+math.pi)%(2*math.pi),z=-b.rotation.z}
  end
  local function transform(state,b)
    local d=interiors[state.design]
    local r=orientation(b)
    -- Keep the enlarged coach between the coupled exterior cars.
    -- Compress depth only; the lateral camera clipping clearance remains.
    local point=vector.rotate({x=d.eye.x,y=d.eye.y+d.floor,z=d.eye.z*(d.depth or 1)},r)
    local floor=vector.rotate({x=0,y=d.floor,z=0},r)
    local feet={x=b.pos.x+point.x,y=b.pos.y+point.y-state.eye_height,z=b.pos.z+point.z}
    return feet,r,{x=b.pos.x+floor.x,y=b.pos.y+floor.y,z=b.pos.z+floor.z}
  end
  local function maintain(state,b,n)
    local feet,r,origin=transform(state,b)
    if not alive(state.interior) then
      state.interior=core.add_entity(origin,rooms[state.design])
      if not alive(state.interior) or not state.interior.set_observers then return false end
      state.interior:set_observers({[n]=true})
      state.interior_pos,state.rotation=nil,nil
    end
    if not hide(b.ref,n) then return false end
    local wanted={[b.ref]=true}
    local bodies=tracked[key(state.kind,state.id)]
    for _,part in pairs(bodies) do
      -- This is the selected train, not just one ObjectRef. A coupled
      -- coach can interpenetrate the private cab during a reversal.
      if live(part) then
        wanted[part.ref]=true
        if alive(part.auxiliary) then wanted[part.auxiliary]=true end
      end
    end
    for ref in pairs(wanted) do if hide(ref,n) then state.hidden[ref]=true end end
    for ref in pairs(state.hidden) do
      if not wanted[ref] then reveal(ref,n);state.hidden[ref]=nil end
    end
    if diff(state.feet,feet) then state.anchor:move_to(feet,true);state.feet=feet end
    -- Share the actual client scene-node transform, not just timestamps:
    -- independent ObjectRefs interpolate different arrival sequences
    -- under load. A tiny cabin can otherwise slide past its camera eye.
    local rel={x=10*(origin.x-feet.x),y=10*(origin.y-feet.y),z=10*(origin.z-feet.z)}
    if diff(state.interior_pos,rel) or diff(state.rotation,r) then
      state.interior:set_attach(state.anchor,"",rel,{x=-degrees*r.x,y=-degrees*r.y,z=-degrees*r.z},true)
      state.interior_pos,state.rotation=rel,r
    end
    return true
  end

  local function angular_diff(a,b) return math.abs((a-b+math.pi)%(2*math.pi)-math.pi) end
  local function restore_view(p,state)
    -- Set wanted look before the absolute move packet, which carries
    -- camera heading as well as position on native clients.
    p:set_look_horizontal(state.yaw);p:set_look_vertical(state.pitch)
    p:set_pos(state.return_pos)
  end
  function R.active(p) return riders[name(p)]~=nil end
  function R.exit(p,why)
    local n=name(p)
    local state=riders[n]
    if not state then return false end
    local last_yaw,last_pitch=p:get_look_horizontal(),p:get_look_vertical()
    riders[n]=nil
    remove_interior(state,n)
    if p:get_attach()==state.anchor then p:set_detach() end
    if alive(state.anchor) then state.anchor:remove() end
    p:set_eye_offset(state.eye_a,state.eye_b,state.eye_c)
    p:set_inventory_formspec(state.inventory)
    restore_view(p,state)
    if core.after and core.get_player_by_name then
      settling[n]=state
      core.after(.15,function()
        if settling[n]~=state then return end
        settling[n]=nil
        local live=core.get_player_by_name(n)
        if live~=p or riders[n] or p:get_attach() then return end
        local pos=p:get_pos()
        if not pos or math.abs(pos.x-state.return_pos.x)+math.abs(pos.y-state.return_pos.y)+
            math.abs(pos.z-state.return_pos.z)>.22 then return end
        local yaw,pitch=p:get_look_horizontal(),p:get_look_vertical()
        -- A recent look packet generated while still seated can arrive
        -- after detach. Repair that value only, not later mouse input.
        if angular_diff(yaw,last_yaw)<.08 and math.abs(pitch-last_pitch)<.08 and
            (angular_diff(yaw,state.yaw)>.035 or math.abs(pitch-state.pitch)>.035) then
          restore_view(p,state)
        end
      end)
    end
    if state.hud then p:hud_remove(state.hud) end
    if api.world and api.world.follow_hud then api.world.follow_hud(p,false) end
    if state.flags then p:hud_set_flags(state.flags) end
    if api.vehicle_status then api.vehicle_status(p,why or "Returned to the builder camera.") end
    return true
  end
  function R.enter(p,mode,target)
    local n=name(p)
    if riders[n] then return R.exit(p) end
    if not target or not target.id then return false,mode=="cab" and "Aim at a running train or select it first." or "Aim at a running bus or passenger train." end
    if not R.capable(target.kind,mode) then
      return false,mode=="cab" and "Choose a running train for the cab view." or "Choose a passenger bus or train."
    end
    if p:get_attach() then return false,"Return to the builder camera before boarding." end
    if api.world and api.world.may_board then
      local ok,why=api.world.may_board(p)
      if not ok then return false,why end
    end
    local b,index,design=chosen(target.kind,target.id,target.body,mode)
    if not b then return false,index end
    if not b.ref.set_observers or not b.ref.get_observers then return false,"This Luanti server does not support private vehicle views." end
    local state={kind=target.kind,id=target.id,body=index,design=design,hidden={},
      return_pos=p:get_pos(),yaw=p:get_look_horizontal(),pitch=p:get_look_vertical(),
      eye_height=p:get_properties().eye_height or 1.625,inventory=p:get_inventory_formspec(),
      flags=p.hud_get_flags and p:hud_get_flags()}
    state.eye_a,state.eye_b,state.eye_c=p:get_eye_offset()
    local feet,r=transform(state,b)
    state.anchor=core.add_entity(feet,anchor_name)
    if not alive(state.anchor) or not state.anchor.set_observers then
      if alive(state.anchor) then state.anchor:remove() end
      return false,"Could not create a private seat view."
    end
    state.anchor:set_observers({[n]=true})
    if not maintain(state,b,n) then
      remove_interior(state,n)
      state.anchor:remove()
      return false,"Could not create the vehicle cabin."
    end
    riders[n]=state;settling[n]=nil
    local keys=p:get_player_control()
    state.right,state.aux=keys.place or keys.RMB,keys.aux1
    p:set_eye_offset()
    p:set_attach(state.anchor,"",zero,zero,false)
    -- Keep an unrotated attachment: the cam moves along with the seat
    -- but neither a turn nor key input changes the player's look direction.
    local forward=vector.rotate(axes,r)
    p:set_look_horizontal(math.atan2(-forward.x,forward.z))
    p:set_look_vertical(math.atan2(-forward.y,math.sqrt(forward.x^2+forward.z^2)))
    if api.world and api.world.follow_hud then api.world.follow_hud(p,true) end
    state.hud=p:hud_add({type="text",position={x=.5,y=.88},alignment={x=0,y=0},z_index=110,
      text=(mode=="cab" and "Driver's seat" or "Window seat").."  ·  E / right-click to leave  ·  Inventory: Leave ride",number=0xffedbe})
    p:set_inventory_formspec("formspec_version[7]size[7,2.5]bgcolor[#152334;true]"..
      "label[.5,.55;Seated sightseeing]button_exit[.5,1.30;6,.68;luanttd_leave_ride;Leave ride]")
    return true
  end
  function R.controls(p,k)
    local state=riders[name(p)]
    if not state then return false end
    local right=k.place or k.RMB
    if (right and not state.right) or (k.aux1 and not state.aux) then return R.exit(p) end
    state.right,state.aux=right,k.aux1
    return true
  end
  function R.step(dt,players)
    now=now+dt
    local incoming,changed={},false
    for _,p in ipairs(players) do
      local n=name(p);incoming[n]=true
      if not roster[n] then changed=true end
    end
    for n in pairs(roster) do if not incoming[n] then changed=true;break end end
    roster=incoming
    if changed then for ref,m in pairs(masks) do rebuild_mask(ref,m) end end
    for _,p in ipairs(players) do
      local n=name(p)
      local state=riders[n]
      if state then
        local list=tracked[key(state.kind,state.id)]
        local b=list and list[state.body]
        if not alive(state.anchor) or p:get_attach()~=state.anchor then R.exit(p)
        elseif live(b) then
          state.missing=nil
          if not maintain(state,b,n) then R.exit(p,"The vehicle's seat view is no longer available.") end
        else
          -- A worker/viewport hitch must not strip the private room or
          -- throw the rider out. Freeze at the last received pose, without
          -- advancing the vehicle locally; retry until the bounded grace
          -- expires or the physical body returns (possibly with a new ref).
          state.missing=state.missing or now
          if now-state.missing>3 then R.exit(p,"The vehicle is no longer visible. Returned to the builder camera.") end
        end
      end
    end
    for k,list in pairs(tracked) do
      for body,b in pairs(list) do
        if not b.at or now-b.at>1.5 or not alive(b.ref) then list[body]=nil end
      end
      if not next(list) then tracked[k]=nil end
    end
  end
  return R
end
