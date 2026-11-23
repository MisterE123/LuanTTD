-- A spectator-builder camera. The world is the interaction surface; forms
-- are small contextual menus. Simulation remains authoritative and independent.
return function(api,ui)
  local Sim,S=api.Sim,api.s
  local W={}
  local hud={}
  local controls={}
  local slots={
    {"inspect","Inspect / 1","bl_sel.png"},
    {"road","Lay road / 2","bl_hot_road.png"},
    {"rail","Lay track / 3","bl_hot_rail.png"},
    {"road_station","Road stop / 4","bl_hot_stop.png"},
    {"rail_station","Rail station / 5","bl_hot_station.png"},
    {"custom","Custom tool / 6 (choose in inventory)","bl_hot_tools.png"},
    {"company","Company sheets / 7","bl_hot_company.png"},
    {"jump","Jump map / 8","bl_hot_map.png"},
  }
  local H=api.road_first and dofile(core.get_modpath("luanttd_core").."/hotbar.lua")
  local menu_size=H and H.size or #slots
  if H and api.structure_tools then H.enable_structures(api.bridge_picker ~= nil) end
  if H and api.tram_tools then H.enable_trams() end
  if H and api.ship_tools then H.enable_ships() end
  if H and api.airport_tools then H.enable_airfields(S.air_owned_preview) end
  if H and api.rail_build_tools then H.enable_railworks(api.rail_span_tools,api.crossing_tools,api.bridge_picker ~= nil) end
  if H and api.rail_build_tools then H.enable_rail_waypoints() end
  if H and api.electric_tools then H.enable_electric_rail() end
  if H and api.rail_owned_pair_tools then H.enable_rail_pair() end
  if H and api.rail_block_tools then H.enable_rail_block() end
  if H and api.freight_tools then H.enable_freight() end
  if H and api.oneway_tools then H.enable_oneway() end
  if H and api.road_bay_tools then H.enable_bay_termini() end
  local function entries(state)
    return H and state.visible_menu or slots
  end
  local function populate(p,state)
    if H then
      local visible,map
      if state.order_menu then visible,map=state.order_menu,state.order_layout
      else visible,map=H.compact(H.menus[H.active(state.menus)]) end
      state.visible_menu,state.hotbar_layout=visible,map
      state.layout_changed_at=core.get_us_time()
      -- Luanti retains/clamps the old physical slot when a row is
      -- replaced. Entering a menu must never implicitly arm demolition.
      local i=math.min(p:get_wield_index(),#visible)
      state.inherited_clear=visible[i] and visible[i][1]=="clear" and i or nil
      state.clear_arming_press=nil
    end
    local inv=p:get_inventory()
    local menu=entries(state)
    for i=1,menu_size do
      inv:set_stack("main",i,ItemStack(menu[i] and ("luanttd_core:menu_"..(H and menu[i][1] or i)) or ""))
    end
    local count=#menu
    if state.hotbar_count~=count then
      p:hud_set_hotbar_itemcount(count)
      state.hotbar_count=count
    end
  end
  function W.hotbar_layout(p)
    local state=controls[p:get_player_name()]
    if not state then return {} end
    local map={}
    if H then
      for i,logical in ipairs(state.hotbar_layout or {}) do map[i]=logical end
    else
      for i=1,menu_size do map[i]=i end
    end
    return map
  end
  local function wield_matches(item,entry)
    if not entry then return false end
    local name=type(item)=="string" and item or item and item:get_name()
    return name=="luanttd_core:menu_"..entry[1]
  end
  function W.menu(p)
    local state=controls[p:get_player_name()]
    return state and state.order_menu and "vehicle_orders" or H and state and H.active(state.menus) or "legacy"
  end
  function W.begin_order_selection(p,mode,label)
    local state=controls[p:get_player_name()]
    if not state then return end
    state.clicked=core.get_us_time() -- do not reuse the button press that closed the form
    state.demolishing,state.build_drag=nil,nil
    state.order_mode=mode or "road"
    if H then
      state.order_menu,state.order_done,state.order_layout,state.order_cancel=H.order_overlay(p:get_wield_index(),state.order_mode,label)
      populate(p,state)
    end
  end
  function W.end_order_selection(p)
    local state=controls[p:get_player_name()]
    if not state then return end
    state.order_mode=nil
    if state.order_menu then
      state.order_menu,state.order_done,state.order_layout,state.order_cancel=nil,nil,nil,nil
      populate(p,state)
    end
  end
  function W.home_menu(p)
    local state=controls[p:get_player_name()]
    if H and state and not state.order_menu then
      state.menus={"home"}
      ui.select_tool(p,"inspect")
      populate(p,state)
    end
  end
  function W.has_menu(key) return H and H.path(key)~=nil end
  function W.menu_title(key) return H and H.menus[key] and H.menus[key].title end
  function W.go_menu(p,key)
    local state=controls[p:get_player_name()]
    local path=H and H.path(key)
    if not state or not path then return false,"This hotbar section isn't mounted." end
    if state.order_menu then return false,"Finish selecting vehicle stops before opening a different workbench." end
    if api.owned_rail_ui and api.owned_rail_ui.active(p) then
      return false,"Finish or right-click to cancel the current rail orders before opening a different workbench."
    end
    state.menus=path
    ui.select_tool(p,"inspect")
    populate(p,state)
    W.hud(p)
    return true
  end
  if H then
    core.register_chatcommand("workbenches",{
      description="Open the LuanTTD Transport & World Guide index",
      func=function(name)
        local p=core.get_player_by_name(name)
        if not p or not controls[name] then return false,"Join the campaign to open the transport guide." end
        return ui.open_workbenches(p)
      end,
    })
  end
  local function drag_kind(tool)
    if ui.road_gesture and ui.road_gesture(tool) then return "autoroad" end
    if ui.rail_gesture and ui.rail_gesture(tool) then return "autorail" end
    if ui.station_gesture and ui.station_gesture(tool) then return "station" end
  end
  local function cancel_drag(p,state)
    local drag=state.build_drag
    state.build_drag=nil
    state.build_drag_cancelled=true
    ui["cancel_"..drag.kind](p)
  end
  local function clear_inherited(p,state)
    local i=p:get_wield_index()
    if state.inherited_clear and i~=state.inherited_clear and entries(state)[i]
        and core.get_us_time()-state.layout_changed_at>=170000 then
      state.inherited_clear=nil -- a genuine change away from the carried selection
    end
    return state.inherited_clear==i
  end
  local function activate(item,p,menu,control_press)
    if not p or not p:is_player() then return item end
    local n=p:get_player_name()
    local state=controls[n]
    if not state then return item end
    if state.order_mode then
      local now=core.get_us_time()
      -- A tool click and global click telemetry can describe the same press.
      if state.clicked and now-state.clicked<170000 then return item end
      local selected=entries(state)[p:get_wield_index()]
      if H and not menu and not wield_matches(item,selected) then return item end
      state.clicked=now
      if menu then state.right_at=now end
      W.click(p,menu)
      return p:get_wielded_item()
    end
    if menu and H then
      local now=core.get_us_time()
      if state.right_at and now-state.right_at<170000 then return item end
      state.right_at=now
      if state.build_drag then
        cancel_drag(p,state)
        W.hud(p)
        return item
      end
      if state.demolishing then
        state.demolishing=nil
        state.demolition_cancelled=true
        ui.cancel_demolition(p)
        W.hud(p)
        return item
      end
    end
    if not menu then
      local now=core.get_us_time()
      if state.clicked and now-state.clicked<170000 then return item end
      local index=p:get_wield_index()
      local menu=entries(state)
      local entry=menu[index]
      local key=entry and entry[1]
      if H and ((state.layout_changed_at and now-state.layout_changed_at<170000)
          or not wield_matches(item,entry)) then return item end
      local inherited=H and clear_inherited(p,state)
      if key=="clear" and state.clear_arming_press then return item end
      if key=="clear" and inherited then
        -- Arm only from the authoritative physical press edge. The
        -- engine's duplicate item callback cannot start the drag.
        if control_press then
          state.inherited_clear=nil
          state.clear_arming_press=true
          state.clicked=now
          ui.status(p,"Bulldoze armed. Click or drag again to clear.")
          W.hud(p)
        end
        return item
      end
      state.clicked=now
      if H then
        if key=="teleport_tile" then
          local tile,hit=W.target(p)
          ui.teleport_tile(p,tile,hit)
          W.hud(p)
          return item
        end
        local action,value=H.choose(state.menus,state.hotbar_layout[index])
        if action=="menu" then
          ui.select_tool(p,"inspect")
          populate(p,state)
          W.hud(p)
          return p:get_wielded_item()
        elseif not action then return item end
        key=value
        if key=="bend" or key=="cancel" then ui.road_action(p,key);return item end
        if key=="tram_rotate" then ui.rotate_tram(p);return item end
        if key=="tram_clear" then ui.clear_tram_run(p);W.hud(p);return item end
        if key=="ship_rotate" then ui.rotate_ship(p);return item end
        if key=="rail_rotate" then ui.rotate_rail(p);return item end
        if key=="rail_coal_flip" then ui.flip_rail_coal(p);return item end
        if key=="rail_order_pair" and api.owned_rail_ui then
          if api.owned_rail_ui.begin_pair(p) then
            -- A single physical press may also be observed by globalstep.
            -- Opening the workbench must never silently pick the depot
            -- already under the crosshair on that same press.
            W.begin_order_selection(p,"rail","Paired train orders")
          end
          W.hud(p);return item
        end
        if key=="rail_piece_remove" then ui.toggle_rail_remove(p);return item end
        if key=="rail_clear_run" then ui.clear_rail_run(p);return item end
        if key=="airfield_clear" then ui.clear_airfield_run(p);return item end
        if key=="ship_clear" then ui.clear_ship_run(p);return item end
        if key=="pause" or key=="normal_speed" or key=="fast" then ui.speed(p,key);return item end
      end
      if key=="company" then ui.open_company(p);return item end
      if key=="jump" then ui.open_jump(p);return item end
      if key=="finance" then ui.open_finance(p);return item end
      if key=="controls" then ui.open_controls(p);return item end
      if key=="workbench_index" then ui.open_workbenches(p);return item end
      if key=="custom" and not state.custom then ui.context(p,W.target(p));return item end
      local tool=key=="custom" and state.custom or key
      if tool then ui.select_tool(p,tool) end
      local label=H and ui.begin_fixed_route and ui.begin_fixed_route(p,tool)
      if label then
        W.begin_order_selection(p,"fixed",label)
        W.hud(p)
        return p:get_wielded_item()
      end
      local kind=H and drag_kind(tool)
      if kind then
        local at,hit=W.target(p)
        if at and not state.build_drag and not state.build_drag_cancelled and ui["begin_"..kind](p,at,hit) then
          state.build_drag={tool=tool,kind=kind}
        end
        W.hud(p)
        return item
      end
      if H and S.corner_grid and tool=="clear" and ui.begin_demolition then
        if not state.demolishing and not state.demolition_cancelled then
          local at=W.target(p)
          if at then state.demolishing=ui.begin_demolition(p,at) end
        end
        W.hud(p)
        return item
      end
    end
    W.click(p,menu)
    return item
  end
  local function register_item(key,slot)
    core.register_tool("luanttd_core:menu_"..key,{
      description=slot[2],inventory_image=slot[3],wield_image=slot[3],range=60,
      on_use=function(item,p) return activate(item,p,false) end,
      on_place=function(item,p) return activate(item,p,true) end,
      on_secondary_use=function(item,p) return activate(item,p,true) end,
      on_drop=function(stack) return stack end,
    })
  end
  local function mount_menu(feature)
    if not H then return end
    H[feature]()
    for _,menu in pairs(H.menus) do
      for i=1,menu_size do
        local item=menu[i]
        if item and not core.registered_items["luanttd_core:menu_"..item[1]] then
          register_item(item[1],item)
        end
      end
    end
  end
  function W.enable_rail_coal() mount_menu("enable_rail_coal") end
  function W.enable_rail_goods() mount_menu("enable_rail_goods") end
  function W.enable_rail_oil() mount_menu("enable_rail_oil") end
  function W.enable_ship_coal() mount_menu("enable_ship_coal") end
  if H then
    for _,tool in ipairs({H.order_pick,H.order_done,H.order_dispatch,H.order_cancel,H.teleport_tile}) do register_item(tool[1],tool) end
    local seen={}
    for _,menu in pairs(H.menus) do for i=1,menu_size do
      local item=menu[i]
      if item and not seen[item[1]] then
        seen[item[1]]=true
        register_item(item[1],item)
      end
    end end
  else
    for index,slot in ipairs(slots) do register_item(index,slot) end
  end
  core.register_allow_player_inventory_action(function() return 0 end)
  function W.custom(p,id)
    local state=controls[p:get_player_name()]
    if state then state.custom=id end
  end
  local walk_speed,crouch_speed,flight_boost=2,5.9,2.25
  local function update_flight_speed(p,state,keys)
    -- Aux1 is E by default. Observe it without consuming it: construction
    -- also reads this key to choose diagonal selections.
    local boosted=keys.aux1==true
    if state.sprinting~=boosted then
      local factor=boosted and flight_boost or 1
      p:set_physics_override({speed_walk=walk_speed*factor,speed_crouch=crouch_speed*factor})
      state.sprinting=boosted
    end
  end
  local function vertical_flight(p,state,dt,keys)
    -- The client owns direction, view and horizontal flight. Never send an
    -- absolute player move during continuous flight: in 5.10 that packet
    -- also installs the server's (older) yaw and pitch on the client.
    local climb=(keys.jump and 1 or 0)-(keys.sneak and 1 or 0)
    state.lift_elapsed=(state.lift_elapsed or .25)+dt
    local boosted=state.sprinting and climb~=0
    if state.lift_elapsed<.21 and climb==state.lift_input and boosted==state.lift_boost then return end
    -- Let a prior velocity request reach the client and return in its
    -- position report before another correction. A released key still
    -- stops promptly on the next physics report.
    if state.lift_elapsed<.12 then return end
    state.lift_elapsed=0
    state.lift_input=climb
    state.lift_boost=boosted
    local pos=p:get_pos()
    local tile=Sim.id(math.floor((pos.x+.5)/2),math.floor((pos.z+.5)/2))
    local ground=tile and S.tiles[tile].h or 0
    if api.terrain and tile and api.render.uses_slope(tile) then
      ground=api.render.surface(tile,pos.x,pos.z)-.5
    end
    local desired=climb*6.3*(boosted and flight_boost or 1)
    if climb<0 then desired=-math.min(-desired,math.max(0,pos.y-ground-2.30)*3.7) end
    if climb>0 then
      local ceiling=api.generated_world and api.render and math.max(66,api.render.max_target_level()+15) or 66
      desired=math.min(desired,math.max(0,ceiling-pos.y)*3.7)
    end
    local measured=p:get_velocity().y
    if math.abs(desired-measured)>.035 then p:add_velocity({x=0,y=desired-measured,z=0}) end
  end
  function W.target(p)
    local pos=p:get_pos()
    local eye=p:get_properties().eye_height or 1.625
    local ray=p:get_look_dir()
    if ray.y>=-0.025 then return nil end
    local x0,y0,z0=pos.x,pos.y+eye,pos.z
    -- Tile edges align at half nodes. Test each rendered surface elevation
    -- and take the closest actual intersection, including hill/terminal tops.
    local best,tbest
    if api.terrain then
      best,tbest=api.terrain.pick({x=x0,y=y0,z=z0},ray,api.render.uses_slope,90,api.render.surface)
    end
    local ceiling=api.generated_world and api.render.max_target_level and api.render.max_target_level() or 5
    for level=ceiling,0,-1 do
      local t=(level+.5-y0)/ray.y
      if t>=0 and t<=90 and (not tbest or t<tbest) then
        local tile=Sim.id(math.floor((x0+t*ray.x+.5)/2),math.floor((z0+t*ray.z+.5)/2))
        local a=tile and S.tiles[tile]
        if a and not a.stock_void and not api.render.uses_slope(tile) then
          local top=(a.site or a.house or a.station or a.build=="canal" or a.wood) and 1 or a.h
          if a.signal then top=top+1 end
          if top==level then best,tbest=tile,t end
        end
      end
    end
    if best and tbest then
      return best,{x=x0+tbest*ray.x,y=y0+tbest*ray.y,z=z0+tbest*ray.z}
    end
    return best
  end
  function W.click(p,menu)
    local n=p:get_player_name()
    local tile=W.target(p)
    local state=controls[n]
    if state and state.order_mode then
      local selected=entries(state)[p:get_wield_index()]
      local key=selected and selected[1]
      if state.order_mode=="road" then
        if menu or key=="order_done" then ui.finish_order_pick(p)
        else ui.choose_order_stop(p,tile) end
      elseif state.order_mode=="rail" then
        local rail=api.owned_rail_ui
        if menu or key=="order_cancel" then rail.cancel(p)
        elseif key=="order_dispatch" then rail.confirm(p)
        else rail.pick(p,tile,not not H) end
        if not rail.active(p) then W.end_order_selection(p) end
      elseif state.order_mode=="fixed" then
        if menu or key=="order_cancel" then ui.cancel_fixed_route(p)
        elseif key=="order_dispatch" then ui.confirm_fixed_route(p)
        elseif tile then ui.build_world(p,tile) end
        if not ui.fixed_route_active(p) then W.end_order_selection(p) end
      end
      W.hud(p)
      return
    end
    if menu then
      local cancel=ui.cancel_build_selection or ui.cancel_rail_selection
      if cancel and cancel(p) then W.hud(p);return end
      local state=controls[n]
      local entry=state and entries(state)[p:get_wield_index()]
      if entry and entry[1]=="teleport_tile" then ui.inspect(p,tile);return end
      if entry and ui.station_gesture and ui.station_gesture(entry[1]) then ui.open_station_layout(p);return end
      ui.context(p,tile);return
    end
    if tile then ui.build_world(p,tile)
    else ui.inspect(p,nil) end
    W.hud(p,0)
  end
  function W.spawn(p)
    local n=p:get_player_name()
    controls[n]={elapsed=0,menus={"home"},sprinting=false}
    if api.generated_world and S.sites[1] then
      local id=S.sites[1].tile
      local x,z=Sim.xy(id)
      p:set_pos({x=2*x+.5,y=S.tiles[id].h+15,z=2*z-7})
      p:set_look_horizontal(0);p:set_look_vertical(1.05)
    elseif api.road_first then
      p:set_pos({x=27.5,y=17,z=13})
      p:set_look_horizontal(0);p:set_look_vertical(1.05)
    else
      p:set_pos({x=18.5,y=13,z=10})
      p:set_look_horizontal(0);p:set_look_vertical(1.05)
    end
    p:set_physics_override({
      gravity=0,jump=0,sneak=false,
      speed_walk=walk_speed,speed_crouch=crouch_speed,
      acceleration_air=6,acceleration_default=3,
    })
    p:hud_set_flags({hotbar=true,healthbar=false,crosshair=true,wielditem=false,breathbar=false,minimap=false,minimap_radar=false})
    local inv=p:get_inventory()
    inv:set_size("main",menu_size)
    populate(p,controls[n])
    ui.inventory(p)
    W.hud(p,0)
  end
  function W.leave(n)
    hud[n]=nil;controls[n]=nil;api.render.leave(n)
    if api.selector then api.selector.leave(n) end
  end
  function W.hud(p)
    local n=p:get_player_name()
    local t,hit=W.target(p)
    local state=controls[n]
    if not state then return end
    local menu=entries(state)
    local slot=menu[p:get_wield_index()]
    local key=slot and slot[1]
    local tool=key=="custom" and state and state.custom or key
    local picking=state.order_mode~=nil
    local road_picking=state.order_mode=="road"
    local world_tool=not picking and ui.is_world_tool(tool)
    if world_tool then ui.select_tool(p,tool) end
    local desc,status,ids,valid=ui.world_status(p,t,not H or world_tool or picking,hit)
    if api.road_first and state then
      local now=core.get_us_time()
      if state.last_status~=status then state.last_status=status;state.last_status_at=now end
      if not picking and now-(state.last_status_at or now)>6500000 and ui.phase(p)~=7 then status="" end
    end
    local shade="inspect"
    local anchor=ui.anchor(p)
    if ids then shade=valid and tool~="clear" and "valid" or "invalid" end
    if api.selector then
      local rail=world_tool and ui.rail_overlay and ui.rail_overlay(p,t)
      api.selector.show(p,t,shade)
      api.selector.show(p,anchor,"anchor")
      -- A valid track ghost is already the placement footprint. The
      -- staircase of square outlines obscures its continuous diagonal.
      api.selector.area(p,not rail and ids or nil,t,anchor,shade)
      if api.selector.rail then api.selector.rail(p,rail or nil) end
      if api.selector.signal and ui.signal_arrow then api.selector.signal(p,t,world_tool and ui.signal_arrow(p,t) or nil) end
    elseif ids then api.render.preview(n,ids,valid) end
    if H and not world_tool and not picking then
      desc="" -- Menu labels sit next to the actual hotbar, not the crosshair.
    elseif not picking and (key=="company" or key=="jump" or key=="custom" and not Sim.tools[tool]) then
      desc=slot[2]
    end
    local entry=hud[n] or {}
    local function draw(id,pos,text,color,vertical)
      if not entry[id] then
        entry[id]=p:hud_add({type="text",position=pos,alignment={x=0,y=0},offset={x=0,y=vertical or 0},text=text,number=color,z_index=100})
        entry[id.."_text"]=text
      elseif entry[id.."_text"]~=text then
        entry[id.."_text"]=text;p:hud_change(entry[id],"text",text)
      end
    end
    local guidance=ui.tutorial_hint and ui.tutorial_hint(p) or ""
    if guidance~="" or entry.tutorial then draw("tutorial",{x=.5,y=.103},guidance,0xffedbe) end
    draw("aim",{x=.5,y=.55},desc,0xffe3a3)
    draw("status",{x=.5,y=H and .803 or .831},status,0xe8f2df)
    if H then
      local section=H.active(state.menus)
      draw("guide",{x=.5,y=.768},not picking and ui.guide(p,section) or "",0xffe3a3)
      local title,focus,help
      local inherited=clear_inherited(p,state)
      if picking and state.order_menu then
        title=state.order_menu.title
        if road_picking then
          focus=key=="order_done" and (H.shortcut(state.order_done).."  Done") or "Pick stops in travel order"
          help="Left-click a stop    ·    Right-click or "..H.shortcut(state.order_done).." + click to finish"
        else
          local ready=state.order_mode=="rail" and api.owned_rail_ui.ready(p) or
            state.order_mode=="fixed" and ui.fixed_route_ready(p)
          focus=key=="order_cancel" and "Cancel route setup" or key=="order_dispatch" and
            (ready and "Click to dispatch" or "Choose the required stops first") or
            (ready and "Destination picked: dispatch or choose another" or "Pick a highlighted target")
          help=H.shortcut(state.order_done).." + click to dispatch    ·    Right-click or "..
            H.shortcut(state.order_cancel).." + click to cancel"
        end
      else
        title,focus,help=H.legend(state.menus,p:get_wield_index(),world_tool,menu)
        if inherited then
          focus=focus.."  (not armed)"
          help="Left-click once to arm Bulldoze, or select another tool."
        end
      end
      local panel={x=.5,y=.861}
      if not entry.hotbar_panel then
        entry.hotbar_panel=p:hud_add({type="image",position=panel,alignment={x=0,y=0},
          scale={x=1,y=1},text="bl_hotbar_legend.png",z_index=97})
      end
      draw("mode",panel,title,0xffe3a3,-22)
      draw("selected",panel,focus,0xfff5db,0)
      draw("help",panel,help,0xc0dce3,22)
    else
      draw("help",{x=.5,y=.865},"WASD fly · Space/Shift altitude · 1–8 tools · I inventory · Right-click palette",0xc0dce3)
    end
    hud[n]=entry
  end
  local function labels(p,state)
    local pos=p:get_pos()
    local ids=state.labels or {}
    local keep={}
    local names=state.label_names or {}
    local function visit(k,id,name,color,height)
      local x,z=Sim.xy(id);x,z=x*2+.5,z*2+.5
      if (x-pos.x)^2+(z-pos.z)^2>42^2 then return end
      keep[k]=true
      if not ids[k] then
        ids[k]=p:hud_add({type="waypoint",name=name,text="",precision=0,
          world_pos={x=x,y=height or 2.55,z=z},number=color,z_index=-300})
      elseif names[k]~=name then
        p:hud_change(ids[k],"name",name)
      end
      names[k]=name
    end
    for _,site in ipairs(S.sites) do
      if not site.closed then
        if api.road_first and site.kind=="town" then
          visit("f"..site.id,site.tile,site.name.."  ("..site.population..")",0xffebaf,
            api.generated_world and S.tiles[site.tile].h+3 or 3)
        else visit("f"..site.id,site.tile,site.name,0xffebaf) end
      end
    end
    if api.road_first and not api.generated_world then
      local phase=ui.phase(p)
      local menu=W.menu(p)
      local starter=menu=="home" or menu=="roads" or menu=="road_stops"
      if starter and phase<=2 then
        for _,mark in ipairs({{"guide_a",9,"A  •  Port Alder stop"},{"guide_b",18,"B  •  Mason Quay stop"}}) do
          local id=Sim.id(mark[2],12)
          if not S.tiles[id].station then visit(mark[1],id,mark[3],0xffcf76,.66) end
        end
      elseif starter and phase==3 then
        visit("guide_depot",Sim.id(10,13),"Suggested depot",0xffcf76,.66)
      end
    end
    for _,st in pairs(S.stations) do
      local title=ui.stop_label(st)
      if api.road_first and st.mode=="road" then
        local waiting,units=0," waiting"
        if api.oil_tools and st.stop_type=="truck" then
          local oil=Sim.oil_stop_status(S,st,"oil") or 0
          local goods=Sim.oil_stop_status(S,st,"goods") or 0
          if oil>0 then title=title.."   ·   "..oil.." kL crude" end
          if goods>0 then title=title.."   ·   "..goods.." crates" end
        elseif api.timber_tools and st.stop_type=="truck" then
          local wood=Sim.timber_stop_status(S,st,"wood") or 0
          local goods=Sim.timber_stop_status(S,st,"goods") or 0
          if wood>0 then title=title.."   ·   "..wood.." t wood" end
          if goods>0 then title=title.."   ·   "..goods.." crates" end
        elseif st.coal_art and Sim.coal_stop_status then
          waiting,units=Sim.coal_stop_status(S,st)," t waiting"
        elseif st.stop_type=="truck" and S.road_mail then
          waiting,units=Sim.mail_stop_status(S,st)," bags waiting"
        elseif st.stop_type~="truck" then waiting=Sim.waiting_passengers(S,st) end
        if (waiting or 0)>0 then title=title.."   ·   "..waiting..units end
      end
      visit("s"..st.id,st.tile,title,0xaddbe5)
    end
    for k,id in pairs(ids) do if not keep[k] then p:hud_remove(id);ids[k]=nil;names[k]=nil end end
    state.labels=ids;state.label_names=names
  end
  function W.step(dt)
    dt=math.min(dt,.10)
    for _,p in ipairs(core.get_connected_players()) do
      local state=controls[p:get_player_name()]
      if state then
        local keys=p:get_player_control()
        local click=keys.dig or keys.LMB
        if not click then state.clear_arming_press=nil end
        if click and not state.dig then activate(p:get_wielded_item(),p,false,true) end
        state.dig=click
        if H then
          local right=keys.place or keys.RMB
          if right and not state.place then activate(p:get_wielded_item(),p,true) end
          state.place=right
        end
        if state.demolishing then
          local item=entries(state)[p:get_wield_index()]
          if not item or item[1]~="clear" then
            state.demolishing=nil
            state.demolition_cancelled=true
            ui.cancel_demolition(p)
          elseif not click then
            state.demolishing=nil
            local at=W.target(p)
            if at then ui.end_demolition(p,at,keys.aux1==true)
            else ui.cancel_demolition(p) end
            W.hud(p)
          end
        end
        if state.build_drag then
          local drag=state.build_drag
          local item=entries(state)[p:get_wield_index()]
          local tool=item and (item[1]=="custom" and state.custom or item[1])
          if tool~=drag.tool then
            cancel_drag(p,state)
          elseif not click then
            local at,hit=W.target(p)
            if at and hit then
              state.build_drag=nil
              ui["end_"..drag.kind](p,at,hit)
            else cancel_drag(p,state) end
            W.hud(p)
          end
        end
        if not click then state.demolition_cancelled=nil;state.build_drag_cancelled=nil end
        update_flight_speed(p,state,keys)
        vertical_flight(p,state,dt,keys)
        state.elapsed=state.elapsed+dt
        if state.elapsed>=.08 then state.elapsed=0;W.hud(p) end
        state.signs_elapsed=(state.signs_elapsed or .8)+dt
        if state.signs_elapsed>=.8 then state.signs_elapsed=0;labels(p,state) end
      end
    end
  end
  return W
end
