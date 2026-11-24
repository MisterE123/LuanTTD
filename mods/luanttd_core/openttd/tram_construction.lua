-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Port from source pin 14.1: tram branches of
-- CmdBuildRoad/CmdBuildRoadDepot in road_cmd.cpp, CheckBuildableTile and
-- CheckFlatLandRoadStop/CmdBuildRoadStop in station_cmd.cpp, depot_func.h,
-- road_map.cpp GetAnyRoadBits, road.h and table/roadtypes.h.
-- Pure planning: prechecked map validity, town/company allocation, calendar
-- availability, budget, station spread/authority and mutation belong outside.
return function(Road,types)
  local T={}
  local floor=math.floor
  local dirs={[0]=8,4,2,1}
  local axes={[0]=10,5}
  local reverse_mask={[0]=12,6,3,9}
  local crossing_slope={[0]=true,[5]=true,[10]=true,[7]=true,[11]=true,[13]=true,[14]=true}
  local function has(mask,bit) return floor(mask/bit)%2==1 end
  local function mask(a,b,op)
    local c=0
    for i=0,3 do local d=2^i;if op(has(a,d),has(b,d)) then c=c+d end end
    return c
  end
  local function band(a,b) return mask(a,b,function(x,y) return x and y end) end
  local function bor(a,b) return mask(a,b,function(x,y) return x or y end) end
  local function remove(a,b) return a-band(a,b) end
  local function one(m) return m==1 or m==2 or m==4 or m==8 end
  local function nbits(m)
    local n=0;for i=0,3 do if has(m,2^i) then n=n+1 end end
    return n
  end
  local function by_price(o,k,default) return o.prices and o.prices[k] or default end
  local function has_power(a,b) return types[a] and types[a].powered[b] or false end
  local function build_cost(o,rt) return floor(by_price(o,"road",95)*types[rt].cost_multiplier/8) end
  local function tram_type(rt) return types[rt] and types[rt].type=="tram" end
  local function tram_buildable_type(rt,o)
    return tram_type(rt) and (not o.available or o.available(rt))
  end
  local function clear(t,o,no_water)
    if t.kind=="clear" then return 0 end
    if t.kind=="water" and no_water then return nil,"WATER" end
    if not o.clear_quote then return nil,"LANDSCAPE_CLEAR_REQUIRED" end
    return o.clear_quote(t,no_water)
  end
  local function company(owner) return owner~=nil and owner~="town" and owner~="none" end
  local function owned(t,o)
    return not company(t) or t==o.owner
  end

  -- Exact GetAnyRoadBits by subtype. A ground tile below a span remains
  -- its own tile kind. Depot dir points out; bridge/tunnel dir points in.
  function T.effective_bits(t,portal_straight)
    if not t or t.tramtype==nil then return 0 end
    if t.kind=="road" then return t.tram_bits or 0 end
    if t.kind=="crossing" then return axes[t.axis] end
    if t.kind=="depot" or t.kind=="bay_stop" then return dirs[t.dir] end
    if t.kind=="drive_stop" then return axes[t.dir%2] end
    if (t.kind=="bridge" or t.kind=="tunnel") and t.transport=="road" then
      return portal_straight and axes[t.dir%2] or dirs[(t.dir+2)%4]
    end
    return 0
  end

  function T.can_depot_slope(d,s)
    local entrance=reverse_mask[d]
    if not entrance then return false end
    if s==0 then return true end
    local raised=band(s%16,entrance)
    return s>=16 and raised==entrance or s<16 and raised~=0
  end

  -- Depot is a dedicated road type, never a road/tram combination. Source
  -- permits a same-type rotation without clearing, including bridge above
  -- that already exists (new depot construction under a bridge is denied).
  function T.depot(tile,dir,rt,o)
    o=o or {}
    if not tram_buildable_type(rt,o) or not dirs[dir] then return nil,"INVALID_PARAMETER" end
    local s=tile.slope or 0
    if s~=0 and (o.build_on_slopes==false or not T.can_depot_slope(dir,s)) then
      return nil,"FLAT_LAND_REQUIRED"
    end
    local same=tile.kind=="depot" and tile.tramtype==rt
    if same then
      if tile.owner~=o.owner then return nil,"OWNED_BY_ANOTHER" end
      if tile.dir==dir then return nil,"ALREADY_BUILT" end
      if tile.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    end
    local clearing=0
    if not same then
      local failure
      clearing,failure=clear(tile,o,false)
      if clearing==nil then return nil,failure end
      if tile.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
    end
    local plan={kind="depot",dir=dir,tramtype=rt,tram_bits=dirs[dir],
      tram_owner=o.owner,owner=o.owner,rotate=same,clearing=clearing,
      base=(tile.base or 0)+(s==0 and 0 or s>=16 and 2 or 1),
      foundation=s~=0 and "leveled" or "none"}
    plan.cost=clearing+by_price(o,"depot",500)+(s~=0 and by_price(o,"foundation",250) or 0)
    return plan
  end

  -- Lay electrified tram bits independently of an existing road. Street,
  -- crossing and overlay paths preserve the non-tram bits and ownership.
  -- For a stock branch which would clear a tile, caller must explicitly
  -- supply clear_quote. This API never actually removes a site object.
  function T.lay(t,requested,rt,o)
    o=o or {}
    if not tram_buildable_type(rt,o) or requested<1 or requested>15 or requested%1~=0 then
      return nil,"INVALID_PARAMETER"
    end
    if o.town_generation and not has(types[rt].flags,16) then return nil,"ROADTYPE_NOT_FOR_TOWN" end
    local existing,other,pieces=0,0,requested
    local slope=t.slope or 0
    local present=T.effective_bits(t,false)
    local must_clear=false
    local made_kind=t.kind
    local crossing_axis
    if t.kind=="road" then
      if t.roadworks then return nil,"ROAD_WORKS_IN_PROGRESS" end
      other,existing=t.road_bits or 0,present
      if remove(pieces,existing)==0 then return nil,"ALREADY_BUILT" end
      if one(existing) and not owned(t.tram_owner,o) then return nil,"OWNED_BY_ANOTHER" end
    elseif t.kind=="crossing" then
      if has(types[rt].flags,2) then return nil,"CROSSING_DISALLOWED_ROAD" end
      other=axes[t.axis]
      if remove(pieces,other)~=0 then must_clear=true
      else
        pieces=other
        if t.tramtype~=nil then return nil,"ALREADY_BUILT" end
      end
    elseif t.kind=="rail" then
      if not crossing_slope[slope] then return nil,"WRONG_SLOPE" end
      if o.crossing_with_competitor==false and o.owner~="town" and o.owner~="deity" and
          not owned(t.owner,o) then return nil,"OWNED_BY_ANOTHER" end
      if t.rail_normal==false then must_clear=true
      else
        if has(types[rt].flags,2) then return nil,"CROSSING_DISALLOWED_ROAD" end
        if t.rail_no_crossing then return nil,"CROSSING_DISALLOWED_RAIL" end
        if t.rail_axis==nil or band(pieces,axes[t.rail_axis])~=0 then must_clear=true
        else
          if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
          crossing_axis=1-t.rail_axis
          pieces=axes[crossing_axis]
          return {kind="crossing",axis=crossing_axis,tramtype=rt,tram_bits=pieces,
            tram_owner=o.owner,rail_owner=t.owner,existing=0,added=pieces,cost=2*build_cost(o,rt)}
        end
      end
    elseif t.kind=="depot" or t.kind=="bay_stop" then
      if remove(pieces,present)==0 then return nil,"ALREADY_BUILT" end
      must_clear=true
    elseif t.kind=="drive_stop" then
      if remove(pieces,present)==0 then return nil,"ALREADY_BUILT" end
      local straight=axes[t.dir%2]
      if remove(pieces,straight)~=0 then must_clear=true
      else
        pieces=straight
        if t.tramtype~=nil then return nil,"ALREADY_BUILT" end
      end
    elseif t.kind=="bridge" or t.kind=="tunnel" then
      if t.transport~="road" or pieces~=dirs[(t.dir+2)%4] then must_clear=true
      else
        if t.tramtype~=nil then return nil,"ALREADY_BUILT" end
        if t.occupied or t.span_occupied then return nil,"VEHICLE_IN_THE_WAY" end
      end
    else
      must_clear=true
    end
    local clearing=0
    if must_clear then
      local why
      clearing,why=clear(t,o,o.no_water)
      if clearing==nil then return nil,why end
      made_kind="road"
    end
    local found=false
    if other~=pieces then
      local adjusted,need=Road.prepare(slope,pieces,existing,other,o.build_on_slopes~=false)
      if not adjusted then return nil,"WRONG_SLOPE" end
      if need and o.build_on_slopes==false then return nil,"WRONG_SLOPE" end
      pieces,found=adjusted,need
    end
    if not must_clear then
      if t.kind=="road" or t.kind=="crossing" then pieces=remove(pieces,existing) end
      if t.kind=="road" and other~=0 and
          Road.foundation(slope,bor(existing,pieces))~=Road.foundation(slope,other) then
        return nil,"WRONG_SLOPE"
      end
      if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    end
    local cost=t.kind=="bridge" or t.kind=="tunnel"
    local length=(cost and not must_clear) and 2*((t.skip or 0)+2) or nbits(pieces)
    local rt_owner=o.owner
    if existing~=0 then rt_owner=t.tram_owner end
    if t.kind=="road" and t.tramtype~=nil and t.tramtype~=rt then
      -- A powered vehicle may use the old tram type without converting it.
      -- The reverse power case needs a separate NewGRF conversion command.
      if has_power(rt,t.tramtype) then rt=t.tramtype
      else return nil,has_power(t.tramtype,rt) and "CONVERSION_REQUIRED" or "INCOMPATIBLE_ROADTYPE" end
    end
    local result={kind=made_kind,existing=existing,added=pieces,
      roadtype=not must_clear and t.roadtype or nil,road_bits=not must_clear and t.road_bits or nil,
      road_owner=not must_clear and t.road_owner or nil,tramtype=rt,
      tram_bits=bor(pieces,existing),tram_owner=rt_owner,clearing=clearing,changed_clear=must_clear,
      foundation=Road.foundation(slope,bor(pieces,existing)),foundation_fee=found}
    result.cost=clearing+length*build_cost(o,rt)+(found and by_price(o,"foundation",250) or 0)
    return result
  end

  -- New/continued drive-through tram station; actual station mutation is
  -- external. Existing road and tram can coexist only on the selected
  -- axis. Each class keeps its owner; expansion purchases missing halves.
  function T.stop(t,axis,rt,o)
    o=o or {}
    if o.drive_through==false then return nil,"TRAM_DRIVE_THROUGH_ONLY" end
    if not tram_buildable_type(rt,o) or not axes[axis] then return nil,"INVALID_PARAMETER" end
    if t.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
    if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    local s=t.slope or 0
    local z=(t.base or 0)+(s==0 and 0 or s>=16 and 2 or 1)
    if s>=16 or (s~=0 and (o.build_on_slopes==false or not T.can_depot_slope(axis,s) or
                    not T.can_depot_slope(axis+2,s))) or (o.allowed_z and o.allowed_z~=z) then
      return nil,"FLAT_LAND_REQUIRED"
    end
    if t.kind=="drive_stop" and o.join_existing then
      if t.dir%2~=axis then return nil,"DRIVE_THROUGH_DIRECTION" end
      if o.stop_type and t.stop_type~=o.stop_type then return nil,"WRONG_STATION_FACILITY" end
      if o.station and t.station~=o.station then return nil,"ADJOINS_MORE_THAN_ONE_EXISTING" end
      return {kind=t.kind,unchanged=true,axis=axis,base=z,cost=0,station=t.station}
    end
    local clearing,tracks=0,0
    local road,tram,road_owner,tram_owner=nil,nil,nil,o.owner
    local straight=axes[axis]
    if t.kind=="road" then
      local rbits,tbits=t.road_bits or 0,t.tram_bits or 0
      local union=bor(rbits,tbits)
      if remove(union,straight)~=0 then
        local n=nbits(union)
        if n>2 then return nil,"DRIVE_THROUGH_JUNCTION" end
        if n==2 and not (union==5 or union==10) then return nil,"DRIVE_THROUGH_CORNER" end
        return nil,"DRIVE_THROUGH_DIRECTION"
      end
      road,tram,road_owner,tram_owner=t.roadtype,t.tramtype,t.road_owner,t.tram_owner
      if road~=nil then
        if road_owner=="town" and o.on_town_road==false then return nil,"DRIVE_THROUGH_ON_TOWN_ROAD" end
        if ((road_owner~="town" and o.on_competitor_road==false) or
            (road_owner~="town" and (t.disallowed or 0)~=0)) and
            not owned(road_owner,o) then return nil,"OWNED_BY_ANOTHER" end
        tracks=build_cost(o,road)*(2-nbits(rbits))
      end
      if tram==nil then tram_owner=o.owner end
      if tram~=nil then
        if (o.on_competitor_road==false or one(tbits)) and
            not owned(tram_owner,o) then return nil,"OWNED_BY_ANOTHER" end
        if not has_power(rt,tram) then return nil,"INCOMPATIBLE_ROADTYPE" end
        tracks=tracks+build_cost(o,tram)*(2-nbits(tbits))
      else
        tracks=tracks+2*build_cost(o,rt)
      end
    else
      local why
      clearing,why=clear(t,o,false)
      if clearing==nil then return nil,why end
      tracks=2*build_cost(o,rt)
    end
    return {kind="drive_stop",axis=axis,dir=axis,owner=o.owner,roadtype=road,road_owner=road_owner,
      tramtype=tram or rt,tram_owner=tram_owner,tram_bits=straight,
      road_bits=road~=nil and straight or nil,base=z,clearing=clearing,tracks=tracks,
      cost=clearing+tracks+by_price(o,"stop",200)+(s~=0 and by_price(o,"foundation",250) or 0)}
  end
  return T
end
