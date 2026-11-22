-- LuanTTD aqueduct host. Raised route and physical lower water are not
-- represented by the same tile record. Only rail/water/ordinary road
-- underlays supported by the upstream planner are preserved in place.
return function(Sim,Terrain,Aqua)
  local A={}
  local function bridge_below(s,id)
    local road=s.bridge_above and s.bridge_above[id]
    local aqua=s.aqueduct_above and s.aqueduct_above[id]
    return (road and s.stock_road_bridges[road]) or (aqua and s.stock_aqueducts[aqua])
  end
  local function view(s)
    local B={xy=Sim.xy,id=Sim.id}
    function B.tile(id)
      local t=id and s.tiles[id]
      if not t then return end
      local x,z=Sim.xy(id)
      local slope,base,top=Terrain.tile(s.corner_grid,x,z)
      local span=bridge_below(s,id)
      local kind=t.terrain=="water" and (t.water_class or "sea") or "clear"
      local record={slope=slope,base=base,max_z=top,kind=kind,owner=t.owner,
        overhead=span and {axis=span.axis,deck=span.deck}}
      if t.ship and t.ship.kind=="aqueduct" then
        for k,v in pairs(t.ship) do record[k]=v end
      elseif t.ship or t.tram or t.airfield or t.stock_industry or t.stock_landmark or t.road_bridge_id or t.road_tunnel_id then
        record.kind="obstruction"
      elseif t.rail_tracks then
        record.kind=(t.rail_station_id or t.rail_depot_dir) and "obstruction" or "plain_rail"
      elseif t.build=="road" then record.kind="road"
      elseif t.build=="canal" then record.kind="canal"
      elseif t.build or t.site or t.house or t.wood then record.kind="obstruction" end
      return record
    end
    function B.clear_quote(id,record)
      if Sim.rail_span_protected and Sim.rail_span_protected(s,id) then return nil,"AQUEDUCT_SITE_OCCUPIED" end
      if s.tunnel_below and s.tunnel_below[id] then return nil,"SUBSURFACE_RESERVED" end
      if record.kind=="clear" and not record.overhead and record.owner==nil then return 0 end
      return nil,"AQUEDUCT_SITE_OCCUPIED"
    end
    return B
  end
  function A.quote(s,owner,start,last)
    if not s.corner_grid or not start or not last then return nil,"SELECT_TWO_HEADS" end
    local plan,why,id=Aqua.plan(view(s),start,last,
      {owner=owner,budget=s.companies[owner] and s.companies[owner].cash or 100000})
    if plan and Sim.rail_span_protected then
      for _,tile in ipairs(plan.middle) do
        if Sim.rail_span_protected(s,tile) then return nil,"AQUEDUCT_SITE_OCCUPIED",tile end
      end
    end
    return plan,why,id
  end
  local function expense(s,owner,n)
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-n,c.expense+n,c.month_exp+n
  end
  function A.build(s,owner,start,last)
    local plan,reason,at=A.quote(s,owner,start,last)
    if not plan then return nil,reason,at end
    local key=s.next_stock_aqueduct or 1
    s.next_stock_aqueduct=key+1
    s.stock_aqueducts=s.stock_aqueducts or {}
    s.aqueduct_above=s.aqueduct_above or {}
    s.stock_aqueducts[key]=plan
    local dirty={plan.start,plan["end"]}
    for _,id in ipairs(dirty) do
      local head=Aqua.head_record(plan,id)
      head.aqueduct=key
      s.tiles[id].ship=head
    end
    for _,id in ipairs(plan.middle) do s.aqueduct_above[id]=key;dirty[#dirty+1]=id end
    expense(s,owner,plan.price)
    s.topology=s.topology+1
    return plan,dirty
  end
  function A.remove(s,owner,head,quote)
    local ship=head and s.tiles[head] and s.tiles[head].ship
    local key=ship and ship.aqueduct
    local plan=key and s.stock_aqueducts[key]
    if not plan or plan.owner~=owner then return nil,"SELECT_OWN_AQUEDUCT" end
    local price=Aqua.clear_cost(plan)
    local c=s.companies[owner]
    if not c or c.cash<price then return nil,"NOT_ENOUGH_MONEY" end
    local dirty={plan.start,plan["end"]}
    if not quote then
      s.tiles[plan.start].ship=nil;s.tiles[plan["end"]].ship=nil
      s.stock_aqueducts[key]=nil
      expense(s,owner,price)
      s.topology=s.topology+1
    end
    for _,id in ipairs(plan.middle) do
      if not quote then s.aqueduct_above[id]=nil end
      dirty[#dirty+1]=id
    end
    return dirty,price
  end
  return A
end
