-- Builder guidance depends on the whole campaign. Index company-owned
-- roads and depots once on the worker, then update only edited tiles.
return function(Sim,s)
  local G={}
  local counts,tiles,locations={},{},{}
  local function observe(id)
    local t=s.tiles[id]
    local previous=tiles[id]
    local kind=t and t.owner and (t.rail_depot_dir~=nil and "rail" or
      t.build=="road_depot" and "depot" or
      not s.stock_generated_profile and t.build=="road" and "road")
    if previous then
      local c=counts[previous.owner]
      c[previous.kind]=c[previous.kind]-1
      local set=locations[previous.owner] and locations[previous.owner][previous.kind]
      if set then set[id]=nil end
      tiles[id]=nil
    end
    if kind then
      local c=counts[t.owner] or {depot=0,road=0,rail=0}
      c[kind]=c[kind]+1
      counts[t.owner]=c
      tiles[id]={owner=t.owner,kind=kind}
      if kind~="road" then
        local own=locations[t.owner] or {depot={},rail={}}
        own[kind][id]={id=id,dir=t.rail_depot_dir}
        locations[t.owner]=own
      end
    end
  end
  for id in pairs(s.tiles) do observe(id) end
  function G.changed(ids)
    if type(ids)~="table" then return end
    for _,id in ipairs(ids.tiles or ids) do if type(id)=="number" then observe(id) end end
  end
  function G.depots(owner,rail)
    local set=locations[owner]
    local out={}
    for _,item in pairs(set and set[rail and "rail" or "depot"] or {}) do out[#out+1]=item end
    table.sort(out,function(a,b) return a.id<b.id end)
    return out
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
