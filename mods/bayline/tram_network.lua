-- Bridge the saved shared-corner world to the OpenTTD ELRL construction and
-- traversal rules. This slice deliberately accepts only flat, at-grade rail.
-- Rail and road bits/owners are independent even where they share a tile.
return function(Sim,T,Terrain)
  local N={}
  local ELRL,ROAD=1,0
  local function shape(s,id)
    if not s.corner_grid or not s.tiles[id] then return end
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function load(s,id)
    local t=id and s.tiles[id]
    if not t then return end
    local p=t.tram
    local slope,base=shape(s,id)
    local out={slope=slope,base=base,
      overhead=s.bridge_above and s.bridge_above[id]~=nil or false}
    if p then
      for k,v in pairs(p) do out[k]=v end
    end
    if t.build=="road" or (p and p.kind=="drive_stop" and t.build=="road_station") then
      out.kind=out.kind or "road"
      out.road_bits=Sim.road_bits(s,id)
      if out.road_bits>0 then
        out.roadtype=ROAD
        out.road_owner=t.road_town and "town" or t.owner
      end
    end
    if not out.kind then
      if t.terrain=="water" then out.kind="water"
      elseif t.build or t.site or t.house or t.wood or t.ship or t.airfield or t.stock_industry or t.stock_landmark then out.kind="protected"
      else out.kind="clear" end
    end
    return out
  end
  local function playable(s,id,t)
    return t and t.slope==0 and not t.overhead and
      not (Sim.rail_span_protected and Sim.rail_span_protected(s,id)) and
      not (s.tunnel_below and s.tunnel_below[id])
  end
  local function options(owner)
    return {owner=owner,build_on_slopes=false,no_water=true,drive_through=true,
      stop_type="bus",clear_quote=function(t)
        if t.kind=="clear" then return 0 end
        return nil,"PROTECTED_TILE"
      end}
  end
  local function propose(s,owner,kind,id,arg,occupancy)
    local t=load(s,id)
    if not playable(s,id,t) then return nil,"TRAM_NEEDS_FLAT_CLEARANCE" end
    if occupancy and occupancy(id) then t.occupied=true end
    local p,why
    if kind=="road" and (t.kind=="road" or t.kind=="clear" or t.kind=="drive_stop") then
      p,why=T.lay(t,arg,ELRL,options(owner))
    elseif kind=="depot" and (t.kind=="clear" or t.kind=="depot") then
      p,why=T.depot(t,arg,ELRL,options(owner))
    elseif kind=="drive_stop" and (t.kind=="clear" or t.kind=="road") then
      -- Do not silently replace/extend the shared road in this preview.
      -- Complete the through carriageway with the road tool first.
      local axis=arg==0 and 10 or arg==1 and 5
      if not axis then return nil,"INVALID_PARAMETER" end
      if t.roadtype~=nil and t.road_bits~=axis then return nil,"TRAM_STOP_NEEDS_THROUGH_ROAD" end
      p,why=T.stop(t,arg,ELRL,options(owner))
    else
      return nil,"PROTECTED_TILE"
    end
    if not p then return nil,why end
    return {kind=p.kind,dir=p.dir or t.dir,tram_bits=p.tram_bits,tramtype=p.tramtype,
      owner=p.kind~="road" and (p.owner or t.owner) or nil,tram_owner=p.tram_owner,
      station=(p.kind=="drive_stop") and id or nil,stop_type=(p.kind=="drive_stop") and "bus" or nil},
      p.cost
  end

  -- Quotes are read-only and failed drags have no cash/tile side effects.
  -- Command input uses the stock mask or stock diag direction; no ID cache
  -- lives past a board's snapshot lifetime.
  function N.plan(s,owner,kind,ids,arg,occupancy)
    if not s.corner_grid or type(owner)~="string" or type(ids)~="table" or #ids==0 or
       (kind~="road" and kind~="drive_stop" and kind~="depot") then return nil,"INVALID_PARAMETER" end
    if kind=="road" and arg~=nil and (type(arg)~="number" or arg%1~=0 or arg<1 or arg>15) then
      return nil,"INVALID_PARAMETER"
    end
    if kind~="road" and (#ids~=1 or type(arg)~="number" or arg%1~=0 or arg<0 or arg>3) then
      return nil,"INVALID_PARAMETER"
    end
    if kind=="road" and arg and #ids~=1 then return nil,"INVALID_PARAMETER" end
    local requests,seen,total,items={},{},0,{}
    for n,id in ipairs(ids) do
      if not s.tiles[id] or seen[id] then return nil,"INVALID_PARAMETER" end
      seen[id]=true
      if kind=="road" and n>1 then
        local prev,matched=ids[n-1],false
        for d=1,4 do
          if Sim.adjacent(prev,d)==id then
            requests[prev]=(requests[prev] or 0)+2^(d-1)
            requests[id]=2^((d+1)%4)
            matched=true;break
          end
        end
        if not matched then return nil,"TRAM_DRAG_NOT_CONNECTED" end
      end
    end
    for _,id in ipairs(ids) do
      local request=arg or requests[id]
      if request==nil then return nil,"INVALID_PARAMETER" end
      local p,cost=propose(s,owner,kind,id,request,occupancy)
      if p then
        items[#items+1]={id=id,record=p}
        total=total+cost
      elseif cost~="ALREADY_BUILT" or kind~="road" then
        return nil,cost,id
      end
    end
    if #items==0 then return nil,"ALREADY_BUILT" end
    return items,total
  end
  function N.construct(s,owner,kind,ids,arg,occupancy)
    local items,cost,failed=N.plan(s,owner,kind,ids,arg,occupancy)
    if not items then return nil,cost,failed end
    local company=s.companies[owner]
    if (company and company.cash or 100000)<cost then return nil,"NOT_ENOUGH_MONEY" end
    company=company or Sim.company(s,owner)
    company.cash=company.cash-cost
    company.expense=company.expense+cost
    company.month_exp=company.month_exp+cost
    local dirty={}
    for i,p in ipairs(items) do s.tiles[p.id].tram=p.record;dirty[i]=p.id end
    s.topology=s.topology+1
    return dirty,cost
  end
  function N.board(s,occupancy)
    local B={xy=Sim.xy,tile_at=Sim.id}
    function B.tile(id)
      local p=load(s,id)
      if p and p.tramtype then return p end
    end
    function B.tram_bits(id) return T.effective_bits(B.tile(id),false) end
    function B.adjacent(id,d) return Sim.adjacent(id,4-d) end
    function B.center_z(id)
      local _,height=shape(s,id)
      return height and height*8
    end
    function B.edge_available(from,to)
      local a,b=B.tile(from),B.tile(to)
      return playable(s,from,a) and playable(s,to,b) and a.base==b.base or false
    end
    function B.stop_continues(a,b)
      local t,u=B.tile(a),B.tile(b)
      return t and u and t.kind=="drive_stop" and u.kind=="drive_stop" and
        t.station==u.station and t.dir==u.dir and t.stop_type==u.stop_type or false
    end
    function B.stop_entry(id,d)
      return occupancy and occupancy.drive_length and occupancy.drive_length(id,d) or 0,16
    end
    function B.station_area(id,facility)
      local t=B.tile(id)
      if t and t.kind=="drive_stop" and t.station==id and t.stop_type==facility then
        return {tile=id,w=1,h=1},id
      end
    end
    B.cache_trimmed_station_area=B.station_area
    function B.can_build_tram(v,id,requested)
      if not v.owner then return false end
      local p,reason=propose(s,v.owner,"road",id,requested)
      return p~=nil or reason=="ALREADY_BUILT"
    end
    return B
  end
  return N
end
