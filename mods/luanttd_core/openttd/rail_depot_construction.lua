-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 16.0-RC1 CmdBuildTrainDepot,
-- CanBuildDepotByTileh, and CcRailDepot/PlaceExtraDepotRail.
return function(T,Q)
  local D={MIN_BRIDGE_HEIGHT=3,TILE_HEIGHT_STEP=8}
  local edges={[0]=12,6,3,9}
  local raw={[0]=true,[23]=true,[27]=true,[29]=true,[30]=true}
  for i=1,14 do raw[i]=true end
  local order={
    [0]={{T.LEFT,T.SE},{T.X,T.SW},{T.LOWER,T.NW}},
    [1]={{T.UPPER,T.SW},{T.Y,T.NW},{T.LEFT,T.NE}},
    [2]={{T.UPPER,T.SE},{T.X,T.NE},{T.RIGHT,T.NW}},
    [3]={{T.RIGHT,T.SW},{T.Y,T.SE},{T.LOWER,T.NE}},
  }
  local fallback=Q and Q.base_prices()
  local function cost(o,k) return o.prices and o.prices[k] or fallback[k] end

  function D.can_build_slope(dir,shape)
    if not edges[dir] or not raw[shape] then return false end
    if shape==0 then return true end
    local raised=T.intersect(shape,edges[dir])
    return shape>=16 and raised==edges[dir] or shape<16 and raised~=0
  end

  -- Render and physical rail use the level foundation at the highest
  -- corner, not GetRailFoundation for an ordinary through track.
  function D.surface(shape,base)
    if not raw[shape] or type(base)~="number" then return end
    local rise=shape>=16 and 2 or shape~=0 and 1 or 0
    return 0,base+rise,rise==0 and "none" or "leveled"
  end

  -- LandscapeClear is a separate DC_AUTO | DC_NO_WATER command. The
  -- adapter must quote it against the actual tile and supply authoritative
  -- owner, bridge deck, vehicle and reservation information.
  function D.quote(tile,dir,o)
    o=o or {}
    local railtype=o.railtype or 0
    local rail_cost=Q.rail_price(railtype,o)
    if not tile or not edges[dir] or rail_cost==nil or o.available==false or
        not raw[tile.slope] then return nil,"INVALID_PARAMETER" end
    local shape=tile.slope
    if shape~=0 and o.build_on_slopes==false then return nil,"FLAT_LAND_REQUIRED" end
    if not D.can_build_slope(dir,shape) then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION" end
    local _,level,foundation=D.surface(shape,tile.base_level or 0)
    local rotating=tile.kind=="depot" and (tile.railtype or 0)==railtype
    local plan={railtype=railtype,direction=dir,trackbits=2^(dir%2),shape=shape,level=level,
      foundation=foundation,rotate=rotating}
    if rotating then
      if tile.owner~=o.owner then return nil,"OWNED_BY_ANOTHER" end
      if dir==tile.dir then plan.noop=true;plan.cost=0;return plan end
      if tile.occupied then return nil,"VEHICLE_IN_THE_WAY" end
      -- Caller executes FreeTrainTrackReservation and TryPathReserve when
      -- it can update that train transactionally, or refuses safely.
      plan.rereserve=tile.reserved or nil
    end
    local clear=0
    if not rotating then
      local why
      if not o.clear then return nil,"LANDSCAPE_CLEAR_REQUIRED" end
      clear,why=o.clear(tile)
      if clear==nil then return nil,why end
      if tile.overhead then
        if type(tile.deck)~="number" then return nil,"UNKNOWN_BRIDGE_HEIGHT" end
        local diff=level+D.MIN_BRIDGE_HEIGHT-tile.deck
        if diff>0 then return nil,"BRIDGE_TOO_LOW_FOR_TRAIN_DEPOT",diff*D.TILE_HEIGHT_STEP end
      end
      if o.pool_full then return nil,"DEPOT_POOL_FULL" end
    end
    plan.parts={clearing=clear,foundation=shape==0 and 0 or cost(o,"foundation"),
      depot=cost(o,"depot"),rail=rail_cost}
    local c=plan.parts
    plan.cost=c.clearing+c.foundation+c.depot+c.rail
    return plan
  end

  -- CcRailDepot is an independently paid, best-effort GUI callback.
  -- A failed/missing piece never prevents a later candidate from trying.
  -- Re-enter the fresh map before each post: successful previous pieces
  -- can change the reachable sides of the mouth during this command.
  function D.connect(board,id,dir,o,buy)
    if not order[dir] then return 0 end
    local front=board.adjacent(id,dir)
    if not front then return 0 end
    local t=board.tile(front)
    if not t or t.kind~="rail" and t.kind~="signals" then return 0 end
    local across=board.adjacent(front,dir)
    local count=0
    for i,c in ipairs(order[dir]) do
      local there=across and i==2 and board.tile(across)
      t=board.tile(front)
      if t and (t.kind=="rail" or t.kind=="signals" and o and o.auto_remove_signals) and
          not (there and there.kind=="depot") and
          T.intersect(t.trackbits,T.trackbits(T.reachable(c[2])))~=0 and buy(front,c[1]) then
        count=count+1
      end
    end
    return count
  end

  return D
end
