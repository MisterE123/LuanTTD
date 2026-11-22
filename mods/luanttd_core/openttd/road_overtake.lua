-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, OpenTTD 14.1 roadveh_cmd.cpp RoadVehCheckOvertake,
-- CheckRoadBlockedForOvertaking and IndividualRoadVehicleController; table
-- selection uses roadveh_movement.h via the existing Motion kernel.
local O={DRIVE_SIDE=16,TIMEOUT=35,IN_ROAD_STOP=32}
local floor=math.floor
local trackdir={[0]=0,1,8,9} -- _dir_to_diag_trackdir: NE SE SW NW
local function has(mask,b) return floor(mask/2^b)%2~=0 end
local function straight(td) return td>=0 and td<16 and floor(td/2)%4==0 end
local function reversing(td) return td>=0 and td<16 and td%8>=6 end

-- board.is_station(tile) also covers drive-through stops.
-- board.tile_status(tile,v) returns compatible, trackdirbits, red_signals
-- using stock, unfiltered-by-entry-side GetTileTrackStatus.
-- board.vehicles_at(tile) returns complete logical tile membership (not
-- radius buckets or a per-lane list); absent data must return nil.
-- Vehicles use {id,first,type,tile,direction,state,tram,articulated,stopped,
-- speed,max_speed,acceleration,overtaking,overtaking_ctr}. For the look-ahead
-- only front engines are considered. Feed the leader resolved to its front
-- even when the ordinary proximity probe first found an articulated part.
function O.track_blocked(board,v,u,tile,td)
  if tile==nil then return true,"unknown-tile" end
  local compatible,bits,red=board.tile_status(tile,v)
  if not compatible then return true,"incompatible" end
  if type(bits)~="number" or type(red)~="number" then return true,"unknown-status" end
  if not has(bits,td) then return true,"no-continuation" end
  -- TrackdirBitsToTrackBits folds the reverse bank. TRACK_BIT_CROSS is
  -- bits 0 and 1: do not reject an orthogonal X|Y with no curved tracks.
  if floor(bits/4)%16~=0 or floor(bits/1024)%16~=0 then return true,"junction" end
  if red~=0 then return true,"barred-crossing" end
  local vehicles=board.vehicles_at(tile)
  if not vehicles then return true,"unknown-occupancy" end
  for _,other in ipairs(vehicles) do
    if other.type=="road" and other.first==other.id and other.id~=v.id and other.id~=u.id then
      return true,"other-vehicle"
    end
  end
  return false
end

-- Both arguments are the actual front actors. u is the stock proximity
-- probe's result resolved to its front before calling this function.
function O.check(board,v,u,original)
  if v.tram then return false,"tram" end
  if board.is_station(v.tile) or board.is_station(u.tile) then return false,"station" end
  if v.articulated then return false,"articulated" end
  if v.direction~=u.direction or v.direction%2==0 then return false,"direction" end
  if v.state>=O.IN_ROAD_STOP or not straight(v.state%16) then return false,"state" end
  -- AM_ORIGINAL ignores the measured acceleration. AM_REALISTIC uses the
  -- target max only when the leading vehicle is accelerating.
  if type(u.speed)~="number" then return false,"unknown-speed" end
  local leader_stopped=u.speed==0 or u.stopped
  if not leader_stopped then
    if not original and type(u.acceleration)~="number" then return false,"unknown-speed" end
    local moving_speed=u.speed
    if original or u.acceleration>0 then moving_speed=u.max_speed end
    if type(moving_speed)~="number" or type(v.max_speed)~="number" then return false,"unknown-speed" end
    if moving_speed>=v.max_speed then return false,"not-faster" end
  end
  local d=floor(v.direction/2)
  local td=trackdir[d]
  local blocked,why=O.track_blocked(board,v,u,v.tile,td)
  if blocked then return false,why end
  blocked,why=O.track_blocked(board,v,u,board.adjacent(v.tile,d),td)
  if blocked then return false,why end
  return true,leader_stopped and floor(O.TIMEOUT/2) or 0
end

function O.try(board,v,u,original)
  if (v.overtaking or 0)~=0 then return false,"already-overtaking" end
  local ok,value=O.check(board,v,u,original)
  if ok then v.overtaking,v.overtaking_ctr=O.DRIVE_SIDE,value end
  return ok,value
end

-- Call at the beginning of *each individual movement attempt*, including
-- a later stock-blocked attempt. Do not call once per game tick, per route
-- tile, or when speed accumulated insufficient movement budget.
function O.before_step(v,is_station)
  if (v.overtaking or 0)==0 then return nil end
  if is_station then
    v.overtaking=0
    return "station"
  end
  v.overtaking_ctr=(v.overtaking_ctr+1)%256 -- source counter is a byte
  if v.overtaking_ctr>=O.TIMEOUT and straight(v.state) then
    v.overtaking=0
    return "timeout"
  end
end

-- Branch on the selected next trackdir, even if the subsequent entry test
-- fails. This is not a generic heading change: turning on a curve retains
-- the opposite lane row until the source can safely switch the table.
function O.reversing(v,next_td)
  if reversing(next_td) then
    v.overtaking=0
    return true
  end
  return false
end

function O.active(v) return (v.overtaking or 0)~=0 end

-- Call only in the within-tile proximity branch, after a leader was found.
-- It ALWAYS consumed a failed movement attempt, including the initial
-- pass decision. In the separate tile-entry branch, the original copies
-- the leader's speed and waits without ever starting an overtake.
function O.within_blocked(board,v,leader,original)
  local started,why=false,nil
  if not O.active(v) then started,why=O.try(board,v,leader,original) end
  if not O.active(v) then v.speed=leader.speed or 0 end
  return false,started,why
end

function O.entry_blocked(v,leader)
  v.speed=leader.speed or 0
  return false
end

-- Do not clamp a saved counter at a curve, move the vehicle sideways by
-- hand, or mirror just the position without re-evaluating the next heading.
-- The source selects the opposite entire table row, then performs the
-- ordinary Rotate/Move test on the real, previous absolute position.
function O.next_pose(Motion,v,side)
  return Motion.step(v,side,O.active(v))
end

function O.enter_pose(Motion,v,x,y,td,side,frame)
  O.reversing(v,td)
  return Motion.enter(v,x,y,td,side,frame,O.active(v))
end

-- Conservative adapter for the current campaign when only normal roads
-- have authoritative per-tile status and occupancy. Unrecognized tiles
-- (including structures or stations in the look-ahead) veto initiation.
-- This is narrower than stock itself; its core can accept e.g. an unbarred
-- crossing if the real callback and surrounding state have been ported.
function O.plain_board(F,board,vehicles_at)
  return {
    is_station=function(id)
      local t=id~=nil and board.tile(id)
      return t and (t.kind=="drive_stop" or t.kind=="bay_stop" or t.kind=="station") or false
    end,
    adjacent=board.adjacent,
    vehicles_at=vehicles_at,
    tile_status=function(id,v)
      local t=board.tile(id)
      if not t or t.kind~="road" or t.roadtype==nil then return false end
      local allowed
      if board.compatible then
        allowed=board.compatible(v,id,t.roadtype)
      else
        allowed=v.compatible and v.compatible[t.roadtype] or false
      end
      return allowed,F.status(t,false),0
    end,
  }
end

return O
