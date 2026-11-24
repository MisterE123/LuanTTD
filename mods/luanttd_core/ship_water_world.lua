-- Read-only stock construction queries and atomic flat canal mutation.
-- Lock gameplay can use the same board once native gate assets are ready.
return function(Sim,Network,Construction)
  local M={}
  local function board(s)
    local b=Network.board(s)
    b.version=function()return s.topology end
    return b
  end
  local function options(s,owner)
    local cash=s.companies[owner] and s.companies[owner].cash or 100000
    local function clear(id,t,opts)
      local tile=s.tiles[id]
      if tile.ship or tile.tram or t.overhead or (Sim.rail_span_protected and Sim.rail_span_protected(s,id)) or
        s.tunnel_below and s.tunnel_below[id] then
        return nil,"LANDSCAPE_CLEAR_REQUIRED"
      end
      if t.kind=="clear" then return 0 end
      if t.is_water_tile or t.rocks and not t.is_coast then
        if tile.owner and tile.owner~="water" and tile.owner~=opts.owner then return nil,"OWNED_BY_ANOTHER" end
        return t.water_class=="canal" and Construction.CLEAR_CANAL or Construction.CLEAR_WATER
      end
      return nil,"LANDSCAPE_CLEAR_REQUIRED"
    end
    return {owner=owner,budget=cash,clear=clear}
  end
  local function finance(s,owner,plan)
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-plan.cost,c.expense+plan.cost,c.month_exp+plan.cost
    for _,op in ipairs(plan.infrastructure) do
      local holder=s.companies[op.owner]
      if holder then holder.water_infrastructure=(holder.water_infrastructure or 0)+op.delta end
    end
    s.topology=s.topology+1
  end
  function M.quote(s,owner,a,b,diagonal)
    if not (s.corner_grid and s.tiles[a] and s.tiles[b]) then return nil,"INVALID_PARAMETER" end
    local opts=options(s,owner)
    opts.diagonal=diagonal
    local plan,why,at=Construction.canal(board(s),a,b,"canal",opts)
    if plan and Sim.rail_span_protected then
      for id in pairs(plan.records) do
        if Sim.rail_span_protected(s,id) then return nil,"LANDSCAPE_CLEAR_REQUIRED",id end
      end
    end
    return plan,why,at
  end
  function M.build(s,owner,a,b,diagonal)
    local p,why,at=M.quote(s,owner,a,b,diagonal)
    if not p then return nil,why,at end
    local B=board(s)
    function B.commit(plan)
      local c=Sim.company(s,owner)
      if c.cash<plan.cost then return false,"NOT_ENOUGH_MONEY" end
      for id,r in pairs(plan.records) do
        local t=s.tiles[id]
        -- The ground remains at its shared corner elevation. Store the
        -- WaterClass independently of its neighbors.
        t.build,t.owner,t.terrain,t.water_class,t.stock_canal="canal",r.owner,"water",r.water_class,true
        t.stock_water_rocks=nil
      end
      finance(s,owner,plan)
      return true
    end
    local ok,error_=Construction.apply(B,p)
    if not ok then return nil,error_ end
    return p
  end
  function M.remove(s,owner,id,quote)
    local t=id and s.tiles[id]
    if not t or not t.stock_canal or t.build~="canal" or t.ship then return nil,"SELECT_OWN_CANAL" end
    return Sim.clear_water(s,owner,id,quote)
  end
  function M.quote_lock(s,owner,id,occupied)
    if not (s.corner_grid and id and s.tiles[id]) then return nil,"INVALID_PARAMETER" end
    local opts=options(s,owner)
    opts.ensure_empty=function(tile)
      return not (s.tiles[tile].ship or (Sim.rail_span_protected and Sim.rail_span_protected(s,tile)) or
        (occupied and occupied(tile)))
    end
    return Construction.lock(board(s),id,opts)
  end
  function M.build_lock(s,owner,id,occupied)
    local p,why,at=M.quote_lock(s,owner,id,occupied)
    if not p then return nil,why,at end
    local B=board(s)
    function B.commit(plan)
      local c=Sim.company(s,owner)
      if c.cash<plan.cost then return false,"NOT_ENOUGH_MONEY" end
      s.stock_ship_locks=s.stock_ship_locks or {}
      s.stock_ship_locks[plan.middle]={owner=owner,middle=plan.middle,lower=plan.lower,upper=plan.upper,
        dir=plan.dir,tiles=plan.tiles}
      for cell,record in pairs(plan.records) do
        local tile=s.tiles[cell]
        tile.ship=record
        tile.stock_water_rocks=nil
        if record.part~="middle" and record.water_class=="canal" and tile.build~="canal" then
          tile.terrain,tile.build,tile.water_class,tile.owner,tile.stock_canal=
            "water","canal","canal",record.owner,true
        end
      end
      finance(s,owner,plan)
      return true
    end
    local ok,msg=Construction.apply(B,p)
    if not ok then return nil,msg end
    return p
  end
  function M.remove_lock(s,owner,id,quote,occupied)
    local t=id and s.tiles[id] and s.tiles[id].ship
    local lock=t and t.kind=="lock" and s.stock_ship_locks and s.stock_ship_locks[t.lock_middle]
    if not lock or lock.owner~=owner then return nil,"SELECT_OWN_LOCK" end
    local c=s.companies[owner]
    local clearing=2000 -- PR_CLEAR_LOCK
    if not c or c.cash<clearing then return nil,"NOT_ENOUGH_MONEY" end
    for _,cell in ipairs(lock.tiles) do
      if occupied and occupied(cell) then return nil,"VEHICLE_IN_THE_WAY" end
    end
    if quote then return lock.tiles,clearing end
    local center=s.tiles[lock.middle]
    local river=center.ship.water_class=="river"
    center.build,center.terrain,center.water_class,center.stock_canal,center.owner=
      nil,river and "water" or "grass",river and "river" or nil,nil,nil
    for _,cell in ipairs(lock.tiles) do s.tiles[cell].ship=nil end
    s.stock_ship_locks[lock.middle]=nil
    c.cash,c.expense,c.month_exp=c.cash-clearing,c.expense+clearing,c.month_exp+clearing
    c.water_infrastructure=(c.water_infrastructure or 0)-3*Construction.LOCK_DEPOT_TILE_FACTOR
    s.topology=s.topology+1
    return lock.tiles,clearing
  end
  return M
end
