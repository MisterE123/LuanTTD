-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- OpenTTD 14.1 water_cmd.cpp, station_cmd.cpp, rail_cmd.cpp,
-- tunnelbridge_cmd.cpp, ship_cmd.cpp and pathfinder/follow_track.hpp.
-- The board uses stock DiagDirections -X,+Z,+X,-Z (0,1,2,3).
return function(Track)
  local W={NE=0,SE=1,SW=2,NW=3,EC_NONE=0,EC_NO_WAY=4}
  local coast={[1]=32,[2]=4,[4]=16,[8]=8}
  local track_other_half={[4]=8,[8]=4,[16]=32,[32]=16}
  local blocked_ne=1+4+32
  local blocked_nw=2+16+4
  local single_corner={[1]=true,[2]=true,[4]=true,[8]=true}
  local water_types={water=true,sea=true,canal=true,river=true,coast=true,lock=true,ship_depot=true}
  local station_types={dock=true,buoy=true,oilrig=true,station=true}

  -- Track status of an actual tile; a pier/rig/industry that stores water
  -- class is not navigable unless a stock callback explicitly says so.
  -- Kinds "sea"/"canal"/"river" are shorthand for plain water.
  -- A lock/depot's direction controls passage on all its tiles.
  function W.status(t,x,z,side)
    -- RC1 GetTileTrackStatus_Water has no tracks for ClearRocks/CoastRocks.
    if not t or t.rocks then return 0 end
    local k=t.kind
    local bits,is_water=0,water_types[k] or k=="buoy"
    if k=="water" or k=="sea" or k=="canal" or k=="river" then
      if (t.slope or 0)==0 then bits=63 end
    elseif k=="buoy" then
      bits=63
    elseif k=="coast" then
      bits=coast[(t.slope or 0)%16] or 0
    elseif k=="lock" then
      bits=2^(t.dir%2)
    elseif k=="ship_depot" then
      bits=2^t.axis
    elseif k=="shore_rail" then
      if single_corner[t.slope] and t.plain~=false then bits=track_other_half[t.rail_bits] or 0 end
    elseif k=="aqueduct" and t.dir~=nil and (side==nil or side==Track.reverse_side(t.dir)) then
      bits=2^(t.dir%2)
    end
    if is_water then
      if x==0 then bits=Track.remove(bits,blocked_ne) end
      if z==0 then bits=Track.remove(bits,blocked_nw) end
    end
    return Track.trackdirs(bits)
  end

  -- GetEffectiveWaterClass: explicit map class wins. Aqueduct is always
  -- a canal; navigable railway halftile has no class field and counts as sea.
  function W.water_class(t)
    if not t then return nil end
    local k=t.kind
    if k=="aqueduct" then return "canal" end
    if k=="shore_rail" then return "sea" end
    if not (water_types[k] or station_types[k] or k=="industry" or k=="object" or k=="trees") then return nil end
    if t.water_class~=nil then return t.water_class end
    if k=="sea" or k=="canal" or k=="river" then return k end
    if k=="coast" then return "sea" end
    return nil -- provide water_class on a water/lock/depot/buoy record
  end

  function W.trackdirs(bits)
    local out={}
    for td=0,13 do if Track.valid_trackdir(td) and Track.has(bits,td) then out[#out+1]=td end end
    return out
  end
  W.exit_direction=Track.exit_side

  function W.at(board,id,side)
    local t=id~=nil and board.tile(id) or nil
    if not t then return 0 end
    local x,z=board.xy(id)
    return W.status(t,x,z,side)
  end

  -- CFollowTrackWater: ships allow 90-degree transitions, have no forced
  -- in-follower reversal (even on depot tiles), no owner check, and do
  -- not use the road/rail reservation mask. Reverse planning is external.
  function W.follow(board,vehicle,old_id,td)
    local exit=Track.valid_trackdir(td) and Track.exit_side(td) or nil
    local r={old_tile=old_id,old_td=td,exit=exit,tile=nil,trackdirs=0,skip=0,
      bridge=false,tunnel=false,station=false,error=W.EC_NONE,ok=false}
    if exit==nil or not Track.has(W.at(board,old_id),td) then
      r.error=W.EC_NO_WAY
      return r
    end
    local old=board.tile(old_id)
    if old.kind=="aqueduct" and old.dir==exit then
      r.tile=old.other
      r.skip=old.skip or 0
      r.bridge=true
    else
      r.tile=board.adjacent(old_id,exit)
    end
    local trackdirs=W.at(board,r.tile)
    r.trackdirs=Track.intersect(trackdirs,Track.reachable(exit))
    if r.trackdirs==0 then
      r.error=W.EC_NO_WAY
      return r
    end
    local next_tile=board.tile(r.tile)
    if next_tile.kind=="aqueduct" and not r.bridge and next_tile.dir~=exit then
      r.error=W.EC_NO_WAY
      return r
    end
    r.ok=true
    return r
  end

  function W.is_docking(board,id)
    if board.is_docking then return board.is_docking(id) end
    local t=board.tile(id)
    return t and t.docking==true or false
  end

  -- IsShipDestinationTile checks the four neighbours, not the adjacent
  -- slip's owner and not an arbitrary radius around the station.
  function W.ship_destination(board,id,station)
    if not W.is_docking(board,id) then return false end
    for d=0,3 do
      local near=board.adjacent(id,d)
      local t=near~=nil and board.tile(near)
      if t and (
          (t.kind=="dock" and t.station==station and t.water_part) or
          (t.kind=="industry" and t.neutral_station==station) or
          (t.kind=="oilrig" and t.station==station)) then return true end
    end
    return false
  end
  return W
end
