-- Shared UI adapter for the paid road fleet and the independent tram pilot.
return function(api)
  local S,Sim=api.s,api.Sim
  local Road,Tram={},{}
  local function valid_index(i,n)
    return type(i)=="number" and i%1==0 and i>=1 and i<=n
  end
  local function signature(v)
    local items={}
    for _,o in ipairs(v.orders) do items[#items+1]=o.station..":"..tostring(o.action) end
    return table.concat(items,"/")
  end
  local function depot_receiver(owner,id,depot)
    local v,t=S.fleet[id],S.tiles[depot]
    if not v or v.owner~=owner or not Sim.vehicles[v.engine] or Sim.vehicles[v.engine].mode~="road"
        or (v.home_depot or v.depot)~=depot or not t or t.build~="road_depot" or t.owner~=owner then
      return nil,"Choose a road vehicle assigned to this depot."
    end
    if v.running or v.route or v.road_return_depot then return nil,"Stop the receiving vehicle before copying orders." end
    return v
  end
  function Road.copy_sources(owner,id,depot)
    local dst,why=depot_receiver(owner,id,depot)
    if not dst then return nil,why end
    local sources={}
    for _,v in pairs(S.fleet) do
      if v~=dst and v.owner==owner and #v.orders>0 and Sim.can_copy_road_orders(S,owner,id,v.id) then
        sources[#sources+1]={id=v.id,label=v.name,revision=signature(v),count=#v.orders,
          cargo=Sim.cargo[v.cargo] and Sim.cargo[v.cargo].name}
      end
    end
    table.sort(sources,function(a,b) return a.id<b.id end)
    return {vehicle=id,label=dst.name,count=#dst.orders,revision=signature(dst),sources=sources}
  end
  function Road.copy(owner,id,depot,source,source_revision,target_revision)
    local dst,why=depot_receiver(owner,id,depot)
    if not dst then return false,why end
    local src=S.fleet[source]
    if not src or src==dst or src.owner~=owner or #src.orders==0 then
      return false,"Choose another road vehicle with orders from your company."
    end
    if signature(dst)~=target_revision or signature(src)~=source_revision then
      return false,"Orders changed. Review the source and try again."
    end
    return Sim.clone_road_orders(S,owner,id,source,"copy")
  end
  function Road.read(owner,id)
    local v=S.fleet[id]
    if not v or v.owner~=owner or Sim.vehicles[v.engine].mode~="road" then return end
    local items,targets={},{}
    for _,o in ipairs(v.orders) do
      local title=Sim.road_order_name(S,o.station)
      local suffix=({full=" (Full load)",unload=" (Unload only)",transfer=" (Transfer)",via=" (Go via)"})[o.action] or ""
      items[#items+1]={id=o.station,label=(title or "Missing stop")..suffix}
    end
    for sid,st in pairs(S.stations) do
      if Sim.road_order_target(S,owner,id,sid) then targets[#targets+1]={id=sid,label=st.name} end
    end
    for wp,mark in pairs(S.stock_road_waypoints or {}) do
      local key="waypoint:"..wp
      if Sim.road_order_target(S,owner,id,key) then targets[#targets+1]={id=key,label=mark.name} end
    end
    table.sort(targets,function(a,b)
      if type(a.id)~=type(b.id) then return type(a.id)=="number" end
      return a.id<b.id
    end)
    local active=type(v.road_order_override)=="number" and v.road_order_override
      or v.dest_index or v.road_depot_resume or v.index
    if #v.orders>0 and v.road_via_pending and v.dest_index and not v.road_order_override then
      local tag="waypoint:"..v.road_via_pending[1]
      local index=(v.dest_index-2)%#v.orders+1
      for _=1,#v.orders do
        local row=v.orders[index]
        if not row or row.action~="via" then break end
        if row.station==tag then active=index end
        index=(index-2)%#v.orders+1
      end
    end
    return {items=items,targets=targets,revision=signature(v),active=active,
      can_toggle=v.running or #v.orders>=2,running=not not v.running}
  end
  function Road.edit(owner,id,revision,operation,index,target)
    local actual=Road.read(owner,id)
    if not actual then return false,"Choose an owned road vehicle." end
    if revision~=actual.revision then return false,"Orders changed. Review the updated list." end
    if operation=="append" then return Sim.add_order(S,owner,id,target,"normal") end
    if not valid_index(index,#actual.items) then return false,"Select an order first." end
    return Sim.edit_order(S,owner,id,index,operation)
  end
  local function tram_info(owner,id)
    if not api.tram or not api.tram.run then return end
    local service=api.tram.run
    if service.by_ui and type(id)=="number" then
      local p=service.by_ui(S,id)
      if p and p.owner==owner then return service.orders(S,owner,service.serial(p)) end
    end
    local a,b,p=service.orders(S,owner)
    if p and (id=="pilot" or id==1 or id==p.depot) then return a,b,p end
  end
  function Tram.read(owner,id)
    local orders,rev,p=tram_info(owner,id)
    if not orders then return end
    local items,targets={},{}
    local function label(tile)
      local x,z=Sim.xy(tile)
      local st=Sim.tram_stop_station(S,tile,owner)
      return st and st.name or ("Tram stop (%d, %d)"):format(x,z)
    end
    for _,tile in ipairs(orders) do items[#items+1]={id=tile,label=label(tile)} end
    -- Enumerate physical platforms from the station registry instead
    -- of walking every cell on large generated worlds.
    for _,st in pairs(S.stations) do
      if st.owner==owner and st.mode=="road" then
        local function offer(tile)
          if Sim.tram_stop_station(S,tile,owner)==st then targets[#targets+1]={id=tile,label=st.name} end
        end
        if st.road_members then
          for tile in pairs(st.road_members) do offer(tile) end
        else offer(st.tile) end
      end
    end
    table.sort(targets,function(a,b) return a.id<b.id end)
    local leg=p.legs[p.leg]
    local active=leg.order_index or (not p.loop and (p.leg==3 and 1 or p.leg==2 and 2 or p.leg==4 and 2 or 1)) or nil
    local carrier=p.carrier
    local summary=carrier and ("%d / %d aboard  |  %d delivered  |  $%d fares"):format(
      carrier.units,carrier.stock_tram.capacity,carrier.delivered,carrier.revenue)
    return {items=items,targets=targets,revision=rev,active=active,pending=(not active and p.pending_order or nil),summary=summary}
  end
  function Tram.edit(owner,id,revision,op,index,target)
    local current=Tram.read(owner,id)
    if not current then return false,"Choose your operating streetcar." end
    if current.revision~=revision then return false,"Orders changed. Review the updated list." end
    local orders={}
    for i,o in ipairs(current.items) do orders[i]=o.id end
    local active=current.active
    local next_order=current.pending or active%#orders+1
    if op=="append" then
      if not api.tram.facility(owner,target,"drive_stop") then return false,"Choose an owned tram stop." end
      orders[#orders+1]=target
      if active==#orders-1 then next_order=#orders end
    else
      if not valid_index(index,#orders) then return false,"Select an order first." end
      if op=="skip" then
        if (current.pending or active)==index then return false,"This is already the current order." end
        active=nil
        next_order=index
      elseif op=="remove" then
        table.remove(orders,index)
        if #orders<2 then return false,"Keep at least two tram stops." end
        if active==index then
          active=nil
          next_order=index>#orders and 1 or index
        elseif active then
          if index<active then active=active-1 end
          next_order=active%#orders+1
        elseif index<=next_order then
          if index<next_order then next_order=next_order-1 end
          if next_order>#orders then next_order=1 end
        end
      elseif op=="up" or op=="down" then
        local i=index+(op=="up" and -1 or 1)
        if not valid_index(i,#orders) then return false,"Cannot move this order farther." end
        orders[i],orders[index]=orders[index],orders[i]
        active=active==index and i or active==i and index or active
        next_order=active and active%#orders+1 or next_order==index and i or next_order==i and index or next_order
      else return false,"Unsupported tram order operation." end
    end
    local _,_,p=tram_info(owner,id)
    local serial=api.tram.run.serial and api.tram.run.serial(p)
    local ok,why=api.tram.run.replace_orders(S,owner,orders,next_order,active,serial)
    return ok,ok and why or api.tram.reason(why)
  end
  return {road=Road,tram=Tram}
end
