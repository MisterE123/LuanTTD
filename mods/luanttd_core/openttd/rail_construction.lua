-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 rail_cmd.cpp ordinary CmdBuildSingleRail, CmdBuildTrainDepot,
-- CmdBuildSingleSignal, and station_cmd.cpp CalculateRailStationCost,
-- CheckBuildableTile/CheckFlatLandRailStation, depot_func.h, table/pricebase.h.
-- Stock gauges in CmdBuildSingleRail verified against 16.0-RC1. No
-- roads/crossing construction, game-world spending,
-- custom railtypes, NewGRF station specs, or mutation/signal recomputation.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local RailTypes=dofile(mod.."/openttd/rail_types.lua")
return function(Track,Signal,Height)
  local Q={}
  local floor,max=math.floor,math.max
  local base={
    rail=100,signal=65,depot=600,station=200,station_length=180,foundation=250,
    clear_rail=-70,clear_signal=10,clear_grass=20,clear_rough=40,clear_rocks=200,
    clear_fields=500,clear_water=10000,
  }
  local rail_multipliers={[0]=8,12,16,24}
  local land_keys={grass="clear_grass",rough="clear_rough",snow="clear_rough",desert="clear_rough",
    rocks="clear_rocks",fields="clear_fields"}
  local straight_edges={[0]=12,6,3,9}
  local one_corner={[1]=true,[2]=true,[4]=true,[8]=true}
  local slopes={[0]=true,[23]=true,[27]=true,[29]=true,[30]=true}
  for i=1,14 do slopes[i]=true end
  local function valid_track(t) return type(t)=="number" and t>=0 and t<=5 and t%1==0 end
  local function uint(n,max_num) return type(n)=="number" and n%1==0 and n>=0 and n<=max_num end
  local function cost(o,key) return o.prices and o.prices[key] or base[key] end
  local function plain(t) return t.kind=="rail" or t.kind=="signals" end
  local function shore(t) return t.kind=="water" and t.coast==true end
  local function occupied(t) return t.occupied or (t.train_bits or 0)~=0 end
  local function check_owner(t,o) return t.owner==o.owner end

  function Q.base_prices()
    local out={}
    for k,v in pairs(base) do out[k]=v end
    return out
  end

  -- RecomputePrices for this vanilla construction-price table (no GRF
  -- multiplier). Optional authoritative snapshot: opts.prices overrides it.
  function Q.prices(difficulty,inflation)
    difficulty,inflation=difficulty or 1,inflation or 65536
    local factor=({[0]=6,8,9})[difficulty]
    if not factor or not uint(inflation,2^32-1) then return nil,"INVALID_PARAMETER" end
    local out={}
    for k,v in pairs(base) do
      local p=floor(v*factor*inflation/2^19)
      out[k]=p==0 and (v>0 and 1 or -1) or p
    end
    return out
  end

  function Q.rail_price(railtype,o)
    local m=rail_multipliers[railtype]
    if m then return floor(cost(o or {},"rail")*m/8) end
  end
  function Q.rail_clear_price(railtype,o)
    local p=Q.rail_price(railtype,o)
    -- C++ signed division truncates toward zero.
    if p then return max(cost(o or {},"clear_rail"),-floor(p*3/4)) end
  end

  function Q.occupied_track(bits,track)
    local piece=2^track
    if Track.has(bits,track) then return true end
    for other=0,5 do
      if Track.has(bits,other) and Track.tracks_overlap(piece+2^other) then return true end
    end
    return false
  end

  -- DC_AUTO | DC_NO_WATER. Surface-specific commands outside this slice
  -- may be delegated to existing source-backed planners: clear_quote(t,true).
  local function clearing(tile,o,shape)
    if tile.kind=="clear" or tile.kind=="ground" then
      local ground=tile.ground or "grass"
      local key=land_keys[ground]
      if not key then return nil,"LANDSCAPE_CLEAR_REQUIRED" end
      if ground=="grass" and tile.density==0 then return 0 end
      return cost(o,key)
    end
    if tile.kind=="water" then
      if not shore(tile) then return nil,"CANT_BUILD_ON_WATER" end
      if occupied(tile) then return nil,"VEHICLE_IN_THE_WAY" end
      return cost(o,one_corner[shape] and "clear_water" or "clear_rough")
    end
    if plain(tile) or tile.kind=="depot" then
      if not check_owner(tile,o) then return nil,"OWNED_BY_ANOTHER" end
      return nil,plain(tile) and "MUST_REMOVE_RAILROAD_TRACK" or "BUILDING_MUST_BE_DEMOLISHED"
    end
    if tile.kind=="station" or tile.kind=="waypoint" then return nil,"BUILDING_MUST_BE_DEMOLISHED" end
    if o.clear_quote then return o.clear_quote(tile,true) end
    return nil,"LANDSCAPE_CLEAR_REQUIRED"
  end

  local function normal(o) return (o.railtype==nil or o.railtype==0) and o.available~=false end
  -- Local bits only. Signal removal can also invalidate a train whose
  -- reservation ends just past a PBS signal; execution owns that lookup.
  local function reservation_flags(tile,bits,signal_tracks)
    local out=Track.intersect(tile.reserved_bits or 0,bits)
    for _,track in ipairs(signal_tracks or {}) do
      out=Track.union(out,Track.intersect(tile.reserved_bits or 0,2^track))
    end
    return out
  end

  function Q.piece(tile,track,o)
    o=o or {}
    local request=o.railtype or RailTypes.RAIL
    if not tile or not valid_track(track) or o.available==false or not RailTypes.entry(request) then
      return nil,"INVALID_PARAMETER"
    end
    local shape=tile.slope or 0
    if not slopes[shape] then return nil,"INVALID_PARAMETER" end
    local existing,prior_type=0
    if plain(tile) or tile.kind=="depot" then
      if not check_owner(tile,o) then return nil,"OWNED_BY_ANOTHER" end
      if not plain(tile) then return nil,"BUILDING_MUST_BE_DEMOLISHED" end
      prior_type=tile.railtype or RailTypes.RAIL
      if not RailTypes.is_compatible(prior_type,request) then return nil,"IMPOSSIBLE_TRACK_COMBINATION" end
      existing=tile.trackbits or 0
      if Track.has(existing,track) then return nil,"ALREADY_BUILT" end
      if (tile.occupied and tile.train_bits==nil) or Q.occupied_track(tile.train_bits or 0,track) then
        return nil,"VEHICLE_IN_THE_WAY"
      end
    elseif tile.kind=="road" or tile.kind=="crossing" then return nil,"UNSUPPORTED_LEVEL_CROSSING" end
    local newbit=2^track
    local ok,foundation,corner,changed=Track.build_slope(shape,newbit,existing,
      tile.flooding or shore(tile),o.build_on_slopes~=false)
    if not ok then
      return nil,foundation=="water" and "CANT_BUILD_ON_WATER" or "LAND_SLOPED_IN_WRONG_DIRECTION"
    end
    local combined=Track.union(existing,newbit)
    local removed_signals={}
    if tile.kind=="signals" and Track.tracks_overlap(combined) then
      if not o.auto_remove_signals then return nil,"MUST_REMOVE_SIGNALS_FIRST" end
      for k=0,5 do
        if Track.has(existing,k) and Signal.on_track(tile,k) then removed_signals[#removed_signals+1]=k end
      end
    end
    local clear=0
    local water_ground=shore(tile) and one_corner[shape] or false
    if existing==0 then
      local failure
      clear,failure=clearing(tile,o,shape)
      if clear==nil then return nil,failure end
      if water_ground then clear=clear-cost(o,"clear_water")+cost(o,"clear_rough") end
    end
    local result_type,convert=request,false
    local conversion_cost=0
    if prior_type then
      result_type,convert=RailTypes.add_piece_type(prior_type,request)
      if result_type==nil then return nil,convert end
      if convert then
        -- CmdConvertRail prices the count of existing tracks (not the
        -- squared count that the infrastructure ledger uses on overlaps).
        local count=0
        for k=0,5 do if Track.has(existing,k) then count=count+1 end end
        conversion_cost=count*RailTypes.convert_cost(prior_type,result_type,o.prices)
      end
    end
    local parts={track=Q.rail_price(request,o),clearing=clear,foundation=changed and cost(o,"foundation") or 0,
      conversion=conversion_cost,signals=#removed_signals*cost(o,"clear_signal")}
    local result_kind=tile.kind=="signals" and #removed_signals==0 and "signals" or "rail"
    local p={kind=result_kind,railtype=result_type,convert_from=convert and prior_type or nil,
      owner=o.owner,trackbits=combined,track=track,
      foundation=foundation,foundation_corner=corner,foundation_changed=changed,
      remove_signals=removed_signals,water_ground=water_ground,
      affected_reservations=reservation_flags(tile,0,removed_signals),parts=parts}
    p.cost=parts.track+parts.clearing+parts.foundation+parts.signals+parts.conversion
    if Height and tile.base_level~=nil then p.profile=Height.profile({
      kind=result_kind,trackbits=combined,slope=shape},tile.base_level) end
    return p
  end

  function Q.can_depot_slope(dir,shape)
    local corners=straight_edges[dir]
    if not corners or not slopes[shape] then return false end
    if shape==0 then return true end
    local raised=Track.intersect(shape%16,corners)
    return shape>=16 and raised==corners or shape<16 and raised~=0
  end

  function Q.depot(tile,dir,o)
    o=o or {}
    if not tile or not straight_edges[dir] or not normal(o) then return nil,"INVALID_PARAMETER" end
    local shape=tile.slope or 0
    if not slopes[shape] then return nil,"INVALID_PARAMETER" end
    if shape~=0 and (o.build_on_slopes==false or not Q.can_depot_slope(dir,shape)) then return nil,"FLAT_LAND_REQUIRED" end
    local rotating=tile.kind=="depot" and (tile.railtype==nil or tile.railtype==0)
    local clear=0
    if rotating then
      if not check_owner(tile,o) then return nil,"OWNED_BY_ANOTHER" end
      if tile.dir==dir then return nil,"ALREADY_BUILT" end
      if occupied(tile) then return nil,"VEHICLE_IN_THE_WAY" end
    else
      local failure
      clear,failure=clearing(tile,o,shape)
      if clear==nil then return nil,failure end
      if tile.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
      if o.depot_pool_full then return nil,"DEPOT_POOL_FULL" end
    end
    local parts={track=Q.rail_price(0,o),clearing=clear,depot=cost(o,"depot"),
      foundation=shape==0 and 0 or cost(o,"foundation")}
    local p={kind="depot",railtype=0,dir=dir,trackbits=2^(dir%2),owner=o.owner,rotate=rotating,
      foundation=shape==0 and "none" or "leveled",
      cost=parts.track+parts.clearing+parts.depot+parts.foundation,parts=parts}
    if Height and tile.base_level~=nil then p.profile=Height.profile({
      kind="depot",dir=dir,slope=shape},tile.base_level) end
    return p
  end

  local upper={[0]=true,[1]=true,[2]=true,[4]=true}
  local signal_errors={parameter="INVALID_PARAMETER",no_track="THERE_IS_NO_RAILROAD_TRACK",
    owner="OWNED_BY_ANOTHER",overlap="NO_SUITABLE_RAILROAD_TRACK",no_signal="THERE_ARE_NO_SIGNALS"}
  function Q.signal(tile,track,args,o)
    o,args=o or {},args or {}
    if not uint(args.kind or Signal.PBS,5) or not uint(args.variant or 0,1) or
        not uint(args.copy_mask or 0,255) or not uint(args.cycle_start or 0,5) or
        not uint(args.cycle_stop or 5,5) or (args.cycle_start or 0)>(args.cycle_stop or 5) then
      return nil,"INVALID_PARAMETER"
    end
    if not valid_track(track) then return nil,"THERE_IS_NO_RAILROAD_TRACK" end
    local ok,why=Signal.eligible(tile,o.owner,track,args)
    if not ok then return nil,signal_errors[why] end
    local variant=args.variant or 0
    if args.ctrl then variant=1-variant end
    local prev=(upper[track] and tile.upper_variant or not upper[track] and tile.lower_variant) or 0
    local amount=0
    if why=="new" then amount=cost(o,"signal")
    elseif why~="skip" and (((args.copy_mask or 0)~=0 and variant~=prev) or
        (args.convert and (args.ctrl or variant~=prev))) then amount=cost(o,"signal")+cost(o,"clear_signal") end
    return {cost=amount,kind="signal",track=track,action=why,variant=variant,
      affected_reservations=why=="skip" and 0 or reservation_flags(tile,2^track)}
  end

  -- Row-major stock OrthogonalTileArea order, not platform order. In the
  -- source the length-ready counter resets when tracknum == numtracks
  -- BEFORE this tile; it does not reset every numtracks submitted tiles.
  -- Preserve that exact loop including unchanged station cells.
  function Q.station(tiles,axis,numtracks,length,o)
    o=o or {}
    if o.authority_denied then return nil,"AUTHORITY_REFUSES" end
    local gauge=o.railtype or RailTypes.RAIL
    if o.available==false or not RailTypes.entry(gauge) or (axis~=Track.X and axis~=Track.Y) or not uint(numtracks,255) or
        not uint(length,255) or numtracks==0 or length==0 or type(tiles)~="table" or
        #tiles~=numtracks*length then return nil,"INVALID_PARAMETER" end
    if o.station_spread and max(length,numtracks)>o.station_spread then return nil,"STATION_SPREAD" end
    local tracknum,length_ready=0,true
    local allowed,station=nil,nil
    local out={cost=0,kind="station",railtype=gauge,axis=axis,owner=o.owner,numtracks=numtracks,length=length,tiles={},
      parts={foundation=0,clearing=0,track=0,station=0,length=0}}
    for i,tile in ipairs(tiles) do
      if tile.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST",i end
      if occupied(tile) then return nil,"VEHICLE_IN_THE_WAY",i end
      local shape=tile.slope or 0
      if not slopes[shape] or type(tile.base_level)~="number" or tile.base_level%1~=0 then
        return nil,"INVALID_PARAMETER",i
      end
      if shape>=16 or shape~=0 and o.build_on_slopes==false then return nil,"FLAT_LAND_REQUIRED",i end
      local foundation,clear=0,0
      if shape~=0 then
        if not Q.can_depot_slope(axis,shape) or not Q.can_depot_slope(axis+2,shape) then return nil,"FLAT_LAND_REQUIRED",i end
        foundation=cost(o,"foundation")
      end
      local level=tile.base_level+(shape==0 and 0 or 1)
      if allowed==nil then allowed=level
      elseif allowed~=level then return nil,"FLAT_LAND_REQUIRED",i end
      local affected=0
      if tile.kind=="station" then
        if station==nil then station=tile.station
        elseif station~=tile.station then return nil,"ADJOINS_MORE_THAN_ONE_EXISTING",i end
        affected=tile.reserved_bits or 0
      elseif tile.kind=="signals" then return nil,"MUST_REMOVE_SIGNALS_FIRST",i
      elseif tile.kind=="rail" and RailTypes.has_power(tile.railtype or 0,gauge) and tile.trackbits==2^axis then
        if not check_owner(tile,o) then return nil,"OWNED_BY_ANOTHER",i end
        clear=Q.rail_clear_price(tile.railtype or 0,o)
        affected=reservation_flags(tile,2^axis)
      else
        local failure
        clear,failure=clearing(tile,o,shape)
        if clear==nil then return nil,failure,i end
      end
      if tracknum==numtracks then length_ready=true;tracknum=0
      else tracknum=tracknum+1 end
      local changed=tile.kind~="station" or tile.axis~=axis
      local price=0
      if changed then
        local charges=out.parts
        charges.foundation=charges.foundation+foundation
        charges.clearing=charges.clearing+clear
        local track=Q.rail_price(gauge,o)
        local plat=cost(o,"station")
        charges.station=charges.station+plat
        charges.track=charges.track+track
        price=foundation+clear+track+plat
        if length_ready then
          local increment=cost(o,"station_length")
          charges.length=charges.length+increment
          length_ready=false
          price=price+increment
        end
      end
      local placement={id=tile.id,owner=tile.owner,cost=price,changed=changed,
        affected_reservations=affected,level=level,foundation=shape==0 and "none" or "leveled"}
      if Height then placement.profile=Height.profile({kind="station",axis=axis,slope=shape},tile.base_level) end
      out.tiles[i]=placement
      out.cost=out.cost+price
    end
    for i,tile in ipairs(tiles) do
      if tile.kind=="station" and not check_owner(tile,o) then return nil,"OWNED_BY_ANOTHER",i end
    end
    out.level=allowed
    out.existing_station=station
    return out
  end
  return Q
end
