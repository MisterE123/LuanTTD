-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, no warranty. OpenTTD 16.0-RC1 water_cmd.cpp:
-- IsWateredTile and DrawWaterEdges (stock CanalFeature::Dikes, offset 0).
-- Directions are the original 0..7 Direction enum. Output bits are the
-- sprite offsets, independent of the native geometry used to draw them.
local D={}
local floor=math.floor
local coast={
  [1]={[3]=true,[2]=true,[1]=true}, -- W sees SE, E, NE
  [2]={[1]=true,[0]=true,[7]=true}, -- S sees NE, N, NW
  [4]={[7]=true,[6]=true,[5]=true}, -- E sees NW, W, SW
  [8]={[5]=true,[4]=true,[3]=true}, -- N sees SW, S, SE
}
function D.watered(tile,from,source)
  local kind=tile.kind
  if kind=="clear_water" or kind=="water_rocks" or kind=="depot" or kind=="void" then return true end
  if kind=="lock" then return tile.dir%2==floor(from/2)%2 end
  if kind=="coast" or kind=="coast_rocks" or kind=="half_rail" then
    local row=coast[tile.slope]
    return row and row[from] or false
  end
  if kind=="oilrig" then
    return source.kind=="oilrig" or source.kind=="industry" or tile.on_water==true
  end
  if kind=="industry" then
    return source.kind=="oilrig" or (source.kind=="industry" and source.industry==tile.industry) or tile.on_water==true
  end
  if kind=="object" then return tile.on_water==true end
  if kind=="dock" then return tile.slope==0 end
  if kind=="buoy" then return true end
  if kind=="aqueduct" then return (tile.dir+2)%4==floor(from/2) end
  return false
end

local dx={-1,0,1,0,-1,1,1,-1}
local dz={0,1,0,-1,1,1,-1,-1}
local from={5,7,1,3,6,0,2,4}
local pair={{1,2},{2,3},{3,4},{4,1}}
function D.edges(read)
  local function wet(i)
    return read(dx[i],dz[i],from[i])
  end
  local a,b,c,d=wet(1),wet(2),wet(3),wet(4)
  local side={a,b,c,d}
  local mask=(a and 0 or 1)+(b and 0 or 2)+(c and 0 or 4)+(d and 0 or 8)
  for i,p in ipairs(pair) do
    local l,r=side[p[1]],side[p[2]]
    if not l and not r then mask=mask+2^(i+3)
    elseif l and r and not wet(i+4) then mask=mask+2^(i+7) end
  end
  return mask
end
return D
