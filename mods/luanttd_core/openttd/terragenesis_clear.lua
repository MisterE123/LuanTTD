-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors; source OpenTTD 14.1 src/clear_cmd.cpp GenerateClearTile,
-- src/map_func.h ScaleBySize and RandomTileSeed, src/map.cpp direction offsets.
-- Bayline adapter holds temperate clear cover as an immutable sparse overlay.
local C={}
local floor,ceil=math.floor,math.ceil
local GRASS,ROUGH,ROCKS=0,1,2
C.grass,C.rough,C.rocks=GRASS,ROUGH,ROCKS

function C.describe(word)
  -- First byte is identical to TerraGenesis: map class and water subtype.
  -- Above that sits stock clear-ground type, independently of the shore enum.
  return word%16,floor(word/16)%16,floor(word/256)%16
end

function C.generate(base,next_random,pulse)
  assert(type(base)=="table" and type(base.tile)=="function" and base.rng_after
    and type(next_random)=="function","Temperate base raster and stock RNG required")
  local w,h=base.width,base.depth
  local area=w*h
  local state={base.rng_after[1],base.rng_after[2]}
  local function random() return next_random(state) end
  local function scaled(n) return ceil(n*area/65536) end
  local function within(i) return i>=0 and i<area end
  local function clear(i)
    return within(i) and base.tile(i%w+1,floor(i/w)+1)%16==0
  end
  local changed={}
  local function paint(i,v) changed[i]=v end
  local rough=scaled(random()%1024+0x400)
  local rocky=scaled(random()%128+0x80)
  for j=1,rough do
    if pulse and j%4096==0 then pulse() end
    local i=random()%area
    if clear(i) then paint(i,ROUGH) end
  end
  local offsets={[0]=-1,w,1,-w}
  for j=1,rocky do
    if pulse and j%512==0 then pulse() end
    local r=random()
    local i=r%area
    if clear(i) then
      local remaining=floor(r/65536)%16+5
      while true do
        paint(i,ROCKS)
        local new
        repeat
          remaining=remaining-1
          if remaining==0 then break end
          new=i+offsets[random()%4]
        until clear(new)
        if remaining==0 then break end
        i=new
      end
    end
  end
  local V={}
  for k,v in pairs(base) do V[k]=v end
  V.rng_after=state
  V.base_id=base.base_id.."/clear-v1"
  V.clear_attempts={rough=rough,rocky=rocky}
  function V.tile(x,z)
    local word=base.tile(x,z)
    if word and word%16==0 then
      -- Row-major compression key (same index as native TileIndex).
      return word+256*(changed[(z-1)*w+x-1] or GRASS)
    end
    return word
  end
  function V.clear_ground(x,z)
    local word=V.tile(x,z)
    if word and word%16==0 then return floor(word/256)%16 end
  end
  function V.storage_options()
    return {seed=base.seed,base_id=V.base_id,corner=function(_,x,z)return base.corner(x,z) end,
      tile=function(_,x,z)return V.tile(x,z) end}
  end
  return V
end
return C
