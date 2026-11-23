-- Single-choice, server-authoritative confirmation. This is not an area
-- demolisher or a second infrastructure write path.
return function(api,clear_structure,status)
  local S,Sim,R=api.s,api.Sim,api.render
  local B={form="luanttd_core:demolish_layers"}
  local pending,serial={},0
  local function money(n) return (n<0 and "-$" or "$")..math.abs(n) end
  function B.choices(n,id)
    local t=S.tiles[id]
    local opts,seen={},{}
    if not t then return opts end
    local function add(key,title,ok,detail,apply)
      if seen[key] then return end
      seen[key]=true
      opts[#opts+1]={key=key,title=title,ok=not not ok,detail=detail or "",apply=apply}
    end
    local function structure(key,title,at)
      if not at then return end
      local handled,tiles,note=clear_structure(n,at,true)
      if handled then add(key,title,tiles,note,function() return clear_structure(n,at,false) end) end
    end
    local function span(index,records,title,key)
      local q=index and records and records[index[id]]
      if q then structure(key,title,q.start) end
    end
    span(S.bridge_above,S.stock_road_bridges,"Remove overhead road bridge, keep surface","road_bridge")
    span(S.rail_bridge_above,S.stock_rail_spans,"Remove overhead rail bridge, keep surface","rail_bridge")
    span(S.aqueduct_above,S.stock_aqueducts,"Remove overhead aqueduct, keep surface","aqueduct")
    span(S.tunnel_below,S.stock_road_tunnels,"Remove road tunnel below, keep surface","road_tunnel")
    span(S.rail_tunnel_below,S.stock_rail_spans,"Remove rail tunnel below, keep surface","rail_tunnel")
    if t.tram then add("tramway","Tramway or tram facility",false,"This version does not support removing the tram layer separately.") end
    if t.level_crossing then
      add("crossing","Level crossing",false,"Separate road and rail removal is not available on a level crossing.")
    end
    if t.rail_station_id or t.rail_depot_dir~=nil then
      local title=t.rail_station_id and "Remove entire station platform, keep rails" or "Remove railway depot, keep rails"
      local free=t.owner==n and api.rail_build and not api.rail_build.busy() and api.trackworks
        and (not api.trackworks.span_protected or not api.trackworks.span_protected(S,id))
      local occupied=t.rail_depot_dir~=nil and api.trackworks and api.trackworks.owned_depot_occupied
        and api.trackworks.owned_depot_occupied(S,id)
      add("rail_facility",title,free and not occupied,occupied and "The depot contains a purchased train."
        or not free and "Only clear, owned facilities can be changed while no train is using this railway."
        or "Underlying track stays in place. You can bulldoze it separately afterward.",function()
        local ok,note,tiles=api.trackworks.remove_facility(S,n,id)
        return true,ok and tiles or nil,note
      end)
    end
    local d=S.stock_rail_dispatch
    local function rail_action(key,title,plan,why)
      add(key,title,plan,plan and ("Cost: "..money(plan.price)) or why,function()
        local ok,note=api.rail_build.build(n,plan)
        return true,ok and {} or nil,note
      end)
    end
    if api.rail_build and t.rail_waypoint_id then
      rail_action("waypoint","Remove waypoint, keep rails",api.rail_build.quote_waypoint(n,id,true))
    end
    if api.rail_build and d and d.signals and d.signals.records[id] then
      rail_action("signal","Remove signal, keep rails",api.rail_build.quote_remove_signal(n,id))
    end
    if t.build=="road_station" and t.stop_axis and not t.road_stop_pair and Sim.remove_through_road_stop then
      local can,cost=Sim.remove_through_road_stop(S,n,id,true)
      add("through_stop","Remove stop, keep road",can,can and ("Cost: "..money(cost)) or cost,function()
        local ok,note,tiles=Sim.remove_through_road_stop(S,n,id)
        return true,ok and tiles or nil,note
      end)
    end
    if t.station or t.build=="road_depot" then
      if not t.road_town then
        local plan,cost=Sim.plan(S,n,"clear",{id},true)
        local balance=S.companies[n] and S.companies[n].cash or 100000
        local title=t.build=="road_depot" and "Remove road depot" or "Remove stop and its road"
        add("ground_facility",title,plan and balance>=cost,plan and ("Cost: "..money(cost)) or cost,function()
          local ok,note,tiles=Sim.build(S,n,"clear",{id})
          return true,ok and tiles or nil,note
        end)
      end
    end
    if t.road_bridge_id then structure("road_bridge","Remove the full road bridge",id)
    elseif t.road_tunnel_id then structure("road_tunnel","Remove both road tunnel portals",id)
    elseif t.rail_span_id then structure("rail_span","Remove the full rail bridge or tunnel",id)
    elseif t.airfield then structure("airfield","Remove the entire airfield",id)
    elseif t.ship then structure("harbor","Remove the full harbor structure",id) end
    if t.rail_type==1 and not t.rail_station_id and not t.rail_depot_dir and not t.rail_span_id and
        not t.level_crossing and api.electric_quote and api.electric_commit then
      local q,why=api.electric_quote(n,{id},0)
      add("wire","Remove electrification, keep rails",q,q and ("Cost: "..money(q.cost)) or why,function()
        local ok,note=api.electric_commit(n,q)
        return true,ok and {} or nil,note
      end)
    end
    return opts
  end
  function B.open(p,id)
    local n=p:get_player_name()
    local choices=B.choices(n,id)
    if #choices==0 then return false end
    local x,z=Sim.xy(id)
    serial=serial+1
    pending[n]={id=id,topology=S.topology,options=choices,token=serial}
    local h=2.20+#choices*1.09
    local esc=core.formspec_escape
    local b={("formspec_version[7]size[12.4,%g]bgcolor[#152334;false]"):format(h),
      "style_type[label;textcolor=#E5ECEA]style_type[button;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA]",
      ("label[.42,.47;Bulldozer / tile %d, %d]"):format(x,z),
      "label[.42,.96;Confirm the layer you intend to remove. Nothing has changed yet.]"}
    for i,o in ipairs(choices) do
      local y=1.25+(i-1)*1.09
      if o.ok then b[#b+1]=("button[.42,%g;11.56,.47;bulldoze_%d_%d;%s]"):format(y,serial,i,esc(o.title))
      else b[#b+1]=("label[.42,%g;%s]"):format(y+.24,esc(o.title.." / unavailable")) end
      b[#b+1]=("textarea[.42,%g;11.56,.64;;;%s]"):format(y+.49,esc(o.detail))
    end
    b[#b+1]=("button_exit[.42,%g;11.56,.51;cancel_layers;Cancel]"):format(h-.68)
    core.show_formspec(n,B.form,table.concat(b))
    return true
  end
  function B.fields(p,f)
    local n=p:get_player_name()
    local q=pending[n]
    if not q then return true end
    if f.quit or f.cancel_layers then pending[n]=nil;status(p,"Demolition canceled.");return true end
    local index
    for key in pairs(f) do
      local a,b=key:match("^bulldoze_(%d+)_(%d+)$")
      if tonumber(a)==q.token then
        if index then return true end
        index=tonumber(b)
      end
    end
    local prior=index and q.options[index]
    if not prior or not prior.ok then return true end
    pending[n]=nil
    core.close_formspec(n,B.form)
    local fresh
    if q.topology==S.topology then
      for _,o in ipairs(B.choices(n,q.id)) do
        if o.key==prior.key and o.ok and o.detail==prior.detail then fresh=o;break end
      end
    end
    if not fresh then status(p,"The tile or quote changed. Select it again.");return true end
    local _,ids,note,level=fresh.apply()
    status(p,note or "Layer removal canceled.")
    if ids then
      if level then R.raise_bound(level) end
      if #ids>0 then R.update(ids);api.save() end
    end
    return true
  end
  function B.leave(n) pending[n]=nil end
  return B
end
