-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 16.0-RC1 (07b339c): clear_cmd.cpp
-- TileMayHaveRocks, TileMakeRocks, GenerateRocks, TileMayHaveRough,
-- GenerateRough and GenerateClearTile; map_func.h, map.cpp and
-- core/random_func.hpp supply map offsets and exact RNG projections.
local C={}
local floor,ceil=math.floor,math.ceil
local CLEAR,WATER=0,6
local SEA,COAST,RIVER=1,2,3 -- host base raster codes, not upstream enums.
local GRASS,ROUGH,ROCKS,DESERT=0,1,2,5
local ROCKY_WATER=4096 -- independent of dry cover and the water class
C.grass,C.rough,C.rocks=GRASS,ROUGH,ROCKS

function C.describe(word)
  return word%16,floor(word/16)%16,floor(word/256)%16,floor(word/ROCKY_WATER)%2==1
end

local function walk(tile,count,offsets,random,read,may_place,place)
  while true do
    place(tile,read(tile))
    local next_tile
    repeat
      count=count-1
      if count==0 then return end
      -- RandomRange uses the high two bits (ScaleToLimit), not modulo.
      next_tile=tile+offsets[floor(random()/1073741824)]
    until may_place(read(next_tile),true)
    tile=next_tile
  end
end

local function may_have_rocks(word,allow_water)
  if not word then return false end
  local kind,water,_,rocky=C.describe(word)
  if kind==CLEAR then return true end
  if kind~=WATER then return false end
  return water==COAST or allow_water and not rocky and (water==SEA or water==RIVER)
end

local function rock_walk(tile,count,offsets,random,read,write)
  if may_have_rocks(read(tile),false) then
    walk(tile,count,offsets,random,read,may_have_rocks,function(i,word)
      local kind,water,_,rocky=C.describe(word)
      if kind==CLEAR then write(i,word%256+256*ROCKS)
      elseif water~=RIVER and not rocky then write(i,word+ROCKY_WATER) end
    end)
  end
end

-- A fresh RC1 landmark can request the same source walk on the live
-- post-industry board, without re-running the global clear generation.
function C.rock_walker(width,random,read,write)
  local offsets={[0]=-1,width,1,-width}
  return function(tile,count) rock_walk(tile,count,offsets,random,read,write) end
end

function C.generate(base,next_random,pulse)
  assert(type(base.tile)=="function" and base.rng_after and type(next_random)=="function",
    "Stock ground pass requires a terrain raster and RNG")
  local w,h=base.width,base.depth
  local area=w*h
  local state={base.rng_after[1],base.rng_after[2]}
  local function random() return next_random(state) end
  local function scaled(n) return ceil(n*area/65536) end
  local offsets={[0]=-1,w,1,-w}
  local changed={}
  local function read(i)
    if i>=0 and i<area then return changed[i] or base.tile(i%w+1,floor(i/w)+1) end
  end
  local function may_have_rough(word)
    return word and word%16==CLEAR and floor(word/256)%16~=DESERT
  end
  local function roughen(i,word)
    changed[i]=word%256+256*ROUGH
  end
  local rocks=C.rock_walker(w,random,read,function(i,word) changed[i]=word end)
  local rough=scaled(random()%512+0x200)
  local rocky=scaled(random()%128+0x80)
  for j=1,rough do
    if pulse and j%4096==0 then pulse() end
    local r=random()
    local tile=r%area
    if may_have_rough(read(tile)) then walk(tile,floor(r/16777216)%8+1,offsets,random,read,may_have_rough,roughen) end
  end
  for j=1,rocky do
    if pulse and j%512==0 then pulse() end
    local r=random()
    local tile=r%area
    rocks(tile,floor(r/16777216)%16+5)
  end
  local V={}
  for k,v in pairs(base) do V[k]=v end
  V.rng_after=state
  V.base_id=base.base_id.."/clear-16.0-RC1"
  V.clear_attempts={rough=rough,rocky=rocky}
  function V.tile(x,z)
    if x>=1 and x<=w and z>=1 and z<=h then return read((z-1)*w+x-1) end
  end
  function V.clear_ground(x,z)
    local word=V.tile(x,z)
    if word and word%16==CLEAR then return floor(word/256)%16 end
  end
  function V.storage_options()
    return {seed=base.seed,base_id=V.base_id,corner=function(_,x,z)return base.corner(x,z) end,
      tile=function(_,x,z)return V.tile(x,z) end}
  end
  return V
end
return C
