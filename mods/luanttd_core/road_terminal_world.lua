-- Native adapter for stock single-tile road terminal siting.
-- Stock planning retains command and placement callback separation:
-- optional frontage may fail without rolling back the terminal.
return function(Sim,Terrain,Stop,Underlay,rules)
  local W={}
  local flag={1,2,4,8}
  local axis_bits={[0]=10,5}
  local function match_owner(t,owner)
    return t.owner==nil or t.road_town or t.owner==owner
  end
  local function district(t)
    return t.stock_landmark or t.stock_industry or t.site or t.house
  end
  local function quote_clear(t)
    -- ClearTile_Clear in stock has zero price only for bare dirt; the
    -- ordinary generator's grass starts with full density and costs 20.
    if t.wood then
      local stands=type(t.wood)=="table" and (t.wood.count or 1) or 1
      return stands*20
    end
    local kind=t.stock_clear_ground or 0
    if kind==0 then return t.stock_clear_density==0 and 0 or 20 end
    return ({[1]=40,[2]=200,[3]=500,[5]=40})[kind]
  end
  function W.quote(s,owner,id,selected)
    local t=s.tiles[id]
    local c=s.companies[owner]
    local dir=selected.dir
    if not t or not c or t.stock_void or dir~=0 and dir~=1 and dir~=2 and dir~=3 then return nil,"PARAMETERS" end
    if not s.corner_grid or t.terrain=="water" or district(t) or t.ship or t.airfield or t.level_crossing or t.road_waypoint_id or
        t.rail_type~=nil or t.rail_tracks or t.rail_station_id or t.rail_depot_dir or t.road_bridge_id or t.road_tunnel_id or t.tram or s.stock_farm_fields and s.stock_farm_fields[id] then
      return nil,"PROTECTED_TERMINAL_TILE"
    end
    if not match_owner(t,owner) then return nil,"OWNED_BY" end
    local depot=selected.kind=="depot"
    local through=not depot and selected.through==true
    local kind=t.build=="road_depot" and "depot" or t.build=="road_station" and "station" or t.build=="road" and "road" or "clear"
    if t.build and kind=="clear" or depot and kind~="clear" and kind~="depot" or not depot and kind=="depot" or
        kind=="road" and not through then return nil,"PROTECTED_TERMINAL_TILE" end
    local tile_x,tile_z=Sim.xy(id)
    local slope,base,top=Terrain.tile(s.corner_grid,tile_x,tile_z)
    local ground=rules.ground and rules.ground(s,id)
    if not ground then return nil,"OCCUPANCY_UNKNOWN" end
    local deck,has_bridge
    if rules.deck then deck,has_bridge=rules.deck(s,id) end
    if has_bridge and not deck then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
    local record={id=id,kind=kind,slope=slope,base=base,top=top,bridge_deck=deck,
      occupied=ground[id]==true,owner=t.owner,roadtype=t.roadtype or 0,
      dir=t.depot_dir and 4-t.depot_dir}
    if kind=="road" then
      record.road={roadtype=t.roadtype or 0,bits=Sim.road_bits(s,id),
        owner=t.road_town and "town" or t.owner,disallowed=t.road_disallowed or t.disallowed}
    elseif kind=="station" then
      local st=s.stations[t.station]
      if not st or st.owner~=owner or t.road_stop_pair then return nil,"PROTECTED_TERMINAL_TILE" end
      record.station,record.stop_type=st.id,st.stop_type or "bus"
      record.through=t.stop_axis~=nil
      record.axis=t.stop_axis==5 and 1 or t.stop_axis==10 and 0 or nil
      -- Until multi-tile station edit/order placement is mounted, only
      -- report an already-built same bay, never reorient its route.
      if not through and flag[4-dir]~=Sim.road_bits(s,id) then return nil,"PROTECTED_TERMINAL_TILE" end
    end
    if deck and not depot then
      local gfx=through and (4+dir%2) or dir
      local ok=Underlay.quote({kind="station",station_type=selected.kind,layout=gfx,max_z=top},0,deck)
      record.bridge_forbidden=not ok
    end
    local settings={company=owner,requested_type={kind="road",roadtype=0},
      build_on_slopes=s.stock_road_town_policy==nil or s.stock_road_town_policy.build_on_slopes~=false,
      piece_price=function() return 95 end,
      clear=function()
        if record.occupied then return nil,"VEHICLE_IN_THE_WAY" end
        return quote_clear(t),"PROTECTED_TERMINAL_TILE"
      end}
    local pen=s.stock_road_town_policy
    if pen then settings.on_town_road=pen.stop_on_town_road end
    local leg,why
    if depot then leg,why=Stop.depot(record,{dir=dir,roadtype=0},settings)
    else leg,why=Stop.tile(record,{dir=dir,through=through,stop_type=selected.kind},settings) end
    if not leg then return nil,why end
    if leg.unchanged or leg.station then return nil,"ALREADY_BUILT" end
    if leg.cost>c.cash then return nil,"NOT_ENOUGH_CASH" end
    local native_dir=4-dir
    local edits,price={},leg.cost
    local edit={id=id,tool=depot and "road_depot" or "road_station",depot_dir=depot and native_dir or nil,
      road_bits=through and axis_bits[dir%2] or flag[native_dir],road_town=t.road_town,
      stop_axis=through and axis_bits[dir%2] or nil,road_terminal_level=leg.z,rotate_depot=leg.rotate,
      stop_type=not depot and selected.kind or nil}
    edit.build=edit.tool
    if rules.facility then
      local ok,details=rules.facility(s,owner,edit,selected)
      if not ok then return nil,details end
    end
    -- Stock callback: only add a missing half to existing, normal road.
    -- A blocked neighbor doesn't invalidate the main build quote.
    if rules.connect then
      for _,d in ipairs(through and {native_dir,(native_dir+1)%4+1} or {native_dir}) do
        local neighbor=Sim.adjacent(id,d)
        local n=neighbor and s.tiles[neighbor]
        if n and n.build=="road" and not n.level_crossing and not n.roadworks and Sim.road_bits(s,neighbor)~=0 then
          local addition,cost=rules.connect(s,owner,neighbor,d,edit)
          if addition and cost>0 and price+cost<=c.cash then
            edits[#edits+1]=addition;price=price+cost
          end
        end
      end
    end
    edits[#edits+1]=edit
    return {cost=price,changes=edits}
  end
  return W
end
