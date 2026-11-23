-- The worker keeps the canonical terrain and uses the very same command
-- and exact footprint as the native builder interface.
return function(Sim,s)
  local M={}
  local function id(x)
    return type(x)=="number" and x>=1 and x<=Sim.W*Sim.H and x%1==0
  end
  function M.quote(owner,request)
    if type(request)~="table" or not id(request.first) or request.last~=nil and not id(request.last) then
      return nil,"INVALID_TERRAIN_SELECTION"
    end
    local first,last=request.first,request.last
    local op=request.operation
    local x,z=Sim.xy(first)
    local u,v
    if last then
      u,v=Sim.xy(last)
      if (math.abs(u-x)+1)*(math.abs(v-z)+1)>256 then return nil,"TERRAIN_SELECTION_TOO_LARGE" end
    end
    local a={operation=op,first=first,last=last,diagonal=request.diagonal==true}
    if op=="bulldoze" then
      local plan,why=Sim.clear_area(s,owner,first,last or first,a.diagonal,false)
      if not plan then return nil,why end
      return {request=a,cost=plan.cost,tiles=plan.ids,topology=s.topology,terrain=s.corner_grid.revision}
    end
    if op~="raise" and op~="lower" and op~="level" then return nil,"UNSUPPORTED_TERRAIN_GESTURE" end
    local ok,price,p=Sim.landscape(s,owner,op,x,z,u,v,a.diagonal,"footprint")
    if not ok then return nil,price end
    local tiles={}
    for _,t in ipairs(p.tiles) do
      local tile=Sim.id(t.x,t.z)
      if tile then tiles[#tiles+1]=tile end
    end
    return {request=a,cost=price,tiles=tiles,corners=p.corners,topology=p.topology,terrain=p.terrain_revision}
  end
  local function same(a,b)
    if #a~=#b then return false end
    for i,x in ipairs(a) do
      local y=b[i]
      if type(x)=="table" then
        if x.x~=y.x or x.z~=y.z or x.height~=y.height then return false end
      elseif x~=y then return false end
    end
    return true
  end
  function M.commit(owner,quote)
    local q,why=M.quote(owner,quote.request)
    if not q then return false,why end
    if q.cost~=quote.cost or q.topology~=quote.topology or q.terrain~=quote.terrain
      or not same(q.tiles,quote.tiles) or not same(q.corners or {},quote.corners or {}) then
      return false,"TERRAIN_QUOTE_CHANGED"
    end
    local r=q.request
    if r.operation=="bulldoze" then
      local changed,why=Sim.clear_area(s,owner,r.first,r.last or r.first,r.diagonal,true)
      if not changed then return false,why end
      return true,("Bulldozed %d tile(s) for $%d."):format(#changed.ids,changed.cost),changed.dirty
    end
    local x,z=Sim.xy(r.first)
    local u,v
    if r.last then u,v=Sim.xy(r.last) end
    return Sim.landscape(s,owner,r.operation,x,z,u,v,r.diagonal)
  end
  return M
end
