-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Road-direction tables and CFollowTrackRoad road specialization ported from
-- OpenTTD 14.1: src/rail.cpp, track_func.h, road_cmd.cpp, station_cmd.cpp,
-- tunnelbridge_cmd.cpp, pathfinder/pathfinder_func.h and
-- pathfinder/follow_track.hpp. No path search is performed here.
--
-- Board adapter: tile(id) -> record or nil, adjacent(id,stock_diagdir) -> id
-- or nil. Stock DiagDirection uses NE=0, SE=1, SW=2, NW=3. A Bayline caller
-- maps from neighbor numbers 1=-z, 2=+x, 3=+z, 4=-x with 4-direction.
-- Tile records use kind=road|crossing|depot|bay_stop|drive_stop|bridge|tunnel,
-- road_bits/tram_bits in upstream order (+NW=1, +SW=2, +SE=4, +NE=8);
-- roadtype/tramtype control class existence; dir is the stock entrance
-- or platform direction. Crossing uses axis=0|1, bridge/tunnel use
-- other/skip (number of interior tiles) and dir pointing into the structure.
-- Optional board.edge_available(from,to,dir,vehicle) supplies valid world
-- boundaries / grade policy (not a new stock pathfinding rule).
local R={NE=0,SE=1,SW=2,NW=3}
R.EC_NONE,R.EC_OWNER,R.EC_RAIL_ROAD_TYPE,R.EC_NO_WAY=0,1,2,4
local floor,min=math.floor,math.min
local exitdir={[0]=0,1,0,1,2,1,0,0,2,3,3,2,3,0}
local reachable={[0]=1+8+4096,2+16+4,256+1024+32,512+8192+2048}
local road_trackbits={[0]=0,0,0,16,0,2,8,26,0,4,1,21,32,38,41,63}
local road_bit={[0]=8,4,2,1}
local diag_trackdir={[0]=0,1,8,9}
local drd={[0]=0x101,0x100,1,0}
local masks={}
for d=0,15 do masks[d]=2^d end
local function has(bits,d)
  return floor(bits/masks[d])%2==1
end
local function band(a,b)
  local r=0
  for i=0,13 do
    if has(a,i) and has(b,i) then r=r+masks[i] end
  end
  return r
end
local function reverse_direction(d) return (d+2)%4 end
local function reverse_trackdir(td) return (td+8)%16 end
local function axis_bit(dir) return masks[dir%2] end
R.has_trackdir=has
R.reverse_direction=reverse_direction
R.reverse_trackdir=reverse_trackdir
function R.exit_direction(td) return exitdir[td] end
function R.direction_trackdir(d) return diag_trackdir[d] end
function R.reachable_trackdirs(d) return reachable[d] end
function R.trackdirs(bits)
  local out={}
  for i=0,13 do if has(bits,i) then out[#out+1]=i end end
  return out
end
local function class(t,tram)
  if not t then return nil end
  if tram then return t.tramtype end
  return t.roadtype
end
local function has_roadbit(bits,dir)
  return floor(bits/road_bit[dir])%2==1
end
local function single_tram(t)
  if not t or t.kind~="road" then return nil end
  for dir=0,3 do
    if road_bit[dir]==t.tram_bits then return dir end
  end
end

-- The road subset of the three upstream GetTileTrackStatus callbacks,
-- as used for route reachability. Waiting/crossing red-signal bits do
-- not change TrackdirBits, and are not consumed by the road follower.
function R.status(t,tram,side)
  if class(t,tram)==nil then return 0 end
  local kind=t.kind
  if kind=="road" then
    local bits=(tram and t.tram_bits or (not tram and t.road_bits)) or 0
    if t.roadworks or (side~=nil and not has_roadbit(bits,side)) then return 0 end
    return road_trackbits[bits]*drd[tram and 0 or (t.disallowed or 0)]
  elseif kind=="crossing" then
    if side~=nil and side%2~=t.axis then return 0 end
    return masks[t.axis]*0x101
  elseif kind=="depot" then
    if side~=nil and side~=t.dir then return 0 end
    return axis_bit(t.dir)*0x101
  elseif kind=="bay_stop" or kind=="drive_stop" then
    if side~=nil and (side%2~=t.dir%2 or (kind=="bay_stop" and side~=t.dir)) then return 0 end
    return axis_bit(t.dir)*0x101
  elseif kind=="bridge" or kind=="tunnel" then
    if side~=nil and side~=reverse_direction(t.dir) then return 0 end
    return axis_bit(t.dir)*0x101
  end
  return 0
end

-- GetTrackdirBitsForRoad: a single tram bit has synthetic straight
-- trackdirs so the follower can model a tram reversing in this tile.
-- Ordinary buses do not have valid track on a half-built plain road.
function R.tile_trackdirs(t,tram)
  local bits=R.status(t,tram)
  if tram and bits==0 then
    local dir=single_tram(t)
    if dir~=nil then return axis_bit(dir)*0x101 end
  end
  return bits
end
function R.origin_trackdirs(t,tram,entry)
  return band(R.tile_trackdirs(t,tram),reachable[entry])
end

local function allowed_type(board,v,t,id)
  local typ=class(t,v.tram)
  if typ==nil then return false end
  -- Lua 5.1 number masks cannot encode arbitrary positions of the stock
  -- 64-bit RoadTypes flag. A table (or the adapter callback) can.
  if board.compatible then return board.compatible(v,id,typ) end
  return not v.compatible or v.compatible[typ]==true
end

-- A faithful road follower over the adapter, including in-place reversal
-- transitions. Failure still returns the attempted fields and error, as
-- CFollowTrackRoad does. No global state is mutated.
local function force_reverse(res,leave)
  res.tile=res.old_tile
  res.trackdirs=masks[reverse_trackdir(res.old_td)]
  res.exit=leave
  res.ok=true
  res.reversed=true
  return res
end

local function try_reverse(res,old,v)
  if not v.tram then
    res.exit=reverse_direction(res.exit)
    res.tile=res.old_tile
    res.trackdirs=R.origin_trackdirs(old,false,res.exit)
    if res.trackdirs~=0 then
      res.ok=true;res.reversed=true
      return res
    end
  end
  res.error=R.EC_NO_WAY
  return res
end

local function can_enter(board,v,entry,res)
  if entry.kind=="bay_stop" and entry.dir~=reverse_direction(res.exit) then
    res.error=R.EC_NO_WAY;return false
  end
  local single=v.tram and single_tram(entry)
  if single and single~=reverse_direction(res.exit) then
    res.error=R.EC_NO_WAY;return false
  end
  if entry.kind=="depot" then
    if entry.dir~=reverse_direction(res.exit) then
      res.error=R.EC_NO_WAY;return false
    end
    if entry.owner~=v.owner then
      res.error=R.EC_OWNER;return false
    end
  end
  if not allowed_type(board,v,entry,res.tile) then
    res.error=R.EC_RAIL_ROAD_TYPE;return false
  end
  if (entry.kind=="tunnel" and not res.tunnel or
      entry.kind=="bridge" and not res.bridge) and entry.dir~=res.exit then
    res.error=R.EC_NO_WAY;return false
  end
  return true
end

function R.follow(board,v,old_id,old_td,source_record)
  local old=source_record or board.tile(old_id)
  local res={old_tile=old_id,old_td=old_td,tile=nil,trackdirs=0,
    exit=exitdir[old_td],skip=0,station=false,bridge=false,tunnel=false,
    error=R.EC_NONE,ok=false}
  if res.exit==nil or not (has(R.status(old,v.tram),old_td) or
      (v.tram and single_tram(old)~=nil)) then
    res.error=R.EC_NO_WAY
    return res
  end

  if old.kind=="depot" and old.dir~=res.exit then return force_reverse(res,old.dir) end
  local single=v.tram and single_tram(old)
  if single==reverse_direction(res.exit) or
      (old.kind=="bay_stop" and old.dir==reverse_direction(res.exit)) then
    return force_reverse(res,reverse_direction(res.exit))
  end
  if ((old.kind=="bay_stop" or old.kind=="depot") and old.dir~=res.exit) or
      (single and single~=res.exit) then
    res.error=R.EC_NO_WAY
    return res
  end

  if (old.kind=="bridge" or old.kind=="tunnel") and old.dir==res.exit then
    res.tile=old.other
    res.skip=old.skip or 0
    res.bridge=old.kind=="bridge"
    res.tunnel=old.kind=="tunnel"
  else
    res.tile=board.adjacent(old_id,res.exit)
  end
  local entry=res.tile~=nil and board.tile(res.tile) or nil
  res.station=entry~=nil and not res.bridge and not res.tunnel and
    (entry.kind=="bay_stop" or entry.kind=="drive_stop")
  res.trackdirs=R.tile_trackdirs(entry,v.tram)
  if res.trackdirs~=0 and not res.bridge and not res.tunnel and board.edge_available and
      not board.edge_available(old_id,res.tile,res.exit,v) then
    res.trackdirs=0
  end
  if res.trackdirs==0 then return try_reverse(res,old,v) end
  res.trackdirs=band(res.trackdirs,reachable[res.exit])

  if res.trackdirs==0 or not can_enter(board,v,entry,res) then
    if not v.tram then return try_reverse(res,old,v) end
    if res.trackdirs==0 then res.error=R.EC_NO_WAY end
    return res
  end
  res.ok=true
  return res
end

function R.speed_limit(t,tram)
  local limit=2147483647
  if t.kind=="bridge" and t.bridge_speed then limit=min(limit,t.bridge_speed*2) end
  local road=tram and t.tram_speed or (not tram and t.road_speed)
  if road and road>0 then limit=min(limit,road) end
  return limit,0
end

return R
