-- Validate the normal road gesture, then quote and commit it inside the
-- authoritative Lua VM. Only finite typed values cross the mailbox.
return function(Sim,s,oneway,Bank)
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
    if op=="oneway" then
      if not oneway then return nil,"ONEWAY_REQUIRES_STOCK_ROAD_CLOCK" end
      if request.axis~=0 and request.axis~=1 then return nil,"INVALID_AXIS" end
      return oneway.quote(s,player,first,last,request.axis,{start_half=request.start_half==true,
        end_half=request.end_half==true})
    elseif op=="drag" then
      if request.axis~=0 and request.axis~=1 then return nil,"INVALID_AXIS" end
      return Sim.autoroad_plan(s,player,first,last,request.axis,request.start_half,request.end_half)
    elseif op=="bend" then
      return Sim.autoroad_bend_plan(s,player,first,last)
    elseif op=="fund_bank" and first==last and Bank then
      local q,why=Bank.plan(s,first)
      if not q then return nil,Bank.reason(why) end
      local changes={}
      for i,id in ipairs(q.clears) do changes[i]={id=id,tool="fund_bank",foundation=q.town} end
      return {cost=q.price,changes=changes,bank=q}
    elseif op=="truck_stop" and first==last then
      if not (s.road_mail and s.road_stock_house_supply) and not Sim.road_coal_active(s)
        and not Sim.road_timber_active(s) and not Sim.road_farm_active(s) and not Sim.road_oil_active(s) and not Sim.road_heavy_active(s) and not Sim.road_bank_active(s) then
        return nil,"No stock mail or freight service in this campaign."
      end
      if s.tiles[first].station then return nil,"Build a new truck stop rather than converting a station." end
      local changes,cost=Sim.plan(s,player,"road_station",{first})
      if not changes then return nil,cost end
      return {changes=changes,cost=cost}
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
      ids[i]=c.id or c.tile
      parts[i]=table.concat({tostring(ids[i]),tostring(c.build),tostring(c.road_bits),
        tostring(c.h),tostring(c.tool),tostring(c.disallowed),tostring(c.foundation)},":")
    end
    return {tiles=ids,cost=q.cost,topology=s.topology,terrain=s.corner_grid and s.corner_grid.revision,stopped_at=q.stopped_at,ticket=table.concat(parts,"/")}
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
    if type(published)~="table" or published.topology~=current.topology or published.terrain~=current.terrain or published.cost~=current.cost or published.ticket~=current.ticket
      or published.stopped_at~=current.stopped_at then return false,"ROAD_QUOTE_CHANGED" end
    local first,last=request.first,request.last or request.first
    if request.tool=="oneway" then
      local ok,cost,ids=oneway.commit(s,player,q)
      if not ok then return false,cost end
      local note=("%d road tiles updated for $%d."):format(#ids,cost)
      if #q.skipped>0 then note=note..(" %d skipped."):format(#q.skipped) end
      return true,note,ids
    elseif request.tool=="drag" then
      return Sim.autoroad_build(s,player,first,last,request.axis,request.start_half,request.end_half)
    elseif request.tool=="bend" then
      return Sim.autoroad_bend_build(s,player,first,last)
    elseif request.tool=="fund_bank" then
      local bank,ids=Bank.execute(s,player,first,q.bank)
      if not bank then return false,Bank.reason(ids) end
      return true,("Bank founded for $%d."):format(q.cost),ids
    elseif request.tool=="truck_stop" then
      local ok,note,ids=Sim.build_truck_stop(s,player,first)
      if ok then
        local st=s.stations[s.tiles[first].station]
        st.freight_art=true;st.coal_art=Sim.road_coal_active(s) or nil
        if Sim.road_bits(s,first)==0 then note="Truck stop built. Connect it to the road before ordering trucks." end
      end
      return ok,note,ids
    end
    return Sim.build(s,player,request.tool,{first})
  end
  return M
end
