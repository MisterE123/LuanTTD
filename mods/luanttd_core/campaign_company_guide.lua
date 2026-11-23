-- Builder guidance depends on the whole campaign. Index company-owned
-- roads and depots once on the worker, then update only edited tiles.
return function(Sim,s)
  local G={}
  local counts,tiles={},{}
  local function observe(id)
    local t=s.tiles[id]
    local previous=tiles[id]
    local kind=t and t.owner and (t.build=="road_depot" and "depot" or
      not s.stock_generated_profile and t.build=="road" and "road")
    if previous then
      local c=counts[previous.owner]
      c[previous.kind]=c[previous.kind]-1
      tiles[id]=nil
    end
    if kind then
      local c=counts[t.owner] or {depot=0,road=0}
      c[kind]=c[kind]+1
      counts[t.owner]=c
      tiles[id]={owner=t.owner,kind=kind}
    end
  end
  for id in pairs(s.tiles) do observe(id) end
  function G.changed(ids)
    if type(ids)~="table" then return end
    for _,id in ipairs(ids.tiles or ids) do if type(id)=="number" then observe(id) end end
  end
  function G.phase(owner)
    local c=s.companies[owner]
    if c and c.paid_units>0 then return 8 end
    local order_count=0
    for _,v in pairs(s.fleet) do
      if v.owner==owner then
        if v.running then return 7 end
        order_count=math.max(order_count,#(v.orders or {})+1)
      end
    end
    if order_count>0 then return order_count>=3 and 6 or 5 end
    local used=counts[owner]
    if used and used.depot>0 then return 4 end
    local stops=0
    for _,v in pairs(s.stations) do
      if v.mode=="road" and v.owner==owner and v.stop_type~="truck" then
        local linked=not s.stock_generated_profile
        if not linked then
          for d=1,4 do if Sim.road_connected(s,v.tile,d) then linked=true;break end end
        end
        if linked then stops=stops+1;if stops==2 then return 3 end end
      end
    end
    return (s.stock_generated_profile or used and used.road>=2) and 2 or 1
  end
  return G
end
