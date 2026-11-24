-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 roadveh_cmd.cpp, FindClosestBlockingRoadVeh and
-- RoadVehFindCloseTo, copyright OpenTTD contributors.
-- The adapter enumerates the same spatial candidates as the stock map.
-- Returning a leader does not implement overtaking or stop reservations.
local R={}
local dx={[0]=-4,-8,-4,-1,4,8,4,1}
local dy={[0]=-4,-1,4,8,4,1,-4,-8}
local abs=math.abs
local function inside(d,v)
  return (d>=0 or (v>d and v<=0)) and (d<=0 or (v<d and v>=0))
end
function R.find(v,front,x,y,direction,candidates,update_blocked)
  if (front.reverse_ctr or 0)~=0 then return end
  local best,best_distance
  for _,other in ipairs(candidates) do
    local u,w=other.x-x,other.y-y
    if other.type=="road" and not other.in_depot and abs(other.z-v.z)<6
      and other.direction==direction and other.first~=v.first
      and inside(dx[direction],u) and inside(dy[direction],w) then
      local d=abs(u)+abs(w)
      if not best_distance or d<best_distance or (d==best_distance and other.id<best.id) then
        best,best_distance=other,d
      end
    end
  end
  if not best then
    front.blocked_ctr=0
    return
  end
  if update_blocked~=false then
    front.blocked_ctr=(front.blocked_ctr or 0)+1
    if front.blocked_ctr>1480 then return end
  end
  return best
end
return R
