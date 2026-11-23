-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Pinned OpenTTD 14.1: station.cpp GetTileCatchmentRadius /
-- RecomputeCatchment; station_cmd.cpp UpdateStationAcceptance /
-- CanMoveGoodsToStation / MoveGoodsToStation / BuildStationPart.
return function(Packets,Rating,passenger_acceptance,mail_acceptance)
  local C={default_spread=12,unmodified_radius=4}
  -- Airport "airport" is the stock Small/Country airfield only.
  local radii={bus=3,truck=3,rail=4,dock=5,airport=4,airport_city=5,buoy=0,waypoint=0}
  local houses={passenger=passenger_acceptance,mail=mail_acceptance}
  local min,max=math.min,math.max
  local function in_map(w,h,x,y) return x>=0 and y>=0 and x<w and y<h end

  function C.radius(kind,modified)
    local r=assert(radii[kind],"Unsupported stock station tile kind")
    return r>0 and modified==false and C.unmodified_radius or r
  end

  -- Physical zero-based map tiles. A dock contributes both its slope and
  -- stationary water tile, never the adjacent vehicle berth. Optional
  -- tile.station filters foreign tiles when scanning a map rectangle.
  -- The expanded bounding rectangle is storage, not catchment coverage.
  function C.build(st,width,height,modified)
    local c={id=st.id,width=width,height=height,tiles={},facilities={},radius=0}
    local rect
    for _,tile in ipairs(st.tiles or {}) do
      if tile.station==nil or tile.station==st.id then
        local x,y=tile.x,tile.y
        assert(in_map(width,height,x,y),"Station tile outside map")
        local r=C.radius(tile.kind,modified)
        if r>0 then
          c.radius=max(c.radius,r)
          c.facilities[tile.kind=="airport_city" and "airport" or tile.kind]=true
          if not rect then
            rect={left=x,right=x,top=y,bottom=y}
          else
            rect.left,rect.right=min(rect.left,x),max(rect.right,x)
            rect.top,rect.bottom=min(rect.top,y),max(rect.bottom,y)
          end
          for v=max(0,y-r),min(height-1,y+r) do
            for u=max(0,x-r),min(width-1,x+r) do c.tiles[v*width+u]=true end
          end
        end
      end
    end
    if rect then
      local r=c.radius
      c.station_rect=rect
      c.bounds={left=max(0,rect.left-r),right=min(width-1,rect.right+r),
        top=max(0,rect.top-r),bottom=min(height-1,rect.bottom+r)}
    end
    return c
  end

  function C.contains(c,x,y)
    return in_map(c.width,c.height,x,y) and c.tiles[y*c.width+x]==true
  end

  -- Geometry/ownership check after a host resolves which station to join.
  -- Normal constructors precheck their own footprint size. Spread is the
  -- physical union, not catchment; coordinates in rect are inclusive.
  function C.can_extend(st,c,rect,company,spread)
    if st and st.owner~=company then return false,"ownership" end
    spread=spread or C.default_spread
    local left,right,top,bottom=rect.left,rect.right,rect.top,rect.bottom
    assert(right>=left and bottom>=top,"Empty facility footprint")
    local old=c and c.station_rect
    if old then
      left,right=min(left,old.left),max(right,old.right)
      top,bottom=min(top,old.top),max(bottom,old.bottom)
    end
    if right-left+1>spread or bottom-top+1>spread then return false,"spread" end
    return true
  end

  local function facility_admits(c,cargo)
    local f=c.facilities
    return f.rail or f.dock or f.airport or (cargo=="passenger" and f.bus) or (cargo=="mail" and f.truck) or false
  end

  -- Each covered house tile contributes eighths exactly once, even when
  -- unfinished. house_at returns a HouseID record or nil. Town totals are
  -- metadata, not a filter on the station-level acceptance/always flags.
  function C.acceptance(c,cargo,house_at)
    local accepts=assert(houses[cargo],"Unsupported house cargo")
    local raw,towns,always=0,{},false
    for id in pairs(c.tiles) do
      local house=house_at(id%c.width,math.floor(id/c.width))
      if house then
        local amount=assert(accepts(house.id),"Unknown stock HouseID")
        if amount>0 then
          raw=raw+amount;always=true
          if house.town~=nil then towns[house.town]=(towns[house.town] or 0)+amount end
        end
      end
    end
    local amount=facility_admits(c,cargo) and raw or 0
    return {eighths=amount,raw_eighths=raw,always_accepted=always,
      accepts=amount>=8,demand=math.floor(amount/8),towns=towns}
  end

  -- StationFinder checks the emitting house tile, not only its town.
  -- Delivery acceptance is NOT a production eligibility condition.
  -- town_rights(st.town) returns {exclusive_counter,exclusivity} for
  -- the station's associated town, not the emitting house's town.
  function C.offer(st,c,cargo,x,y,get_goods,opts)
    assert(houses[cargo],"Unsupported house cargo")
    if not C.contains(c,x,y) or not facility_admits(c,cargo) then return end
    opts=opts or {}
    if opts.exclusive_owner~=nil and opts.exclusive_owner~=st.owner then return end
    if opts.town_rights and st.owner~=opts.neutral_owner then
      local rights=opts.town_rights(opts.station_town and opts.station_town(st) or st.town)
      if rights and rights.exclusive_counter>0 and rights.exclusivity~=st.owner then return end
    end
    local g=get_goods(st,cargo)
    if g and g.rating>0 and
        (opts.select_goods==false or Rating.has_tried_loading(g)) then return g.rating end
  end

  -- Cargo gear uses the front vehicle max-speed cache from economy.cpp,
  -- not its displayed speed: ships are not halved, while aircraft use
  -- Aircraft::GetSpeedOldUnits (cached * 10 / 128). Call only where
  -- the vehicle enters the loading branch (not unloading, NO_LOAD or
  -- STOP_LOADING), even when the vehicle has no available capacity.
  function C.observe_loading(g,mode,cached_max_speed,calendar_year,build_year,capacity_left)
    assert(mode=="road" or mode=="rail" or mode=="ship" or mode=="air","Unsupported vehicle mode")
    local speed=mode=="road" and math.floor(cached_max_speed/2) or
      mode=="air" and math.floor(cached_max_speed*10/128) or cached_max_speed
    Rating.observe_loading(g,speed,calendar_year-build_year,capacity_left)
  end

  -- This is deliberately not offer's ownership check. At a neutral
  -- station only, another company's exclusive rights block pickup.
  function C.may_load(st,vehicle_owner,rights,neutral_owner)
    return st.owner~=neutral_owner or not rights or rights.exclusive_counter==0 or
      rights.exclusivity==vehicle_owner
  end

  function C.loaded(st,mode,units)
    if units>0 then
      st.time_since_load=0
      st.last_vehicle_type=mode
    end
  end

  -- The last transport to actually load at this station influences the
  -- rating of all cargoes, not just the cargo that it picked up. Preserve
  -- host options and leave truncation, timers and RNG ownership to it.
  function C.rating_step(st,g,opts)
    local tick={}
    for key,value in pairs(opts) do tick[key]=value end
    tick.ship=st.last_vehicle_type=="ship"
    return Rating.step(g,tick)
  end

  -- Reuse the road fixed-point distribution including company weights and
  -- StationID ties. Pass the indexed nearby list if available; invalidate
  -- cached coverage when the station's facilities change. A shared station
  -- is a single candidate, rating and queue, not one of each per facility.
  function C.allocate(amount,stations,coverage_by_id,cargo,x,y,get_goods,opts)
    local result={}
    if amount<=0 then return result end
    local seen={}
    for _,st in ipairs(stations) do
      local c=coverage_by_id[st.id]
      if c and not seen[st.id] then
        seen[st.id]=true
        local rating=C.offer(st,c,cargo,x,y,get_goods,opts)
        if rating then result[#result+1]={st=st,rating=rating} end
      end
    end
    table.sort(result,function(a,b) return a.st.id<b.st.id end)
    Packets.allocate(amount,result)
    return result
  end

  return C
end
