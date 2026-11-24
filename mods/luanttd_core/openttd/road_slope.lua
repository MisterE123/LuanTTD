-- SPDX-License-Identifier: GPL-2.0-only
-- Originally part of OpenTTD, copyright the OpenTTD contributors. No warranty.
-- Lua port (2026-11-22) of OpenTTD 14.1 src/road_cmd.cpp:
-- _invalid_tileh_slopes_road, GetRoadFoundation, CheckRoadSlope.
-- Bayline +X is OpenTTD SW and +Z is SE. Edges -Z,+X,+Z,-X
-- correspond exactly to ROAD_NW (1), SW (2), SE (4), NE (8).
local R={}
local invalid_level={[0]=0,12,9,8,3,0,1,0,6,4,0,0,2,0,0}
local invalid_straight={[0]=0,0,0,5,0,15,10,15,0,10,15,15,5,15,15}
local high_corner={[23]=2,[27]=1,[29]=8,[30]=4}
local one={[1]=true,[2]=true,[4]=true,[8]=true}
local function has(n,b) return math.floor(n/b)%2==1 end
local function combine(a,b,op)
  local c=0
  for _,i in ipairs({1,2,4,8}) do if op(has(a,i),has(b,i)) then c=c+i end end
  return c
end
local function bor(a,b) return combine(a,b,function(x,y) return x or y end) end
local function intersects(a,b)
  for _,i in ipairs({1,2,4,8}) do if has(a,i) and has(b,i) then return true end end
  return false
end
function R.foundation(mask,bits)
  if mask==0 or bits==0 then return "none" end
  mask=high_corner[mask] or mask
  if not intersects(invalid_level[mask],bits) then return "leveled" end
  if not one[mask] and not intersects(invalid_straight[mask],bits) then return "none" end
  return bits==10 and "x" or "y"
end
function R.prepare(mask,pieces,existing,other,build_on_slopes)
  pieces=combine(pieces,existing,function(x,y) return x and not y end)
  if pieces==0 then return nil,"ALREADY_BUILT" end
  if mask==0 then return pieces,false end
  mask=high_corner[mask] or mask
  local type_bits=bor(existing,pieces)
  if build_on_slopes and not intersects(invalid_level[mask],bor(other,type_bits)) then
    return pieces,other==0 and existing==0
  end
  pieces=bor(pieces,(pieces%4)*4+math.floor(pieces/4))
  type_bits=bor(existing,pieces)
  if (type_bits==5 or type_bits==10) and (other==type_bits or other==0)
      and not intersects(invalid_straight[mask],bor(other,type_bits)) then
    if one[mask] then
      if build_on_slopes then return pieces,other==0 and existing==0 end
    else
      return pieces,one[existing]==true and R.foundation(mask,existing)=="none"
    end
  end
  return nil,"WRONG_SLOPE"
end
-- OpenTTD 16.0-RC1 road_cmd.cpp RemoveRoad, normal-tile geometry. The
-- orchestrator still owns the occupancy, town permission and payment.
function R.remove(mask,pieces,present,other,build_on_slopes)
  mask=high_corner[mask] or mask
  local before=R.foundation(mask,present)
  if ((other==5 or other==10) and intersects(other,invalid_level[mask]))
      or (mask~=0 and not build_on_slopes) then
    pieces=bor(pieces,(pieces%4)*4+math.floor(pieces/4))
  end
  pieces=combine(pieces,present,function(a,b)return a and b end)
  if pieces==0 then return nil,"NO_ROAD_PIECES" end
  local after=present-pieces
  if mask~=0 and after~=0 and combine(invalid_level[mask],after,function(a,b)return a and b end)==after then
    return nil,"WRONG_SLOPE"
  end
  return {removed=pieces,road_bits=after,foundation=before=="none" and R.foundation(mask,after)~="none"}
end
return R
