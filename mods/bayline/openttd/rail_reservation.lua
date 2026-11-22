-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 pbs.cpp, rail_map.h, and CYapfReserveTrack in yapf_rail.cpp.
-- Reservation bits are undirected TrackBits, separate from signal aspects.
-- No signal propagation, occupancy, command authorization or train ownership.
return function(T,F,Cost)
  local R={}
  local band,bor,remove,has=T.intersect,T.union,T.remove,T.has
  local function plain(t) return t.kind=="rail" or t.kind=="signals" end
  local function is_platform(t) return t and t.kind=="station" end
  local function single_bit(t)
    if t.kind=="depot" or t.kind=="bridge" or t.kind=="tunnel" then return 2^(t.dir%2) end
    if t.kind=="station" or t.kind=="waypoint" or t.kind=="crossing" then return 2^t.axis end
  end
  local function set_bits(state,id,s)
    if s==0 then state[id]=nil else state[id]=s end
  end
  local function first_dir(bits)
    for td=0,13 do if has(bits,td) then return td end end
  end
  local function get_signal_type(t,td)
    local track=T.track(td)
    local second=track==T.LOWER or track==T.RIGHT
    local typ
    if second then
      typ=t.lower_signal_type or (t.lower_pbs and 4 or 0)
    else
      typ=t.upper_signal_type or (t.upper_pbs and 4 or 0)
    end
    return typ
  end

  -- state is a persisted id->stock TrackBits map. Single-track features
  -- physically store one flag in stock; here its angular bit is the value.
  -- Bridge and tunnel ends are independent map locations, not one alias.
  function R.bits(board,state,id)
    local t=id~=nil and board.tile(id)
    if not t then return 0 end
    if plain(t) then return state[id] or 0 end
    return band(state[id] or 0,single_bit(t) or 0)
  end

  local function valid(board,id,track)
    local t=id~=nil and board.tile(id)
    if not t or type(track)~="number" or track<0 or track>=6 or track%1~=0
        or not has(T.trackbits(T.status(t)),track) then return end
    return t
  end

  -- TracksOverlap / TryReserveTrack reject same, crossing, and shared
  -- branch overlaps. Only upper+lower or left+right can coexist.
  -- The stock mutation has no owner check; this is intentionally a low-
  -- level primitive for callers that already validated vehicle/path.
  function R.try_reserve(board,state,id,track)
    local t=valid(board,id,track)
    if not t then return false,"invalid_track" end
    local present=R.bits(board,state,id)
    local bit=2^track
    if band(present,bit)~=0 then return false,"reserved" end
    local next_=bor(present,bit)
    if plain(t) then
      if T.tracks_overlap(next_) then return false,"overlap" end
    elseif present~=0 then return false,"reserved" end
    set_bits(state,id,next_)
    return true
  end

  function R.unreserve(board,state,id,track)
    if not valid(board,id,track) then return false,"invalid_track" end
    set_bits(state,id,remove(R.bits(board,state,id),2^track))
    return true
  end

  -- Full directed status for a path search. Copy records; the map's track
  -- and signal state are unchanged. This state is the only reservation
  -- authority for the overlay (avoid mixing with an unrelated board).
  function R.view(board,state)
    local view={}
    for k,v in pairs(board) do view[k]=v end
    function view.tile(id)
      local old=id~=nil and board.tile(id)
      if not old then return end
      local t={}
      for k,v in pairs(old) do t[k]=v end
      t.reserved_bits=R.bits(board,state,id)
      if t.kind=="station" or t.kind=="waypoint" then t.reserved=t.reserved_bits~=0 end
      return t
    end
    return view
  end

  -- Directional platform bits from the starting platform tile (inclusive).
  -- Calls are only on legal station tiles and parallel travel directions.
  -- origin, when present, stops extension BEFORE that tile, as in YAPF.
  local function each_platform(board,begin_,dir,origin,visit)
    local start=board.tile(begin_)
    if not is_platform(start) or start.axis~=dir%2 then return false,begin_ end
    local id=begin_
    local n=F.platform(board,begin_,dir)
    for i=1,n do
      if i>1 and id==origin then break end
      if not visit(id,start.axis) then return false,id end
      id=board.adjacent(id,dir)
    end
    return true,id
  end

  -- CYapfReserveTrack::ReserveRailStationPlatform writes until conflict.
  -- On failure it leaves an acquired prefix, exactly like stock; the
  -- search allocator below rolls back those pieces with its whole attempt.
  function R.reserve_platform(board,state,begin_,dir,origin)
    local touched={}
    local ok,after=each_platform(board,begin_,dir,origin,function(id,track)
      if not R.try_reserve(board,state,id,track) then return false end
      touched[#touched+1]=id
      return true
    end)
    return ok,after,touched
  end

  -- SetRailStationPlatformReservation's write operation, unconditional.
  function R.set_platform(board,state,begin_,dir,reserved)
    return each_platform(board,begin_,dir,nil,function(id,track)
      set_bits(state,id,reserved and 2^track or 0)
      return true
    end)
  end

  -- Read-only stock FollowReservation. Its return does not declare a safe
  -- stop; callers may test the found tile with safe_end() separately.
  function R.follow_end(board,state,v,id,td,ignore_oneway)
    if not T.valid_trackdir(td) or band(R.bits(board,state,id),2^T.track(td))==0 then return id,td end
    local tile,direction=id,td
    local first_tile,first_td
    while true do
      local f=F.follow(board,v,tile,direction) -- ignore caller forbid_90 as stock does
      if not f.ok then break end
      local at=f.tile
      local reserved=band(f.trackdirs,T.trackdirs(R.bits(board,state,at)))
      if reserved==0 then
        if f.station then
          -- A reservation can end inside a platform that the track
          -- follower represents by a jump to the far platform end.
          for _=1,f.skip do
            at=board.adjacent(at,T.reverse_side(f.exit))
            if R.bits(board,state,at)~=0 then
              tile,direction=at,T.diagonal_trackdir(f.exit)
              break
            end
          end
        end
        break
      end
      local next_td=first_dir(reserved)
      local dest=board.tile(at)
      local along,against=false,false
      local typ=0
      if dest.kind=="signals" then
        local signals=dest.present_signals or 0
        along=band(signals,T.signal_along(next_td))~=0
        against=band(signals,T.signal_against(next_td))~=0
        typ=get_signal_type(dest,next_td)
      end
      if not ignore_oneway and against and not along and typ~=4 then break end
      tile,direction=at,next_td
      if first_tile==nil then first_tile,first_td=tile,direction
      elseif tile==first_tile and direction==first_td then break end
      if dest.kind=="depot" or (along and typ<4) then break end
    end
    return tile,direction
  end

  -- These share the source port already used by YAPF and agree with its
  -- own view of reservations and signal types.
  function R.safe_end(board,state,v,id,td,include_line_end,settings)
    return Cost.safe_waiting(R.view(board,state),v,id,td,include_line_end,settings)
  end
  function R.waiting_free(board,state,v,id,td,settings)
    return Cost.waiting_free(R.view(board,state),v,id,td,settings)
  end

  local function each_node(board,v,node,settings,visit)
    local id,td=node.tile,node.td
    local seen={}
    while id~=node.last_tile or td~=node.last_td do
      local key=tostring(id)..":"..td
      if seen[key] then return nil end
      seen[key]=true
      if not visit(id,td) then return false end
      local f=F.follow(board,v,id,td,settings)
      if not f.ok then return nil end
      local first=first_dir(f.trackdirs)
      if first==nil or f.trackdirs~=2^first then return nil end
      id,td=f.tile,first
    end
    return visit(id,td)
  end

  -- Select a safe reservation target, not necessarily the service
  -- destination. The stock routine scans nodes back toward the front
  -- of the acquired path, seeking the first safe tile within each node
  -- with fewer than two signals passed at its parent's endpoint.
  function R.choose_target(board,state,v,best,settings)
    if not best or not best.parent then return end
    local view=R.view(board,state)
    local out={tile=best.last_tile,td=best.last_td,node=best}
    local node=best
    while node.parent do
      if node.parent.signals<2 then
        local valid=each_node(view,v,node,settings,function(id,td)
          if Cost.safe_waiting(view,v,id,td,true,settings) then
            out={tile=id,td=td,node=node}
            return false
          end
          return true
        end)
        if valid==nil then return end
      end
      node=node.parent
    end
    out.origin=node.last_tile
    return out
  end

  -- Reserve destination-first by segment, forward by position within a
  -- segment, as stock. Lua journals storage bits instead of replaying
  -- UnreserveSingleTrack across the same walk. A refused whole path has
  -- no changed bits, including station prefixes and other stock
  -- parallel tracks occupied independently before this transaction.
  function R.try_path(board,state,v,target,settings)
    if not target or not target.node or target.origin==nil then return false,"no_target" end
    local view=R.view(board,state)
    if not Cost.waiting_free(view,v,target.tile,target.td,settings) then
      return false,"target_reserved",target.tile
    end
    local saved,claimed={},{}
    local failure,failed_tile
    local function acquire(id,track)
      local previous=state[id] or 0
      local ok,reason=R.try_reserve(board,state,id,track)
      if not ok then failure,failed_tile=reason,id;return false end
      if saved[id]==nil then saved[id]=previous end
      claimed[#claimed+1]={tile=id,track=track}
      return true
    end
    local node=target.node
    while node.parent and not failure do
      local walked=each_node(view,v,node,settings,function(id,td)
        if is_platform(board.tile(id)) then
          local ok,after=each_platform(board,id,T.entry_side(td),target.origin,acquire)
          if not ok then return false end
          -- Stock passes the tile by reference: after platform allocation
          -- its stop test uses the tile just past the acquired prefix.
          id=after
        elseif not acquire(id,T.track(td)) then return false end
        return id~=target.tile or td~=target.td
      end)
      if walked==nil then failure,failed_tile="path_changed",node.tile end
      node=node.parent
    end
    if failure then
      for id,previous in pairs(saved) do set_bits(state,id,previous) end
      return false,failure,failed_tile
    end
    return true,claimed
  end

  return R
end
