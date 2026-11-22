-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 vehicle.cpp GetNewVehiclePos, train_cmd.cpp
-- _initial_tile_subcoord and TrainController's ordinary position commit.
-- Pure front-vehicle kinematics only: the caller owns track choice, entry
-- permissions, stations, depot transitions, spans, and speed scheduling.
return function(T)
local R={TILE_SIZE=16}
local floor=math.floor
-- The first index is stock Track, second is the direction of travel
-- across the tile boundary (not the side of the tile being entered).
-- false is the stock {0,0,0} sentinel for an unreachable track.
local initial={
  [0]={[0]={15,8,1},false,{0,8,5},false},
  {[0]=false,{8,0,3},false,{8,15,7}},
  {[0]=false,{7,0,2},{0,7,6},false},
  {[0]={15,8,2},false,false,{8,15,6}},
  {[0]={15,7,0},{8,0,4},false,false},
  {[0]=false,false,{0,8,4},{7,15,0}},
}
-- This is OpenTTD Direction (eight values), not DiagDirection (four).
local dx={[0]=-1,-1,-1,0,1,1,1,0}
local dy={[0]=-1,0,1,1,1,0,-1,-1}

-- tx/ty are stock tile coordinates. x/y are absolute integer subcoords.
-- Existing save users may store them directly; they are not mesh offsets.
function R.entry(tx,ty,track,enterdir)
  local row=initial[track]
  local b=row and row[enterdir]
  if not b then return end
  return {x=16*tx+b[1],y=16*ty+b[2],tx=tx,ty=ty,
    direction=b[3],td=T.trackdir_for_entry(track,enterdir)}
end

function R.entry_trackdir(tx,ty,td)
  if not T.valid_trackdir(td) then return end
  return R.entry(tx,ty,T.track(td),T.reverse_side(T.entry_side(td)))
end

-- Propose GetNewVehiclePos's sample without making any track choice.
-- At most one boundary is crossed in stock rail geometry. A malformed
-- position can cross a corner into a diagonal tile; stock would assert
-- there, so expose it as an invalid proposal rather than inventing a turn.
function R.advance(pose)
  local x=pose.x+dx[pose.direction]
  local y=pose.y+dy[pose.direction]
  local tx,ty=floor(x/16),floor(y/16)
  local mx,my=tx-pose.tx,ty-pose.ty
  local crossing=mx~=0 or my~=0
  local side
  if my==0 then
    if mx==-1 then side=T.NE end
    if mx==1 then side=T.SW end
  elseif mx==0 then
    if my==1 then side=T.SE end
    if my==-1 then side=T.NW end
  end
  return {x=x,y=y,tx=tx,ty=ty,direction=pose.direction,td=pose.td,
    enterdir=side,crossing=crossing,invalid=crossing and side==nil}
end

-- Kinematic commit corresponding to TrainController, for a track choice
-- already approved by the adapter. At a boundary the raw position is
-- snapped to the legal entry subcoords and heading in the SAME stock step.
-- A nil next trackdir yields a boundary proposal, never a guessed turn.
function R.step(pose,next_td)
  local p=R.advance(pose)
  if p.invalid then return "invalid",p end
  if not p.crossing then return "move",p end
  if next_td==nil then return "boundary",p end
  if not T.valid_trackdir(next_td) then return "invalid",p end
  local enter=R.entry(p.tx,p.ty,T.track(next_td),p.enterdir)
  if not enter or enter.td~=next_td then return "invalid",p end
  enter.enterdir=p.enterdir
  return "enter",enter
end

-- Presentation helper only. Native 2-node tiles start at tx*2-.5 and
-- stock subcoordinate 8 is exactly their mesh center. Keep unit length
-- and exact sampled state; the renderer alone may interpolate between.
function R.world_pose(pose)
  return pose.x/8-.5,pose.y/8-.5,(pose.direction-3)*math.pi/4
end

return R
end
