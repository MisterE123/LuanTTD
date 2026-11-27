-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: town_cmd.cpp TileLoop_Town and
-- DoCreateTown, map_func.h TileIndexToTileIndexDiffC. Host supplies
-- stock root shape and CanDeleteHouse; receipt never alters houses.
local R={initial=10}
local floor=math.floor
local function byte(word,shift) return floor(word/2^shift)%256 end
local function inward(city,tile) return math.max(0,math.min(city-tile,1)) end
-- RC1 town_map.h: only completed houses age at the economy year
-- edge, stopping at 255. A completion year is equivalent to the
-- yearly map-wide increment without scanning the Luanti world.
function R.age(house,year)
  if not house.completed then return 0 end
  local age=house.age or 0
  if year and house.age_epoch then age=age+math.max(year-house.age_epoch,0) end
  return math.min(age,255)
end
function R.visit(town,house,shape,can_remove,word,year)
  if not (house and house.completed and house.root and town.growing and can_remove
      and R.age(house,year)>=(shape.minimum_life or 0)) then return end
  town.time_until_rebuild=((town.time_until_rebuild or R.initial)-1)%65536
  if town.time_until_rebuild~=0 then return end
  town.time_until_rebuild=byte(word,16)+192
  local src={x=house.x,z=house.z}
  local result={clear=src}
  if byte(word,24)>=12 then
    result.replace={
      x=src.x+(shape.width==2 and inward(town.x,src.x) or 0),
      z=src.z+(shape.depth==2 and inward(town.z,src.z) or 0),
    }
  end
  return result
end
return R
