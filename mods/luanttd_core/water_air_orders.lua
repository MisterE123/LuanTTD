-- SPDX-License-Identifier: GPL-2.0-only
-- Adapters for live ship/aircraft orders. List index updates use the
-- translated OpenTTD 16.0-RC1 order_cmd.cpp/vehicle_base.h rules.
return function(s,Sim,O,Ship,Coal,C,Air,Oil,Tanker)
  local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local CargoOrder=dofile(mod.."/openttd/rail_order_cargo.lua")
  local Rig=dofile(mod.."/openttd/oil_rig.lua")
  local function label(title,id,tile)
    local x,z
    if tile then x,z=Sim.xy(tile) end
    return title..(x and (" (%d, %d)"):format(x,z) or " #"..id)
  end
  local function strict_index(index)
    return type(index)=="number" and index%1==0 and index>0
  end
  local function key(o) return o.kind=="waypoint" and ("buoy:"..o.id) or o.id end
  local function registry(mode)
    return mode=="air" and (s.stock_small_airports or {}) or (s.stock_ship_stations or {})
  end
  local function order(mode,owner,id,check,saved_policy)
    local buoy=mode=="ferry" and type(id)=="string" and id:match("^buoy:(%d+)$")
    if buoy then
      local b=(s.stock_ship_buoys or {})[tonumber(buoy)]
      if b then return {kind="waypoint",id=b.id,tile=b.tile},label("Buoy",b.id,b.tile) end
      return
    end
    local st=registry(mode)[id]
    local rig=(mode=="oil" or mode=="air") and Rig.neutral_ref(s,st)
    if not st or st.owner~=owner and not rig then return end
    local title=rig and rig.name or mode=="air" and (st.layout=="city" and "City Airport" or st.layout=="heliport" and "Heliport"
      or st.layout=="international" and "International Airport" or st.layout=="intercontinental" and "Intercontinental Airport" or st.layout=="commuter" and "Commuter Airport" or st.layout=="metropolitan" and "Metropolitan Airport" or st.layout=="helidepot" and "Helidepot" or st.layout=="helistation" and "Helistation" or "Airfield") or "Dock"
    local o={kind="station",id=id}
    if mode=="coal" or mode=="oil" then
      local report=not saved_policy and (mode=="coal" and C.order_report(s,id) or mode=="oil" and Tanker.report(s,id))
      if check and (not report or #report.sources==0 and not report.accepts) then return end
      if saved_policy=="full" or report and #report.sources>0 then
        o.cargo_order="full";title=rig and ("Full load at "..rig.name) or mode=="oil" and "Full load at oil dock" or "Full load at mine"
      elseif saved_policy=="no_load" or report and report.accepts then
        o.cargo_order="no_load";title=mode=="oil" and "Unload at refinery" or "Unload at power station"
      end
    end
    return o,label(title,id,st.origin or st.land)
  end
  local function locate(mode,owner,id)
    local run=mode=="ferry" and Ship or mode=="coal" and Coal or mode=="air" and Air or mode=="oil" and Oil
    if not run then return end
    local p
    if mode=="air" then
      if not strict_index(id) then return end
      p=run.current(s,id)
    else p=run.current(s) end
    if not p or not p.vehicle or p.owner~=owner or mode=="ferry" and not p.owned then return end
    return p,run
  end
  local function snapshot(p,mode,owner)
    if p.transport_orders then return p.transport_orders,p.transport_order_cursor end
    local a=order(mode,owner,p.first) or {kind="station",id=p.first}
    local b=order(mode,owner,p.second) or {kind="station",id=p.second}
    if mode=="coal" or mode=="oil" then a.cargo_order,b.cargo_order="full","no_load" end
    local current=p.vehicle.order
    local list={a,b}
    local station=p.pending_buoy_dock or current and (current.next_station or current.id)
    local i=station==b.id and 1 or 0
    if mode=="ferry" and p.via then
      local via={kind="waypoint",id=p.via.id,tile=p.via.tile}
      list={a,via,b,via}
      if current and current.kind=="waypoint" then
        i=i==1 and 1 or 3
      else i=i*2 end
    end
    return list,{real=i,implicit=i}
  end
  local function create_selector(mode_of)
    local A={}
    function A.read(owner,id)
      local mode=mode_of(id)
      local p=locate(mode,owner,id)
      if not p then return end
      local list,cursor=snapshot(p,mode,owner)
      local items,targets={},{}
      for i,o in ipairs(list) do
        local dest=key(o)
        local _,desc=order(mode,owner,dest,nil,o.cargo_order)
        items[i]={id=dest,label=(desc or ("Removed stop "..tostring(dest)))..(mode=="air" and CargoOrder.summary(o) or ""),
          cargo=mode=="air" and {load=o.load_type or 0,unload=o.unload_type or 0} or nil}
      end
      local ids={}
      for id in pairs(registry(mode)) do ids[#ids+1]=id end
      table.sort(ids)
      for _,i in ipairs(ids) do
        local o,desc=order(mode,owner,i,true)
        if o and (mode~="air" or not Air.route_stop or Air.route_stop(s,registry(mode)[i],p.engine_id,p)) then
          targets[#targets+1]={id=i,label=desc}
        end
      end
      if mode=="ferry" then
        local buoys={}
        for i in pairs(s.stock_ship_buoys or {}) do buoys[#buoys+1]=i end
        table.sort(buoys)
        for _,i in ipairs(buoys) do
          local id="buoy:"..i
          local o,desc=order(mode,owner,id,true)
          if o then targets[#targets+1]={id=id,label=desc} end
        end
      end
      return {items=items,targets=targets,revision=p.transport_orders_revision or 0,
        active=cursor.real+1,can_toggle=mode~="air",running=mode~="air" and not p.stopped or nil,
        cargo_rules=mode=="air" and {load=CargoOrder.load,unload=CargoOrder.unload} or nil}
    end
    function A.edit(owner,id,revision,op,index,target)
      local mode=mode_of(id)
      local p,run=locate(mode,owner,id)
      if not p then return false,"This is not your active vehicle." end
      if p.failure then return false,"This vehicle is blocked: "..tostring(p.failure) end
      local rev=p.transport_orders_revision or 0
      if rev~=revision then return false,"The order list changed. Review it again." end
      local list,cursor=snapshot(p,mode,owner)
      local seq={}
      for i,o in ipairs(list) do seq[i]=o end
      local c={real=cursor.real,implicit=cursor.implicit}
      local current=index==c.real+1
      if op=="append" then
        local o=order(mode,owner,target,true)
        if not o or mode=="air" and Air.route_stop and not Air.route_stop(s,registry(mode)[target],p.engine_id,p) then
          return false,"Choose a compatible destination."
        end
        if not O.insert(seq,c,#seq,o) then return false,"The order list is full." end
      elseif not strict_index(index) or index>#seq then return false,"Choose an order."
      elseif op=="up" or op=="down" then
        local to=index+(op=="up" and -1 or 1)
        if not O.move(seq,c,index-1,to-1) then return false,"That order is already at the end of the list." end
      elseif op=="remove" then
        if #seq<=2 then return false,"Keep at least two orders in this service. Add a replacement first." end
        assert(O.delete(seq,c,index-1))
      elseif op=="skip" then
        if index==c.implicit+1 or #seq<2 then return false,"This is already the current order." end
        c.real,c.implicit=index-1,index-1
        O.update_real(seq,c)
      elseif mode=="air" and (op=="load" or op=="unload") then
        local setting={}
        for k,v in pairs(seq[index]) do setting[k]=v end
        if not CargoOrder.change(setting,op,target) then return false,"That cargo rule is already set or is not supported." end
        seq[index]=setting
      else return false,"Unknown order command." end
      local n,first,second=0
      local has_full,has_unload
      for _,o in ipairs(seq) do
        if o.kind=="station" then
          if not first then first=o.id elseif first~=o.id and not second then second=o.id end
          n=n+1
          has_full=has_full or o.cargo_order=="full"
          has_unload=has_unload or o.cargo_order=="no_load"
        end
      end
      if n<2 or not second then return false,"Keep two different stations in this service." end
      if (mode=="coal" or mode=="oil") and not (has_full and has_unload) then
        return false,mode=="oil" and "Keep an oil source and refinery order." or "Keep a mine loading order and a power-station unloading order."
      end
      if op=="append" and run.check_order then
        local ok,why=run.check_order(s,p,seq)
        if not ok then return false,why end
      end
      p.transport_orders,p.transport_order_cursor,p.transport_orders_revision=seq,c,rev+1
      if op=="skip" and p.vehicle.loading then
        -- CmdSkipToOrder calls LeaveStation and selects the requested cursor.
        p.transport_skip_loading=true
      elseif op=="remove" and current and p.vehicle.loading then
        -- DeleteOrder cancels compulsory full loading, not the entire stop.
        p.transport_cancel_full=true
      elseif mode=="air" and op=="load" and current and p.vehicle.loading then
        p.transport_live_load=target
      end
      return true,op=="skip" and "Vehicle order changed." or "Vehicle orders updated."
    end
    return A
  end
  return {ship=create_selector(function(id) if id=="ferry" or id=="coal" or id=="oil" then return id end end),
          air=create_selector(function() return "air" end)}
end
