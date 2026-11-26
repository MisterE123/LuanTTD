-- Isolated host adapter for the stock port facilities and water board.
-- No ground infrastructure or legacy route is converted implicitly.
return function(Sim,Terrain,Water,Facilities)
  local N={}
  local function water_class(t)
    if t.build=="canal" then return "canal" end
    if t.terrain=="water" then return t.water_class or "sea" end
  end
  local function read(s,id)
    local t=id and s.tiles[id]
    if not t or t.stock_void or not s.corner_grid then return end
    local x,z=Sim.xy(id)
    local slope,base,top=Terrain.tile(s.corner_grid,x,z)
    local deck,overhead=Sim.bridge_deck_at(s,id)
    local out={slope=slope,base=base,top=top,owner=t.owner,overhead=overhead,bridge_deck=deck}
    if t.ship then
      for k,v in pairs(t.ship) do out[k]=v end
      return out
    end
    if t.rail_tracks and t.rail_ground==13 and not (t.level_crossing or t.rail_station_id or t.rail_depot_dir~=nil or t.rail_waypoint_id) then
      out.kind,out.rail_bits,out.plain="shore_rail",t.rail_tracks,true
      return out
    end
    if t.coastal_water then
      out.kind,out.water_class,out.is_coast="coast","sea",true
      out.water_ground,out.is_water_tile=false,false
      out.rocks=t.stock_water_rocks
      return out
    end
    local cls=water_class(t)
    local mark=t.stock_industry
    if type(mark)=="table" and mark.chain=="oil" and mark.kind=="rig" then
      local firm=(s.stock_oil_industries or {})[mark.id]
      out.kind,out.water_class,out.water_ground="industry",cls,not not cls
      out.neutral_station=firm and firm.neutral_station
      return out -- preserve underlying water class, never permit sailing through a platform
    end
    if cls and (not t.build or t.build=="canal") then
      out.kind,out.water_class,out.water_ground,out.is_water_tile=cls,cls,true,not t.stock_water_rocks
      out.rocks=t.stock_water_rocks
      return out
    end
    if t.house or t.wood or t.site or t.build or t.tram or t.airfield or t.stock_industry or t.stock_landmark or t.owner then
      out.kind="protected"
    else
      out.kind="clear"
    end
    return out
  end
  function N.board(s,occupancy)
    local B={xy=Sim.xy,tile_at=Sim.id}
    function B.tile(id) return read(s,id) end
    function B.adjacent(id,d) return id and Sim.adjacent(id,4-d) end
    function B.ship_depot(id)
      local t=B.tile(id)
      if t and t.kind=="ship_depot" then return s.stock_ship_depots[t.depot] end
    end
    function B.is_docking(id)
      local t=B.tile(id)
      if not t or (t.kind=="lock" and t.part=="middle") or Water.at(B,id)==0 then return false end
      for d=0,3 do
        local n=B.tile(B.adjacent(id,d))
        if n and (n.kind=="dock" and n.water_part or n.kind=="oilrig" or n.kind=="industry" and n.neutral_station) then
          return true
        end
      end
      return false
    end
    function B.docking_occupancy(id)
      return occupancy and occupancy(id) or 0
    end
    function B.station_dock_tiles(id)
      local st=s.stock_ship_stations and s.stock_ship_stations[id]
      if not st then return {} end
      if not st.neutral or not st.oil_rig then return Facilities.docking_neighbors(B,st.water) end
      local neutral=(s.stock_neutral_stations or {})[id]
      local rec=neutral and (s.stock_oil_placements or {})[neutral.industry]
      if not rec or rec.closed then return {} end
      local docks,seen={},{}
      for _,c in ipairs(rec.cells) do
        for _,tile in ipairs(Facilities.docking_neighbors(B,c.id)) do
          if not seen[tile] then docks[#docks+1]=tile;seen[tile]=true end
        end
      end
      table.sort(docks)
      return docks
    end
    function B.closest_station_tile(id,origin)
      local st=s.stock_ship_stations and s.stock_ship_stations[id]
      if not st then return nil end
      local a,b=st.land,st.water
      if Sim.distance(origin,b)<Sim.distance(origin,a) then return b end
      return a
    end
    return B
  end
  -- Existing overpasses are independent of the shoreline; keep the
  -- guard for the other native railway layers, not a rail deck above.
  function N.rail_water_obstruction(s,id)
    local t=s.tiles[id]
    return t.rail_span_id or t.level_crossing or t.rail_waypoint_id or
      s.rail_tunnel_below and s.rail_tunnel_below[id]
  end
  local function clear(s,owner,id,t)
    if N.rail_water_obstruction(s,id) then return nil,"PROTECTED_TILE" end
    if s.tunnel_below and s.tunnel_below[id] then return nil,"SUBSURFACE_RESERVED" end
    local host=s.tiles[id]
    if host.wood then return nil,"DOCK_CLEAR_TREES" end
    if host.ship or host.house or host.site or host.tram or host.airfield or
        host.stock_industry or host.stock_landmark or host.build and host.build~="canal" then
      return nil,"PROTECTED_TILE"
    end
    -- RC1 ClearRocks isn't plain water. CmdBuildDock, CmdBuildShipDepot
    -- and CmdBuildBuoy include its LandscapeClear cost before replacing it.
    if t.rocks then
      local cells,price=Sim.clear_water(s,owner,id,true)
      if cells then return price end
      return nil,price
    end
    -- OpenTTD 14.1 ClearTile_Water: a WATER_TILE_COAST on the
    -- two-raised-corner slope CmdBuildDock allows costs PR_CLEAR_ROUGH.
    -- The dock overlay keeps our base coast intact for later removal.
    if t.kind=="coast" and not host.owner then return 40 end
    if t.kind=="clear" or t.kind=="sea" or t.kind=="river" or t.kind=="canal" then return 0 end
    return nil,"PROTECTED_TILE"
  end
  local function protected_buoy_site(s,id,t)
    local host=s.tiles[id]
    if N.rail_water_obstruction(s,id) or
        s.tunnel_below and s.tunnel_below[id] then return "PROTECTED_TILE" end
    -- The native host cannot auto-clear industry/object/station water
    -- underneath other facilities. Preserve their existing overlays.
    if host.ship or host.tram or host.airfield or host.stock_industry or host.stock_landmark or
        host.house or host.site or host.wood or host.build and host.build~="canal" then
      return "PROTECTED_TILE"
    end
    if not t or not (t.is_water_tile or t.rocks and t.kind=="sea") then return "BUOY_NEEDS_OPEN_WATER" end
  end
  function N.quote(s,owner,kind,id,arg)
    if not s.corner_grid or not id or not s.tiles[id] then return nil,"INVALID_TILE" end
    local B=N.board(s)
    local opts={clear=function(i,t) return clear(s,owner,i,t) end,
      budget=s.companies[owner] and s.companies[owner].cash or 100000}
    if kind=="dock" then return Facilities.dock(B,id,opts) end
    if kind=="depot" then return Facilities.depot(B,id,arg,opts) end
    if kind=="buoy" then
      local why=protected_buoy_site(s,id,B.tile(id))
      if why then return nil,why,id end
      return Facilities.buoy(B,id,opts)
    end
    return nil,"INVALID_FACILITY"
  end
  function N.build(s,owner,kind,id,arg)
    local p,why,at=N.quote(s,owner,kind,id,arg)
    if not p then return nil,why,at end
    local c=Sim.company(s,owner)
    if kind=="dock" then
      s.stock_ship_stations=s.stock_ship_stations or {}
      local next_=s.next_stock_ship_station or 1
      s.next_stock_ship_station=next_+1
      s.stock_ship_stations[next_]={id=next_,owner=owner,land=p.land,water=p.water,dir=p.dir,
        station_area=p.station_area,approach=p.approach,water_class=p.water_class}
      s.tiles[p.land].stock_water_rocks=nil
      s.tiles[p.water].stock_water_rocks=nil
      s.tiles[p.land].ship={kind="dock",station=next_,owner=owner,dir=p.dir,water_part=false}
      s.tiles[p.water].ship={kind="dock",station=next_,owner=owner,dir=p.dir,
        water_part=true,water_class=p.water_class,water_ground=true}
      p.id=next_
    elseif kind=="buoy" then
      s.stock_ship_buoys=s.stock_ship_buoys or {}
      local next_=s.next_stock_ship_station or 1
      s.next_stock_ship_station=next_+1
      s.stock_ship_buoys[next_]={id=next_,tile=id}
      s.tiles[id].stock_water_rocks=nil
      s.tiles[id].ship={kind="buoy",station=next_,owner=p.water_owner,
        water_class=p.water_class,water_ground=true}
      p.id=next_
    else
      s.stock_ship_depots=s.stock_ship_depots or {}
      local next_=s.next_stock_ship_depot or 1
      s.next_stock_ship_depot=next_+1
      s.stock_ship_depots[next_]={id=next_,owner=owner,tiles=p.tiles,axis=p.axis}
      for i,tile in ipairs(p.tiles) do
        s.tiles[tile].stock_water_rocks=nil
        s.tiles[tile].ship={kind="ship_depot",owner=owner,depot=next_,axis=p.axis,
          part=i,water_class=p.water_classes[i],water_ground=true}
      end
      p.id=next_
    end
    c.cash,c.expense,c.month_exp=c.cash-p.cost,c.expense+p.cost,c.month_exp+p.cost
    s.topology=s.topology+1
    return p
  end
  -- Remove both parts. Underlying water class is preserved because the
  -- facility never consumed the original ground fields. Dynamic berth
  -- lookup reevaluates neighbours on the following query, including when
  -- a nearby dock still shares a navigable berth.
  function N.remove(s,owner,id,occupied,quote)
    local t=id and s.tiles[id] and s.tiles[id].ship
    if not t or t.kind~="buoy" and t.owner~=owner then return nil,"SELECT_OWN_FACILITY" end
    local entries,p,tiles,cost
    if t.kind=="ship_depot" then
      entries=s.stock_ship_depots
      p=entries and entries[t.depot]
      if not p then return nil,"INVALID_FACILITY" end
      if s.stock_owned_oil_ship and s.stock_owned_oil_ship.depot==p.id then return nil,"DEPOT_HAS_OIL_SHIP" end
      if s.stock_coal_ship and s.stock_coal_ship.depot==p.id then return nil,"DEPOT_HAS_OWNED_SHIP" end
      if s.stock_owned_ferry and s.stock_owned_ferry.depot==p.id then return nil,"DEPOT_HAS_PASSENGER_FERRY" end
      tiles,cost=p.tiles,90 -- PR_CLEAR_DEPOT_SHIP
    elseif t.kind=="dock" then
      entries=s.stock_ship_stations
      p=entries and entries[t.station]
      if not p then return nil,"INVALID_FACILITY" end
      local tanker=s.stock_oil_ship_route
      if tanker and (tanker.first==p.id or tanker.second==p.id) then return nil,"DOCK_HAS_OIL_SERVICE" end
      tiles,cost={p.land,p.water},55 -- PR_CLEAR_STATION_DOCK
    elseif t.kind=="buoy" then
      entries=s.stock_ship_buoys
      p=entries and entries[t.station]
      if not p or p.tile~=id then return nil,"INVALID_FACILITY" end
      for _,name in ipairs({"ship_pilot","stock_coal_ship_run","stock_oil_ship_route"}) do
        local run=s[name]
        if run then
          local v=run.vehicle
          -- Stock disallows another company's orders. This constrained
          -- shuttle also requires withdrawing its own active order first;
          -- live editing of a running order list isn't mounted here.
          if run.via and run.via.id==p.id or v and v.order and v.order.kind=="waypoint" and v.order.tile==id then
            return nil,"BUOY_IN_USE"
          end
          if v and (v.tile==id or v.x and v.y and Sim.id(math.floor(v.x/16),math.floor(v.y/16))==id) then
            return nil,"VEHICLE_IN_THE_WAY"
          end
        end
      end
      for _,v in pairs(s.fleet or {}) do
        local engine=Sim.vehicles and Sim.vehicles[v.engine]
        if engine and engine.mode=="water" and Sim.position(s,v)==id then return nil,"VEHICLE_IN_THE_WAY" end
      end
      tiles,cost={id},Facilities.BUOY_CLEAR_COST
    else return nil,"INVALID_FACILITY" end
    if occupied then
      for _,cell in ipairs(tiles) do if occupied(cell) then return nil,"VEHICLE_IN_THE_WAY" end end
    end
    local c=s.companies[owner]
    if not c or c.cash<cost then return nil,"NOT_ENOUGH_MONEY" end
    if quote then return tiles,cost end
    entries[p.id]=nil
    for _,key in ipairs(tiles) do s.tiles[key].ship=nil end
    c.cash,c.expense,c.month_exp=c.cash-cost,c.expense+cost,c.month_exp+cost
    s.topology=s.topology+1
    return tiles,cost
  end
  return N
end
