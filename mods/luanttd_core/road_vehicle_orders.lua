-- Shared UI adapter for the paid road fleet and the independent tram pilot.
return function(api)
  local S,Sim=api.s,api.Sim
  local Road,Tram={},{}
  local function valid_index(i,n)
    return type(i)=="number" and i%1==0 and i>=1 and i<=n
  end
  function Road.read(owner,id)
    local v=S.fleet[id]
    if not v or v.owner~=owner or Sim.vehicles[v.engine].mode~="road" then return end
    local items,targets,signature={},{},{}
    for _,o in ipairs(v.orders) do
      local st=S.stations[o.station]
      local suffix=({full=" (Full load)",unload=" (Unload only)",transfer=" (Transfer)"})[o.action] or ""
      items[#items+1]={id=o.station,label=(st and st.name or "Missing stop")..suffix}
      signature[#signature+1]=o.station..":"..tostring(o.action)
    end
    for sid,st in pairs(S.stations) do
      if Sim.road_order_target(S,owner,id,sid) then targets[#targets+1]={id=sid,label=st.name} end
    end
    table.sort(targets,function(a,b) return a.id<b.id end)
    local active=type(v.road_order_override)=="number" and v.road_order_override
      or v.dest_index or v.road_depot_resume or v.index
    return {items=items,targets=targets,revision=table.concat(signature,"/"),active=active,
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
    local a,b,p=api.tram.run.orders(S,owner)
    if p and (id=="pilot" or id==1 or id==p.depot) then return a,b,p end
  end
  function Tram.read(owner,id)
    local orders,rev,p=tram_info(owner,id)
    if not orders then return end
    local items,targets={},{}
    local function label(tile)
      local x,z=Sim.xy(tile)
      return ("Tram stop (%d, %d)"):format(x,z)
    end
    for _,tile in ipairs(orders) do items[#items+1]={id=tile,label=label(tile)} end
    for tile,t in ipairs(S.tiles) do
      if t.tram and t.tram.owner==owner and t.tram.kind=="drive_stop" then
        targets[#targets+1]={id=tile,label=label(tile)}
      end
    end
    local leg=p.legs[p.leg]
    local active=leg.order_index or (not p.loop and (p.leg==3 and 1 or p.leg==2 and 2 or p.leg==4 and 2 or 1)) or nil
    return {items=items,targets=targets,revision=rev,active=active,pending=(not active and p.pending_order or nil)}
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
    local ok,why=api.tram.run.replace_orders(S,owner,orders,next_order,active)
    return ok,ok and why or api.tram.reason(why)
  end
  return {road=Road,tram=Tram}
end
