-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright OpenTTD contributors. 16.0-RC1 train_cmd.cpp:
-- both overloads of CheckTrainCollision, before news/rating/sound.
-- Coordinates are stock vehicle centers (including z in stock pixels).
local C={}
local floor,abs=math.floor,math.abs
function C.overlap(front,other)
  if other.kind~="train" or other.depot or other.owner~=front.owner or
      other.consist==front.consist then return false end
  local dx,dy=other.x-front.x,other.y-front.y
  -- Stock unsigned high-bit check on (dy + 7) | (dx + 7).
  if dx < -7 or dx > 8 or dy < -7 or dy > 8 then return false end
  local min_diff=floor((other.length+1)/2)+floor((front.length+1)/2)-1
  if dx*dx+dy*dy>min_diff*min_diff then return false end
  return abs(other.z-front.z)<=5
end

-- Host adapters preserve vehicle query order. The caller owns actual
-- crashes, re-reservation, rating and sound, so this scan cannot invent
-- a victim count or stop a train before its physical position is set.
function C.scan(front,world,crash)
  if front.depot then return false,0 end
  local victims=0
  local function scan(parts)
    for _,other in ipairs(parts) do
      if C.overlap(front,other) then victims=victims+crash(front.consist,other.consist) end
    end
  end
  if front.wormhole then
    scan(world.on_tile(front.tile))
    scan(world.on_tile(world.other_end(front.tile)))
  else
    scan(world.near(front.x,front.y,7))
  end
  return victims~=0,victims
end
return C
