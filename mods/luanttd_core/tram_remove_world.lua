-- Normal ELRL tram layer adapter for OpenTTD 16.0-RC1 RemoveRoad /
-- CmdRemoveLongRoad. The co-located roadway retains its own geometry,
-- owner, town association and one-way signs.
return function(Sim,Terrain,Slope,Sweep)
  local M={}
  local board={xy=Sim.xy}
  function board.next(id,axis) return Sim.adjacent(id,axis==0 and 2 or 3) end
  local function count(bits)
    local n=0
    while bits>0 do n=n+bits%2;bits=math.floor(bits/2) end
    return n
  end
  function M.plan(s,owner,req,busy)
    local company=s.companies[owner]
    if not company or not s.corner_grid or not busy then return nil,"PARAMETERS" end
    local first,last=req.first,req.last or req.first
    if not s.tiles[first] or not s.tiles[last] then return nil,"PARAMETERS" end
    local a,b=Sim.xy(first)
    local x,z=Sim.xy(last)
    if math.abs(x-a)+math.abs(z-b)>=128 then return nil,"PARAMETERS" end
    local cells,why=Sweep.request(board,first,last,req.axis,req.start_half==true,req.end_half==true)
    if not cells then return nil,why end
    local policy=s.stock_road_town_policy or {}
    local function quote(id,bits)
      local t=s.tiles[id]
      local tr=t and t.tram
      if not tr or tr.tramtype~=1 or not tr.tram_bits or tr.tram_bits==0 then return nil,"NO_TRAM" end
      if tr.kind~="road" or t.level_crossing or t.road_waypoint_id or t.station or t.road_tunnel_id
          or t.road_bridge_id or t.rail_span_id or t.stock_void then return nil,"TRAM_FACILITY_PROTECTED" end
      if tr.tram_owner and tr.tram_owner~=owner then return nil,"OWNED_BY" end
      if busy(id) then return nil,"VEHICLE_IN_THE_WAY" end
      if t.roadworks then return nil,"ROAD_WORKS_IN_PROGRESS" end
      local u,v=Sim.xy(id)
      local slope=Terrain.tile(s.corner_grid,u,v)
      local edit,err=Slope.remove(slope,bits,tr.tram_bits,Sim.road_bits(s,id),policy.build_on_slopes~=false)
      if not edit then return nil,err end
      return {id=id,tool="tram_remove",build=t.build,road_bits=Sim.road_bits(s,id),tram_bits=edit.road_bits,
        cost=count(edit.removed)*40+(edit.foundation and 250 or 0)}
    end
    local q,reason=Sweep.sweep(cells,quote,true,company.cash,function()end)
    if not q then return nil,reason end
    if #q.changes==0 then return nil,q.unfunded and "NOT_ENOUGH_CASH" or "NO_TRAM" end
    return q
  end
  function M.apply(s,owner,q)
    local company=s.companies[owner]
    local dirty={}
    for i,edit in ipairs(q.changes) do
      local t=s.tiles[edit.id]
      if edit.tram_bits==0 then t.tram=nil
      else t.tram.tram_bits=edit.tram_bits end
      dirty[i]=edit.id
    end
    company.cash=company.cash-q.cost
    company.expense=company.expense+q.cost
    company.month_exp=company.month_exp+q.cost
    s.topology=s.topology+1
    return true,("Removed tram track on %d tile%s for $%d."):format(#dirty,#dirty==1 and "" or "s",q.cost),dirty
  end
  return M
end
