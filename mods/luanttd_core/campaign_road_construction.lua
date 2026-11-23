-- Validate the normal road gesture, then quote and commit it inside the
-- authoritative Lua VM. Only finite typed values cross the mailbox.
return function(Sim,s)
  local M={}
  local function valid(id) return type(id)=="number" and id%1==0 and s.tiles[id]~=nil end
  local methods={}
  for _,op in ipairs({"road_station","road_depot","road_bay_pair","clear"}) do methods[op]=true end
  local function plan(player,request)
    if type(request)~="table" or not valid(request.first) then return nil,"INVALID_TILE" end
    local first,last,op=request.first,request.last or request.first,request.tool
    if not valid(last) then return nil,"INVALID_TILE" end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if math.abs(x-u)+math.abs(z-v)>=128 then return nil,"ROAD_DRAG_TOO_LONG" end
    if op=="drag" then
      if request.axis~=0 and request.axis~=1 then return nil,"INVALID_AXIS" end
      return Sim.autoroad_plan(s,player,first,last,request.axis,request.start_half,request.end_half)
    elseif op=="bend" then
      return Sim.autoroad_bend_plan(s,player,first,last)
    elseif methods[op] and first==last then
      local changes,cost=Sim.plan(s,player,op,{first})
      if not changes then return nil,cost end
      return {changes=changes,cost=cost}
    end
    return nil,"INVALID_ROAD_GESTURE"
  end
  local function summary(q)
    local ids,parts={},{}
    for i,c in ipairs(q.changes) do
      ids[i]=c.id
      parts[i]=table.concat({tostring(c.id),tostring(c.build),tostring(c.road_bits),
        tostring(c.h),tostring(c.tool)},":")
    end
    return {tiles=ids,cost=q.cost,topology=s.topology,stopped_at=q.stopped_at,ticket=table.concat(parts,"/")}
  end
  function M.quote(player,request)
    local q,why=plan(player,request)
    if not q then return nil,why end
    return summary(q)
  end
  function M.commit(player,request,published)
    local q,why=plan(player,request)
    if not q then return false,why end
    local current=summary(q)
    if type(published)~="table" or published.topology~=current.topology or published.cost~=current.cost or published.ticket~=current.ticket
      or published.stopped_at~=current.stopped_at then return false,"ROAD_QUOTE_CHANGED" end
    local first,last=request.first,request.last or request.first
    if request.tool=="drag" then
      return Sim.autoroad_build(s,player,first,last,request.axis,request.start_half,request.end_half)
    elseif request.tool=="bend" then
      return Sim.autoroad_bend_build(s,player,first,last)
    end
    return Sim.build(s,player,request.tool,{first})
  end
  return M
end
