-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 contributors: rail_cmd.cpp CmdBuildSingleRail, road_cmd.cpp
-- CmdBuildRoad/GetTileTrackStatus_Road, train_cmd.cpp level-crossing
-- checks, pbs.cpp, road_map.h and roadveh_cmd.cpp EnumCheckRoadVehCrashTrain.
-- Ordinary same-tile road/tram + one straight rail; no live mutations
-- outside the supplied crossing board/reservation callbacks.
return function(T)
  local C={rail_infrastructure_factor=2,default_crossing_with_competitor=true}
  local floor,abs=math.floor,math.abs
  local road_bits={[0]=10,5}
  local valid_slope={[0]=true,[5]=true,[7]=true,[10]=true,[11]=true,[13]=true,[14]=true}
  local rail_mul={[0]=8,12,16,24}
  local road_mul={[0]=8,16}
  local function axis(a) return a==0 or a==1 end
  local function crossing(t) return t and t.kind=="crossing" end
  local function town(o) return o=="town" end
  local function company(o,opts)
    if opts.is_company then return opts.is_company(o) end
    return o~=nil and o~="town" and o~="none" and o~="deity"
  end
  local function tile_at(b,id) if id~=nil then return b.tile(id) end end
  local function count(b)
    local n=0
    while b>0 do n,b=n+b%2,floor(b/2) end
    return n
  end
  local function is_type(n) return type(n)=="number" and n>=0 and n%1==0 end
  local function unavailable(o,kind,type_)
    local c=o[kind.."_types"] and o[kind.."_types"][type_]
    return c and c.no_crossing
  end
  local function price(o,kind,type_)
    local c=o[kind.."_types"] and o[kind.."_types"][type_]
    local k=c and c.multiplier or (kind=="rail" and rail_mul or road_mul)[type_]
    if not k then return end
    local base=o.prices and o.prices[kind] or (kind=="rail" and 100 or 95)
    return floor(base*k/8)
  end
  local function quote_result(t,r,o,ra,owner,railtype,rt,tt,ro,to,nr,nt,r_added,reserved,cost)
    assert(axis(ra))
    local out={kind="crossing",road_axis=ra,rail_axis=1-ra,railtype=railtype,
      rail_owner=owner,road_owner=ro,tram_owner=to,roadtype=rt,tramtype=tt,
      road_bits=rt~=nil and road_bits[ra] or 0,tram_bits=tt~=nil and road_bits[ra] or 0,
      slope=t.slope or 0,barred=false,reserved=not not reserved,
      town=r.kind=="rail" and t.town or r.town or t.town}
    if r.kind=="rail" then out.town=t.town end
    out.road_pieces_added,out.tram_pieces_added,out.rail_pieces_added=nr,nt,r_added
    out.top=t.top or (t.base and (t.base+(out.slope~=0 and 1 or 0)))
    out.foundation=out.slope==0 and "none" or "flattened"
    out.cost=cost
    if o.cash~=nil and cost>o.cash then return nil,"NOT_ENOUGH_MONEY" end
    return out
  end

  -- Construction commands' crossing-preserving branches only. FALLBACK_CLEAR
  -- denotes where the source would invoke DC_AUTO landscape clearing, not
  -- permission for the host to demolish protected roads/rails/stations.
  -- road_bits use the stock NW/SW/SE/NE=1/2/4/8 bit layout.
  function C.quote(t,r,o)
    o=o or {}
    if not t or not r or r.owner==nil then return nil,"INVALID_PARAMETER" end
    local slope=t.slope or 0
    local rt,tt=t.roadtype,t.tramtype
    if r.kind=="rail" then
      local track,railtype=r.track,r.railtype or 0
      if not is_type(track) or track>5 or not is_type(railtype) or not price(o,"rail",railtype) then
        return nil,"INVALID_PARAMETER"
      end
      if t.kind~="road" and not crossing(t) and t.kind~="road_depot" then return nil,"FALLBACK_CLEAR" end
      if not valid_slope[slope] then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION" end
      local land_owner=crossing(t) and t.rail_owner or t.owner
      if o.crossing_with_competitor==false and r.owner~="deity" and land_owner~=r.owner then
        return nil,"OWNED_BY_ANOTHER"
      end
      if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
      if t.kind=="road" then
        if t.roadworks then return nil,"ROAD_WORKS_IN_PROGRESS" end
        if (t.disallowed or 0)~=0 then return nil,"CROSSING_ON_ONEWAY_ROAD" end
        if unavailable(o,"rail",railtype) then return nil,"CROSSING_DISALLOWED_RAIL" end
        if (rt~=nil and unavailable(o,"road",rt)) or (tt~=nil and unavailable(o,"road",tt)) then
          return nil,"CROSSING_DISALLOWED_ROAD"
        end
        local rb,tb=t.road_bits or 0,t.tram_bits or 0
        if axis(track) and T.intersect(T.union(rb,tb),road_bits[track])==0 then
          local ro,to=t.road_owner,t.tram_owner
          if count(tb)==1 and company(to,o) and to~=r.owner then return nil,"OWNED_BY_ANOTHER" end
          local nr=rb==0 and 0 or 2-count(rb)
          local nt=tb==0 and 0 or 2-count(tb)
          local cost=price(o,"rail",railtype)
          if nr>0 then cost=cost+nr*assert(price(o,"road",rt),"Missing road type price") end
          if nt>0 then cost=cost+nt*assert(price(o,"road",tt),"Missing tram type price") end
          return quote_result(t,r,o,1-track,r.owner,railtype,rt,tt,ro,to,nr,nt,2,false,cost)
        end
      end
      if crossing(t) and t.rail_axis==track then return nil,"ALREADY_BUILT" end
      return nil,"FALLBACK_CLEAR"
    elseif r.kind=="road" or r.kind=="tram" then
      local new_type,pieces=r.roadtype or (r.kind=="road" and 0 or 1),r.pieces
      if not is_type(pieces) or pieces<1 or pieces>15 or not is_type(new_type) or not price(o,"road",new_type)
        or (r.disallowed~=nil and (not is_type(r.disallowed) or r.disallowed>3)) then
        return nil,"INVALID_PARAMETER"
      end
      if crossing(t) then
        if unavailable(o,"road",new_type) then return nil,"CROSSING_DISALLOWED_ROAD" end
        if T.remove(pieces,road_bits[t.road_axis])~=0 then return nil,"FALLBACK_CLEAR" end
        local on_road=r.kind=="road"
        if on_road and rt~=nil or not on_road and tt~=nil then return nil,"ALREADY_BUILT" end
        if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
        local out,why=quote_result(t,r,o,t.road_axis,t.rail_owner,t.railtype,
          on_road and new_type or rt,not on_road and new_type or tt,
          on_road and r.owner or t.road_owner,not on_road and r.owner or t.tram_owner,
          on_road and 2 or 0,on_road and 0 or 2,0,t.reserved,2*price(o,"road",new_type))
        if out then
          out.barred=not not t.barred
          if not on_road then out.town=t.town end
        end
        return out,why
      end
      if t.kind~="rail" and t.kind~="signals" and t.kind~="rail_depot" then return nil,"FALLBACK_CLEAR" end
      if not valid_slope[slope] then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION" end
      if o.crossing_with_competitor==false and not town(r.owner) and r.owner~="deity" and t.owner~=r.owner then
        return nil,"OWNED_BY_ANOTHER"
      end
      if t.kind~="rail" then return nil,"FALLBACK_CLEAR" end
      if unavailable(o,"road",new_type) then return nil,"CROSSING_DISALLOWED_ROAD" end
      local railtype=t.railtype or 0
      if unavailable(o,"rail",railtype) then return nil,"CROSSING_DISALLOWED_RAIL" end
      local track=t.trackbits==1 and 0 or t.trackbits==2 and 1
      if not track or T.intersect(pieces,road_bits[track])~=0 then return nil,"FALLBACK_CLEAR" end
      if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
      local nroad=r.kind=="road" and 2 or 0
      local reserved=T.has(t.reserved_bits or 0,track)
      return quote_result(t,r,o,1-track,t.owner,railtype,nroad==2 and new_type or nil,
        nroad==0 and new_type or nil,r.owner,r.owner,nroad,2-nroad,1,reserved,2*price(o,"road",new_type))
    end
    return nil,"INVALID_PARAMETER"
  end

  -- One map tile but two different axis fields. These projections keep
  -- the existing road and rail follower/status contracts unchanged.
  function C.road_view(t)
    return {kind="crossing",axis=t.road_axis,roadtype=t.roadtype,tramtype=t.tramtype,
      road_bits=t.road_bits,tram_bits=t.tram_bits,slope=0,base=t.top,barred=t.barred}
  end
  function C.rail_view(t)
    return {kind="crossing",axis=t.rail_axis,owner=t.rail_owner,railtype=t.railtype,
      slope=0,base=t.top,reserved=t.reserved}
  end
  function C.rail_trackdirs(t) return crossing(t) and T.trackdirs(2^t.rail_axis) or 0 end

  local function reserved(ctx,id,t)
    if ctx and ctx.reserved then return not not ctx.reserved(id,t.rail_axis) end
    return not not t.reserved
  end
  local function set_reservation(ctx,id,t,on)
    if ctx and ctx.set_reservation then ctx.set_reservation(id,t.rail_axis,on)
    else t.reserved=on end
  end

  -- TrainCanLeaveTile and VehicleExitDir. Accept either actual raw motion
  -- state or derive both from the real trackdir of a committed subframe.
  function C.vehicle_exit(direction,trackbits)
    local d=floor(direction/2)
    if direction%2==0 and trackbits~=({[0]=32,8,16,4})[d] then d=(d+3)%4 end
    return d
  end
  function C.train_approach(board,v,ctx)
    if v.type~="train" or not v.front or v.crashed then return end
    local curr=tile_at(board,v.tile)
    if not curr then return end
    local track=v.trackbits or (v.td~=nil and 2^T.track(v.td))
    local dir=v.direction or (v.td~=nil and T.heading(v.td))
    if not track or dir==nil or track==64 or track==128 then return end
    if (curr.kind=="tunnel" or curr.kind=="bridge") and dir==2*curr.dir+1 then return end
    if (curr.kind=="depot" or curr.kind=="rail_depot") and dir==2*T.reverse_side(curr.dir)+1 then return end
    local d=C.vehicle_exit(dir,track)
    local id=board.adjacent(v.tile,d)
    local t=tile_at(board,id)
    if not crossing(t) or t.road_axis==d%2 or t.rail_owner~=v.owner then return end
    if ctx and ctx.compatible then
      if not ctx.compatible(v,t.railtype) then return end
    elseif not (v.compatible and v.compatible[t.railtype]) then
      return
    end
    return id
  end

  local function at(ctx,id)
    return (ctx and ctx.vehicles_at and id~=nil and ctx.vehicles_at(id)) or {}
  end
  local function on_crossing(ctx,id)
    for _,v in ipairs(at(ctx,id)) do if v.type=="train" then return true end end
    return false
  end
  function C.should_bar(board,id,ctx)
    local t=tile_at(board,id)
    if not crossing(t) then return false end
    if reserved(ctx,id,t) or on_crossing(ctx,id) then return true end
    local d=2-t.rail_axis
    for _,side in ipairs({d,T.reverse_side(d)}) do
      for _,v in ipairs(at(ctx,board.adjacent(id,side))) do
        if C.train_approach(board,v,ctx)==id then return true end
      end
    end
    return false
  end
  local function arm(board,id,a,dir,out)
    local next_=board.adjacent(id,dir)
    while next_~=nil do
      local t=board.tile(next_)
      if not crossing(t) or t.road_axis~=a then break end
      out[#out+1]=next_
      next_=board.adjacent(next_,dir)
    end
    return out
  end
  function C.group(board,id)
    local t=tile_at(board,id)
    if not crossing(t) then return {} end
    local d=2-t.road_axis
    return arm(board,id,t.road_axis,T.reverse_side(d),arm(board,id,t.road_axis,d,{id}))
  end
  local function change(board,id,barred,sound,ctx,out)
    local t=board.tile(id)
    if barred~=not not t.barred then
      t.barred=barred
      out[#out+1]={tile=id,barred=barred,sound=barred and sound and (not ctx or ctx.ambient~=false) or false}
    end
  end
  -- UpdateLevelCrossing treats all same-axis adjacent road tiles as one
  -- connected crossing for bar visuals. Occupied/waiting roads are not
  -- considered by the stock barrier or PBS predicate.
  function C.update(board,id,ctx,sound,force_barred)
    if sound==nil then sound=true end
    local group=C.group(board,id)
    local out={}
    local closed=not not force_barred
    for _,tile in ipairs(group) do if C.should_bar(board,tile,ctx) then closed=true;break end end
    for _,tile in ipairs(group) do change(board,tile,closed,sound,ctx,out) end
    return out
  end
  function C.try_reserve(board,id,track,ctx)
    local t=tile_at(board,id)
    if not crossing(t) or track~=t.rail_axis then return false,"INVALID_TRACK" end
    if reserved(ctx,id,t) then return false,"RESERVED" end
    set_reservation(ctx,id,t,true)
    return true,C.update(board,id,ctx,false)
  end
  function C.unreserve(board,id,track,ctx)
    local t=tile_at(board,id)
    if not crossing(t) or track~=t.rail_axis then return false,"INVALID_TRACK" end
    set_reservation(ctx,id,t,false)
    return true,C.update(board,id,ctx,true)
  end
  -- TrainCheckIfLineEnds call after route compatibility/line-signal checks.
  function C.maybe_bar(board,id,ctx)
    local t=tile_at(board,id)
    if not crossing(t) or t.barred then return {} end
    set_reservation(ctx,id,t,true)
    return C.update(board,id,ctx,true)
  end
  -- TrainController call after the last wagon's new tile is in the
  -- occupancy hash. PBS reservation may already have been removed.
  function C.tail_left(board,id,ctx) return C.update(board,id,ctx,true) end

  local function restrict_if_adjacent(board,id,mask,red)
    local t=tile_at(board,id)
    if crossing(t) and t.barred then return T.intersect(red,mask) end
    return red
  end
  function C.road_status(board,id,tram,side,ctx)
    local t=tile_at(board,id)
    if not crossing(t) or (tram and t.tramtype==nil or not tram and t.roadtype==nil) or
        (side~=nil and side%2~=t.road_axis) then return 0,0 end
    local tracks=T.trackdirs(2^t.road_axis)
    if not t.barred then return tracks,0 end
    if on_crossing(ctx,id) then return tracks,tracks end
    local d=2-t.road_axis
    local red=restrict_if_adjacent(board,board.adjacent(id,d),2^8+2^1,tracks)
    return tracks,restrict_if_adjacent(board,board.adjacent(id,T.reverse_side(d)),2^0+2^9,red)
  end
  -- Admission only, not a claim/resolver. RoadFindPathToDest tests red
  -- while choosing the next tile's direction, not between same-tile pixels.
  function C.road_step(board,from,to,td,tram,side,ctx)
    if from==to or not crossing(tile_at(board,to)) then return true end
    local allowed,red=C.road_status(board,to,tram,side,ctx)
    return T.valid_trackdir(td) and T.has(allowed,td) and not T.has(red,td) or false
  end
  function C.stock_collision_pair(road,train)
    return train.type=="train" and abs(train.z-road.z)<=6 and abs(train.x-road.x)<=4 and abs(train.y-road.y)<=4
  end
  -- The stock search bucket is centred on the road *front* (first part).
  -- A road part in a wormhole is ignored. Stock can crash road traffic
  -- left on the crossing; do not convert this into an implicit rail stop.
  function C.stock_collision(board,road_parts,train_candidates)
    local head=road_parts[1]
    if not head then return false end
    local candidates=train_candidates(head.x,head.y)
    for _,p in ipairs(road_parts) do
      if not p.wormhole and crossing(tile_at(board,p.tile)) then
        for _,v in ipairs(candidates) do if C.stock_collision_pair(p,v) then return true,p,v end end
      end
    end
    return false
  end
  return C
end
