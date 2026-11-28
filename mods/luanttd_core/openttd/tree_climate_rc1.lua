-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 tree_cmd.cpp GetRandomTreeType,
-- PlaceTree, PlantTreesOnTile and TreesOnTileCanSpread; tree_map.h.
local M={CACTUS=27,NORMAL=0,DESERT=1,RAINFOREST=2}
local floor,min=math.floor,math.min
function M.kind(landscape,zone,seed)
  if landscape=="arctic" then return floor(seed*8/256)+12 end
  if landscape=="tropic" then
    if zone==M.NORMAL then return floor(seed*4/256)+28 end
    if zone==M.DESERT then return seed<=12 and M.CACTUS or nil end
    return floor(seed*7/256)+20
  end
  if landscape=="toyland" then return floor(seed*9/256)+32 end
  return floor(seed*12/256)
end
function M.ground(target)
  if target.class==6 then return 3,3 end -- shore
  if target.snow then
    if target.ground==1 then return 4,3 end
    return 2,target.density
  end
  if target.ground==0 then return 0,target.density end
  if target.ground==1 then return 1,3 end
  return 2,target.density -- desert
end
function M.place(landscape,zone,random_word,target,keep_density)
  local t=M.kind(landscape,zone,floor(random_word/16777216))
  if not t then return end
  local ground,density=M.ground(target)
  if not keep_density and ground<2 then ground,density=floor(random_word/268435456)%2,3 end
  return {class=4,type=t,count=floor(random_word/4194304)%4+1,
    growth=min(floor(random_word/65536)%8,6),ground=ground,density=density,
    water_class=ground==3 and "sea" or nil}
end
function M.can_spread(landscape,zone,setting)
  if landscape=="tropic" then
    if zone==M.DESERT then return false end
    if zone==M.RAINFOREST then return setting==2 or setting==1 end
  end
  return setting==2
end

return M
