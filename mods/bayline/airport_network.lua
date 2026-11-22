-- Saved Country Airfield facility adapter: ordinary, level, clean-ground
-- branch of OpenTTD 14.1 CmdBuildAirport / CheckFlatLandAirport.
-- Noise, stations shared across modes, foundation clearing and airport
-- replacement are explicit future work; the preview never clears objects.
return function(Sim,Terrain,Small)
  local N={PRICE_PER_TILE=600,CLEAR_PER_TILE=30}
  function N.footprint(origin)
    local tiles={}
    local x,z=Sim.xy(origin)
    for dz=0,Small.H-1 do for dx=0,Small.W-1 do
      local id=Sim.id(x+dx,z+dz)
      if id then tiles[#tiles+1]=id end
    end end
    return tiles
  end
  function N.quote(s,owner,origin)
    if not (s.corner_grid and origin and s.tiles[origin]) then return nil,"SELECT_AIRFIELD_ORIGIN" end
    local x,z=Sim.xy(origin)
    local airport={owner=owner,origin=origin,x=x*16,z=z*16,rotation=0,
      width=Small.W,height=Small.H,flags=0,tiles={}}
    local h
    for dz=0,Small.H-1 do for dx=0,Small.W-1 do
      local a=Sim.id(x+dx,z+dz)
      local t=a and s.tiles[a]
      if not t then return nil,"AIRPORT_OUTSIDE_REGION",a end
      local slope,level=Terrain.tile(s.corner_grid,x+dx,z+dz)
      if slope~=0 or h and level~=h then return nil,"AIRPORT_NEEDS_LEVEL_FIELD",a end
      if t.build or t.owner or t.terrain=="water" or t.tram or t.ship or t.airfield or
          t.site or t.house or t.wood or t.stock_industry or t.stock_landmark or (Sim.rail_span_protected and Sim.rail_span_protected(s,a)) or (s.bridge_above and s.bridge_above[a]) or
          (s.aqueduct_above and s.aqueduct_above[a]) or (s.tunnel_below and s.tunnel_below[a]) then
        return nil,"AIRPORT_SITE_OCCUPIED",a
      end
      h=level
      airport.tiles[#airport.tiles+1]={id=a,x=dx,z=dz}
    end end
    local town=Sim.nearest_town(s,origin)
    if town then
      airport.town=town.id
      local count=0
      for _,d in pairs(s.stock_small_airports or {}) do if d.town==town.id then count=count+1 end end
      if count>=2 then return nil,"TOWN_REFUSES_THIRD_AIRPORT" end
    end
    airport.ground=h*8
    airport.price=#airport.tiles*N.PRICE_PER_TILE
    local c=s.companies[owner]
    if (c and c.cash or 100000)<airport.price then return nil,"NOT_ENOUGH_MONEY" end
    return airport
  end
  local function expense(s,owner,cost)
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-cost,c.expense+cost,c.month_exp+cost
    s.topology=s.topology+1
  end
  function N.build(s,owner,origin)
    local airport,why,id=N.quote(s,owner,origin)
    if not airport then return nil,why,id end
    airport.id=s.next_small_airport or 1
    s.next_small_airport=airport.id+1
    s.stock_small_airports=s.stock_small_airports or {}
    s.stock_small_airports[airport.id]=airport
    local dirty={}
    for _,pos in ipairs(airport.tiles) do
      s.tiles[pos.id].airfield={airport=airport.id,x=pos.x,z=pos.z}
      dirty[#dirty+1]=pos.id
    end
    expense(s,owner,airport.price)
    return airport,dirty
  end
  function N.airport_for(s,cell)
    local t=cell and s.tiles[cell]
    local ref=t and t.airfield
    return ref and s.stock_small_airports[ref.airport]
  end
  function N.remove(s,owner,cell,quote,occupied)
    local airport=N.airport_for(s,cell)
    if not airport or owner~=airport.owner then return nil,"SELECT_OWN_AIRFIELD" end
    if airport.flags~=0 or occupied and occupied(airport.id) then return nil,"AIRCRAFT_OCCUPIES_AIRFIELD" end
    local cost=#airport.tiles*N.CLEAR_PER_TILE
    local c=s.companies[owner]
    if not c or c.cash<cost then return nil,"NOT_ENOUGH_MONEY" end
    local dirty={}
    for _,pos in ipairs(airport.tiles) do
      dirty[#dirty+1]=pos.id
      if not quote then s.tiles[pos.id].airfield=nil end
    end
    if not quote then s.stock_small_airports[airport.id]=nil;expense(s,owner,cost) end
    return dirty,cost
  end
  return N
end
