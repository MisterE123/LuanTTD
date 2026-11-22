-- SPDX-License-Identifier: GPL-2.0-only
-- Vanilla OpenTTD 14.1 house production, copyright OpenTTD contributors.
-- src/town_cmd.cpp TownGenerateCargo and TileLoop_Town;
-- src/table/town_land.h _original_house_specs; src/landscape.cpp RunTileLoop;
-- src/economy_func.h ScaleByCargoScale; src/core/random_func.hpp Chance16I.
-- This module models per-house cargo production, not town expansion,
-- construction stages, animated lifts, industry supply or NewGRF hooks.
local H={day_ticks=74,tile_period=256}
local floor,abs,max,min=math.floor,math.abs,math.max,math.min
local feedback={0xD8F,0x1296,0x2496,0x4357,0x8679,0x1030E,0x206CD,0x403FE,
                0x807B8,0x1004B2,0x2006A8,0x4004B2,0x800B87}

-- Stock binary tile order. Lua 5.1 has no native XOR. Precompute the
-- per-bit-position low-nibble XOR masks once for each LFSR width.
local xor16={}
for x=0,15 do
  local row={}
  for y=0,15 do
    local a,b,n=x,y,0
    for i=0,3 do
      if a%2~=b%2 then n=n+2^i end
      a,b=floor(a/2),floor(b/2)
    end
    row[y]=n
  end
  xor16[x]=row
end

local polynomial={}
for i,p in ipairs(feedback) do
  local row={}
  repeat row[#row+1]=p%16;p=floor(p/16) until p==0
  polynomial[i]=row
end

local function next_tile(tile,poly)
  local n=floor(tile/2)
  if tile%2==0 then return n end
  local value,p=0,1
  for i=1,#poly do
    value=value+xor16[n%16][poly[i]]*p
    n,p=floor(n/16),p*16
  end
  return value+n*p
end

-- Saved state: logs determine OpenTTD's row stride/feedback tap; head is
-- the next nonzero tile; counter is the last completed game tick. A caller
-- importing a stock map must keep the imported head and timer counter.
function H.new_clock(log_x,log_y,head,counter)
  assert(log_x>=6 and log_x<=12 and log_x==floor(log_x))
  assert(log_y>=6 and log_y<=12 and log_y==floor(log_y))
  head,counter=head or 1,counter or 0
  assert(head>0 and head<2^(log_x+log_y) and head==floor(head))
  assert(counter>=0 and counter==floor(counter))
  return {log_x=log_x,log_y=log_y,head=head,counter=counter}
end

function H.advance(clock,ticks,visit,before_tick)
  local bits=clock.log_x+clock.log_y
  local poly=assert(polynomial[bits-11],"Unsupported stock map size")
  local tiles_per_tick=2^(bits-8)
  local tile,time=clock.head,clock.counter
  for _=1,ticks do
    time=time+1
    if before_tick then before_tick(time) end
    local count=tiles_per_tick
    if time%256==0 then
      visit(0,time)
      count=count-1
    end
    for _=1,count do
      visit(tile,time)
      tile=next_tile(tile,poly)
    end
  end
  clock.head,clock.counter=tile,time
end

local function chance16(a,b,r)
  return floor(((r%65536)*b+floor(b/2))/65536)<a
end
H.chance16=chance16

function H.scale(amount,percentage,random)
  if amount==0 or percentage==100 then return amount end
  local scaled=floor(amount*percentage/100)
  if scaled==0 and chance16(1,max(floor(100/percentage),1),random()) then return 1 end
  return scaled
end

function H.original(rate,r,multiplier,divisor)
  local draw=r%256
  return draw<rate and (floor(floor(draw*multiplier/divisor)/8)+1) or 0
end
function H.binominal(rate,r,multiplier,divisor)
  local count=0
  for _=1,min(32,floor((rate+7)/8)) do
    count=count+r%2
    r=floor(r/2)
  end
  return floor(count*multiplier/divisor)
end

-- A compact projection of all 110 vanilla HouseSpec rows, indexed by the
-- original house ID. The flags describe the root tile only; subtiles get
-- their own row and are not inferred. Fields:
-- 1 population, 2 mail, 3 temperate build flag, 4 animated-lift flag,
-- 5 minimum year, 6 maximum year (5000000 is stock MAX_YEAR), 7 tile width,
-- 8 tile height (both 0 for the child entry of a multi-tile building).
H.specs={
  [0x00]={187,70,1,0,1963,5000000,1,1}, -- tall_office_block_1
  [0x01]={85,55,1,0,1957,5000000,1,1}, -- office_block_1
  [0x02]={40,20,1,0,1968,5000000,1,1}, -- small_block_of_flats_1
  [0x03]={5,2,1,0,0,5000000,1,1}, -- church_1
  [0x04]={220,85,1,1,1975,5000000,1,1}, -- large_office_block_1
  [0x05]={220,85,0,1,1975,5000000,1,1}, -- large_office_block_1
  [0x06]={30,12,1,0,0,5000000,1,1}, -- town_houses_1
  [0x07]={140,22,1,0,1959,5000000,1,2}, -- hotel_1
  [0x08]={0,22,0,0,1959,5000000,0,0}, -- hotel_1
  [0x09]={0,0,1,0,1945,5000000,1,1}, -- statue_1
  [0x0A]={0,0,1,0,1945,5000000,1,1}, -- fountain_1
  [0x0B]={0,0,1,0,0,5000000,1,1}, -- park_1
  [0x0C]={0,0,1,0,1935,5000000,1,1}, -- park_1
  [0x0D]={150,65,1,0,1951,5000000,1,1}, -- office_block_2
  [0x0E]={95,48,1,0,1930,1960,1,1}, -- shops_and_offices_1
  [0x0F]={95,48,1,0,1930,1960,1,1}, -- shops_and_offices_1
  [0x10]={95,48,1,0,1930,1960,1,1}, -- shops_and_offices_1
  [0x11]={130,50,1,0,1977,5000000,1,1}, -- modern_office_building_1
  [0x12]={6,10,1,0,1983,5000000,1,1}, -- warehouse_1
  [0x13]={110,55,1,0,1985,5000000,1,1}, -- office_block_3
  [0x14]={65,5,1,0,0,5000000,2,2}, -- stadium_1
  [0x15]={0,5,0,0,0,5000000,0,0}, -- stadium_1
  [0x16]={0,5,0,0,0,5000000,0,0}, -- stadium_1
  [0x17]={0,5,0,0,0,5000000,0,0}, -- stadium_1
  [0x18]={15,6,1,0,0,1951,1,1}, -- old_houses_1
  [0x19]={12,7,1,0,0,1952,1,1}, -- cottages_1
  [0x1A]={13,8,1,0,1931,5000000,1,1}, -- houses_1
  [0x1B]={100,35,1,0,1935,5000000,1,1}, -- flats_1
  [0x1C]={170,50,1,0,1963,5000000,1,1}, -- tall_office_block_2
  [0x1D]={100,40,1,0,0,1955,1,1}, -- shops_and_offices_2
  [0x1E]={180,64,1,0,1973,5000000,1,1}, -- shops_and_offices_3
  [0x1F]={35,23,1,0,0,5000000,1,1}, -- theater_1
  [0x20]={65,5,1,0,1958,5000000,2,2}, -- stadium_2
  [0x21]={0,5,0,0,1958,5000000,0,0}, -- stadium_2
  [0x22]={0,5,0,0,1958,5000000,0,0}, -- stadium_2
  [0x23]={0,5,0,0,1958,5000000,0,0}, -- stadium_2
  [0x24]={140,65,1,0,2000,5000000,1,1}, -- offices_1
  [0x25]={15,6,0,0,0,1960,1,1}, -- houses_2
  [0x26]={15,6,0,0,0,1960,1,1}, -- houses_2
  [0x27]={35,23,1,0,1945,5000000,1,1}, -- cinema_1
  [0x28]={180,5,1,0,1983,5000000,2,2}, -- shopping_mall_1
  [0x29]={0,5,0,0,1983,5000000,0,0}, -- shopping_mall_1
  [0x2A]={0,5,0,0,1983,5000000,0,0}, -- shopping_mall_1
  [0x2B]={0,5,0,0,1983,5000000,0,0}, -- shopping_mall_1
  [0x2C]={80,20,0,0,0,5000000,1,1}, -- flats_1
  [0x2D]={80,20,0,0,0,5000000,1,1}, -- flats_1
  [0x2E]={16,6,0,0,0,5000000,1,1}, -- houses_2
  [0x2F]={16,6,0,0,0,5000000,1,1}, -- houses_2
  [0x30]={14,6,0,0,0,1963,1,1}, -- houses_2
  [0x31]={14,6,0,0,0,1963,1,1}, -- houses_2
  [0x32]={135,60,0,0,1966,5000000,1,1}, -- tall_office_block_1
  [0x33]={135,60,0,0,1966,5000000,1,1}, -- tall_office_block_1
  [0x34]={170,70,0,0,1970,5000000,1,1}, -- tall_office_block_1
  [0x35]={170,70,0,0,1970,5000000,1,1}, -- tall_office_block_1
  [0x36]={210,80,0,0,1974,5000000,1,1}, -- tall_office_block_1
  [0x37]={210,80,0,0,1974,5000000,1,1}, -- tall_office_block_1
  [0x38]={10,5,0,0,0,5000000,1,1}, -- houses_2
  [0x39]={10,5,0,0,0,5000000,1,1}, -- houses_2
  [0x3A]={25,20,0,0,0,5000000,1,1}, -- shops_and_offices_1
  [0x3B]={25,20,0,0,0,5000000,1,1}, -- shops_and_offices_1
  [0x3C]={6,2,0,0,0,5000000,1,1}, -- church_1
  [0x3D]={6,2,0,0,0,5000000,1,1}, -- church_1
  [0x3E]={17,7,0,0,0,5000000,1,1}, -- houses_2
  [0x3F]={17,7,0,0,0,5000000,1,1}, -- houses_2
  [0x40]={90,45,0,0,0,1960,1,1}, -- shops_and_offices_1
  [0x41]={90,45,0,0,0,1960,1,1}, -- shops_and_offices_1
  [0x42]={140,25,0,0,1972,5000000,1,2}, -- hotel_1
  [0x43]={0,25,0,0,1972,5000000,0,0}, -- hotel_1
  [0x44]={140,25,0,0,1972,5000000,1,2}, -- hotel_1
  [0x45]={0,25,0,0,1972,5000000,0,0}, -- hotel_1
  [0x46]={105,50,0,0,1963,5000000,1,1}, -- shops_and_offices_1
  [0x47]={105,50,0,0,1963,5000000,1,1}, -- shops_and_offices_1
  [0x48]={190,75,0,0,1978,5000000,1,1}, -- tall_office_block_1
  [0x49]={190,75,0,0,1978,5000000,1,1}, -- tall_office_block_1
  [0x4A]={250,60,0,0,1967,5000000,2,1}, -- tall_office_block_1
  [0x4B]={0,60,0,0,1967,5000000,0,0}, -- tall_office_block_1
  [0x4C]={250,60,0,0,1967,5000000,2,1}, -- tall_office_block_1
  [0x4D]={0,60,0,0,1967,5000000,0,0}, -- tall_office_block_1
  [0x4E]={16,6,0,0,0,5000000,1,1}, -- houses_2
  [0x4F]={16,6,0,0,0,5000000,1,1}, -- houses_2
  [0x50]={16,5,0,0,0,5000000,1,1}, -- houses_2
  [0x51]={7,4,0,0,0,5000000,1,1}, -- houses_2
  [0x52]={45,15,0,0,0,5000000,1,1}, -- flats_1
  [0x53]={8,3,0,0,0,5000000,1,1}, -- church_1
  [0x54]={18,7,0,0,0,5000000,1,1}, -- houses_2
  [0x55]={90,24,0,0,1973,5000000,1,1}, -- flats_1
  [0x56]={120,25,0,0,1962,5000000,1,1}, -- flats_1
  [0x57]={250,80,0,0,1984,5000000,2,1}, -- tall_office_block_1
  [0x58]={0,80,0,0,1984,5000000,0,0}, -- tall_office_block_1
  [0x59]={80,23,0,0,0,5000000,1,1}, -- flats_1
  [0x5A]={180,90,0,0,1993,5000000,1,1}, -- tall_office_block_1
  [0x5B]={8,3,0,0,0,5000000,1,1}, -- church_1
  [0x5C]={18,5,0,0,0,5000000,1,1}, -- houses_2
  [0x5D]={7,3,0,0,0,5000000,1,1}, -- houses_2
  [0x5E]={15,6,0,0,0,5000000,1,1}, -- houses_2
  [0x5F]={17,6,0,0,0,5000000,1,1}, -- houses_2
  [0x60]={19,6,0,0,0,5000000,1,1}, -- houses_2
  [0x61]={21,6,0,0,0,5000000,1,1}, -- houses_2
  [0x62]={75,20,0,0,0,5000000,1,1}, -- tall_office_block_1
  [0x63]={35,9,0,0,0,5000000,1,2}, -- houses_2
  [0x64]={0,0,0,0,0,5000000,0,0}, -- houses_2
  [0x65]={85,18,0,0,0,5000000,1,1}, -- tall_office_block_1
  [0x66]={11,3,0,0,0,5000000,1,1}, -- igloo_1
  [0x67]={10,3,0,0,0,5000000,1,1}, -- tepees_1
  [0x68]={67,22,0,0,0,5000000,1,1}, -- shops_and_offices_1
  [0x69]={86,23,0,0,0,5000000,1,1}, -- shops_and_offices_1
  [0x6A]={95,28,0,0,0,5000000,1,1}, -- tall_office_block_1
  [0x6B]={30,10,0,0,0,5000000,1,1}, -- statue_1
  [0x6C]={25,8,0,0,0,5000000,1,1}, -- teapot_house_1
  [0x6D]={18,7,0,0,0,5000000,1,1}, -- piggy_bank_1
}

-- Completed vanilla house visit, in source call order: optional lift draw,
-- one unconditional town-tile random value (also used by rebuilding), then
-- passengers and mail. Mail always consumes its stock draw even when the
-- game adapter does not yet expose station mail. Return tile_rand so a future
-- house-growth port can use the same draw rather than consuming it twice.
function H.produce_tile(tile,tick,house,settings,random,emit)
  if not house.completed then return end
  local spec=assert(H.specs[house.id],"Non-vanilla house production is not implemented")
  if spec[4]==1 and not house.lift_has_destination then
    if chance16(1,2,random()) and settings.start_lift then settings.start_lift(house) end
  end
  local tile_random=random()
  local mode=settings.mode or "bitcount" -- OpenTTD 14.1 new games default
  local original=(mode=="original")
  assert(original or mode=="bitcount")
  if original or floor(tick/256)%4==tile%4 then
    local generate=original and H.original or H.binominal
    local function cargo(name,rate,multiplier,divisor)
      local amount=generate(rate,random(),multiplier,divisor)
      if amount==0 then return end
      if settings.recession then amount=floor((amount+1)/2) end
      emit(name,H.scale(amount,settings.percentage or 100,random))
    end
    -- Vanilla temperate passengers and mail use the default multiplier,
    -- exactly the divisor, so the ratio is represented by 1 / 1.
    cargo("passenger",spec[1],1,1)
    cargo("mail",spec[2],1,1)
  end
  return tile_random
end

-- map_house(x,z) uses zero-based stock coordinates and returns a HouseSpec
-- reference (house.id), its owner (house.town), and completion state.
-- emit(name,amount,x,z,house,tick) may apply catchment and station ratings.
-- before_tick is for running station rating before tile production at a
-- given tick, as OpenTTD's tick timer runs before RunTileLoop.
function H.advance_houses(clock,ticks,map_house,settings,random,emit,before_tick,landscape_tile)
  local width=2^clock.log_x
  H.advance(clock,ticks,function(tile,tick)
    local x,z=tile%width,floor(tile/width)
    if landscape_tile then landscape_tile(x,z,tick) end
    local house=map_house(x,z)
    if house then
      H.produce_tile(tile,tick,house,settings,random,function(name,amount)
        emit(name,amount,x,z,house,tick)
      end)
    end
  end,before_tick)
end

function H.single_tile_catchment(dx,dz,radius)
  return max(abs(dx),abs(dz))<=radius
end
H.bus_catchment=3
H.unmodified_catchment=4
return H
