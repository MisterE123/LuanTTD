-- SPDX-License-Identifier: GPL-2.0-only
-- Per-player HUD suppression. Neither time, movement, nor any observer
-- belonging to another player changes when this view is entered.
return function(core,hide,restore)
  local C={}
  local players={}
  local outside={x=-8,y=-8}
  local recovered_form="formspec_version[7]size[7,2]bgcolor[#152334;true]"..
    "button_exit[.50,.54;6,.65;luanttd_cine_toggle;Restore interface]"
  local flags={hotbar=false,healthbar=false,crosshair=false,wielditem=false,breathbar=false,
    minimap=false,minimap_radar=false,basic_debug=false}
  local function name(p) return p:get_player_name() end
  local function mask_hud(p,state)
    if not p.hud_get_all then return end
    local shown=p:hud_get_all()
    for id,old in pairs(state.hud) do if not shown[id] then state.hud[id]=nil end end
    for id,d in pairs(shown) do
      local pos=d.position
      if (d.type or d.hud_elem_type)=="waypoint" then
        -- World labels normally leave via the world HUD callback.
        -- Suppress waypoints from another tab or late callback too.
        if d.name~="" or d.text~="" then
          state.hud[id]={label={name=d.name,text=d.text}}
          p:hud_change(id,"name","");p:hud_change(id,"text","")
        end
      elseif pos and (pos.x~=outside.x or pos.y~=outside.y) then
        state.hud[id]={position={x=pos.x,y=pos.y}}
        p:hud_change(id,"position",outside)
      end
    end
  end
  function C.active(p) return players[name(p)]~=nil end
  function C.toggle(p)
    local n=name(p)
    local state=players[n]
    if state then
      players[n]=nil
      p:hud_set_flags(state.flags)
      for id,h in pairs(state.hud) do
        if not p.hud_get or p:hud_get(id) then
          if h.position then p:hud_change(id,"position",h.position) end
          if h.label then
            if h.label.name then p:hud_change(id,"name",h.label.name) end
            if h.label.text then p:hud_change(id,"text",h.label.text) end
          end
        end
      end
      p:set_inventory_formspec(state.form)
      restore(p)
      return true
    end
    state={flags=p:hud_get_flags(),form=p:get_inventory_formspec(),hud={}}
    players[n]=state
    core.close_formspec(n,"")
    hide(p)
    p:hud_set_flags(flags)
    mask_hud(p,state)
    p:set_inventory_formspec(recovered_form)
    return true
  end
  local elapsed=0
  function C.step(dt)
    if not next(players) then return end
    elapsed=elapsed+dt
    if elapsed<.18 then return end
    elapsed=0
    for n,state in pairs(players) do
      local p=core.get_player_by_name(n)
      if p then
        local current=p:hud_get_flags()
        local changed=false
        for k in pairs(flags) do
          if current[k] then state.flags[k]=true;changed=true end
        end
        if changed then p:hud_set_flags(flags) end
        local form=p:get_inventory_formspec()
        if form~=recovered_form then
          state.form=form;p:set_inventory_formspec(recovered_form)
        end
        mask_hud(p,state)
      else players[n]=nil end
    end
  end
  function C.leave(n) players[n]=nil end
  core.register_chatcommand("cine",{description="Hide or restore the interface and pointed-tile outline",
    func=function(n)
      local p=core.get_player_by_name(n)
      if p then return C.toggle(p) end
      return false,"Join the world first."
    end})
  return C
end
