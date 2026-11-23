-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 src/pathfinder/follow_track.hpp rail specialization,
-- Rail90DegTurnDisallowed (rail.h), and Station::GetPlatformLength.
-- This is the follower, not rail YAPF search, traffic, or PBS allocation.
return function(T)
local R={EC_NONE=0,EC_OWNER=1,EC_RAIL_ROAD_TYPE=2,EC_90DEG=3,EC_NO_WAY=4,EC_RESERVED=5}
local band,remove,union,reverse=T.intersect,T.remove,T.union,T.reverse_side

-- RC1 railtypes.h stock powered sets (not the broader physical
-- compatibility set of electric rail). The live consist's union of
-- powered engine types supersedes them, per train_cmd.cpp ConsistChanged.
local stock_power={[0]={[0]=true,[1]=true},[1]={[1]=true},[2]={[2]=true},[3]={[3]=true}}
function R.stock_railtype(gauge) return stock_power[gauge]~=nil end
function R.stock_traction(engine,consist_mask)
  return consist_mask or stock_power[engine or 0]
end

-- board.tile(id) -> tile record or nil; board.adjacent(id,side) -> id or nil.
-- Record kind/trackbits/axis/dir/signals per rail_track.lua plus:
-- owner, railtype, station ID (platforms), other/skip (bridge/tunnel),
-- reserved_bits (station tiles store a separate reserved flag upstream),
-- bridge_speed; board.railtype(id) -> {allow_90,disallow_90,max_speed,
-- compatible={[other_railtype]=true}}. The default compatibility is
-- identical types only. Train v has owner and compatible[type]=true.
local function type_info(board,typ)
  return board.railtype and board.railtype(typ) or nil
end
local function type_equal_or_compatible(board,typ,other)
  if typ==other then return true end
  local info=type_info(board,typ)
  return info and info.compatible and info.compatible[other]==true
end
local function disallow_90(board,old,new,default)
  if old==nil or new==nil then return default end
  local function restrictive(typ)
    local info=type_info(board,typ)
    return (info and info.disallow_90) or (not (info and info.allow_90) and default)
  end
  return restrictive(old) or restrictive(new)
end
local function is_station(t)
  return t and (t.kind=="station" or t.kind=="waypoint")
end
local function span(t)
  return t and (t.kind=="bridge" or t.kind=="tunnel")
end
local function continues(board,a,b)
  return a.kind=="station" and b and b.kind=="station" and not b.blocked and
    a.axis==b.axis and a.station~=nil and a.station==b.station and
    type_equal_or_compatible(board,b.railtype,a.railtype)
end

R.disallow_90=disallow_90

-- Inclusive count and ending tile of a stock directional station platform.
-- Rail waypoints report a single tile even when their order spans many tiles.
function R.platform(board,first,dir)
  local start=board.tile(first)
  local last,length=first,1
  local after=board.adjacent(last,dir)
  while after~=nil and continues(board,start,board.tile(after)) do
    last,length=after,length+1
    after=board.adjacent(last,dir)
  end
  return length,last
end

-- Returns all CFollowTrack fields for a fresh attempt. opts.forbid_90 picks
-- the No90 specialization fallback, overridden by railtype flags.
function R.follow(board,v,old_id,old_td,opts)
  local old=board.tile(old_id)
  local res={old_tile=old_id,old_td=old_td,tile=nil,trackdirs=0,
    exit=T.exit_side(old_td),skip=0,station=false,bridge=false,tunnel=false,
    error=R.EC_NONE,ok=false}
  local function fail(err) res.error=err;return res end
  if not T.valid_trackdir(old_td) or not T.has(T.status(old),old_td) then
    return fail(R.EC_NO_WAY) -- invalid source tile/track would assert upstream
  end

  if old.kind=="depot" and old.dir~=res.exit then
    res.tile=old_id;res.trackdirs=T.trackdirbit(T.reverse_trackdir(old_td))
    res.exit=old.dir;res.reversed=true;res.ok=true
    return res
  end

  if span(old) and old.dir==res.exit then
    res.tile=old.other;res.skip=old.skip or 0
    res.bridge=old.kind=="bridge";res.tunnel=old.kind=="tunnel"
  else
    res.tile=board.adjacent(old_id,res.exit)
  end
  local enter=res.tile~=nil and board.tile(res.tile) or nil
  res.station=not res.bridge and not res.tunnel and is_station(enter) or false
  res.trackdirs=band(T.status(enter),T.reachable(res.exit))
  if res.trackdirs==0 then return fail(R.EC_NO_WAY) end

  if enter.kind=="depot" and enter.dir~=reverse(res.exit) or enter.owner~=v.owner then
    return fail(R.EC_NO_WAY) -- the stock rail follower uses NO_WAY for foreign rail
  end
  if enter.railtype==nil or not (v.compatible and v.compatible[enter.railtype]) then
    return fail(R.EC_RAIL_ROAD_TYPE)
  end
  if ((enter.kind=="bridge" and not res.bridge) or (enter.kind=="tunnel" and not res.tunnel)) and enter.dir~=res.exit then
    return fail(R.EC_NO_WAY)
  end

  if res.station then
    res.station_entry=res.tile
    local length
    length,res.tile=R.platform(board,res.tile,res.exit)
    res.skip=length-1
  end
  local finish=board.tile(res.tile)
  if disallow_90(board,old.railtype,finish.railtype,opts and opts.forbid_90 or false) then
    res.trackdirs=remove(res.trackdirs,T.crossing_trackdirs(old_td))
    if res.trackdirs==0 then return fail(R.EC_90DEG) end
  end
  res.ok=true
  return res
end

-- Stock CFollowTrackFreeRail::MaskReservedTracks is explicit, after Follow.
-- Copy the result to keep unmasked and masked route policies separable.
function R.mask_reserved(board,result)
  if not result.ok then return result end
  local res={}
  for k,v in pairs(result) do res[k]=v end
  local function blocked()
    res.trackdirs=0;res.error=R.EC_RESERVED;res.ok=false
    return res
  end
  if res.station then
    local tile=res.station_entry
    while tile~=res.tile do
      if board.tile(tile).reserved then return blocked() end
      tile=board.adjacent(tile,res.exit)
    end
  end
  local dest=board.tile(res.tile)
  local reserved=dest.reserved_bits or 0
  if is_station(dest) and dest.reserved then reserved=union(reserved,T.trackbit(dest.axis)) end
  res.trackdirs=remove(res.trackdirs,T.trackdirs(reserved))
  local candidates=T.trackbits(res.trackdirs)
  for t=0,5 do
    if T.has(candidates,t) and T.tracks_overlap(union(reserved,T.trackbit(t))) then
      res.trackdirs=remove(res.trackdirs,T.trackdirs(T.trackbit(t)))
    end
  end
  if res.trackdirs==0 then return blocked() end
  return res
end

function R.speed_limit(board,t)
  local max=2147483647
  if t.kind=="bridge" and t.bridge_speed~=nil then max=math.min(max,t.bridge_speed) end
  local info=type_info(board,t.railtype)
  if info and (info.max_speed or 0)>0 then max=math.min(max,info.max_speed) end
  return max,0
end

return R
end
