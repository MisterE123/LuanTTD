-- Bridge the stock station's physical member tiles, spread and facility
-- areas to the saved road station ID. The same station retains its cargo
-- queue and sign when another platform joins.
return function(Sim)
  local M={}
  local function bounds(tiles)
    local minx,minz,maxx,maxz=math.huge,math.huge,-math.huge,-math.huge
    for id in pairs(tiles) do
      local x,z=Sim.xy(id)
      minx,minz=math.min(minx,x),math.min(minz,z)
      maxx,maxz=math.max(maxx,x),math.max(maxz,z)
    end
    if minx==math.huge then return nil end
    return {tile=Sim.id(minx,minz),w=maxx-minx+1,h=maxz-minz+1}
  end
  function M.current(st)
    if st.road_members then return st.road_members end
    return {[st.tile]=st.stop_type or "bus"}
  end
  function M.preview(st,parts)
    local members={}
    if st then for id,kind in pairs(M.current(st)) do members[id]=kind end end
    for _,part in ipairs(parts) do members[part.id]=part.kind end
    local as_bus,as_truck={},{}
    for id,kind in pairs(members) do
      if kind=="bus" then as_bus[id]=true
      elseif kind=="truck" then as_truck[id]=true end
    end
    local spread=bounds(members)
    local road_stop_areas={bus=bounds(as_bus),truck=bounds(as_truck)}
    local sign=st and st.tile or spread and spread.tile
    if sign and spread then
      local x,z=Sim.xy(sign)
      local a,b=Sim.xy(spread.tile)
      sign=Sim.id(math.max(a,math.min(x,a+spread.w-1)),math.max(b,math.min(z,b+spread.h-1)))
    end
    return {road_members=members,road_stop_areas=road_stop_areas,spread=spread,sign=sign}
  end
  function M.structural_apply(st,q)
    st.road_members,st.road_stop_areas,st.spread=q.road_members,q.road_stop_areas,q.spread
    st.tile=q.sign
    local function anchor(kind)
      if q.road_members[q.sign]==kind then return q.sign end
      local found
      for id,t in pairs(q.road_members) do
        if t==kind and (not found or id<found) then found=id end
      end
      return found
    end
    st.bus_tile,st.truck_tile=anchor("bus"),anchor("truck")
    st.stop_type=q.road_stop_areas.truck and not q.road_stop_areas.bus and "truck" or nil
  end
  return M
end
