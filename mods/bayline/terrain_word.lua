-- Terrain-only typed words and detached profile layout. The four-byte
-- WorldStorage word and version-1 sparse save envelope remain unchanged.
local M={}
local floor=math.floor
local byte,char=string.byte,string.char
local RIVER,TAG,STRIDE=54,16777216,65536
M.cover={VOID=0,LAND_FLAT=1,LAND_GRADED=2,WATER_FLAT=3,WATER_GRADED=4,
  COAST=5,COAST_TREES=6,LOCK=7,DEPOT=8,WATER_UNRESOLVED=9,RIVER_FLAT=10,RIVER_GRADED=11}
M.stride=7
local function int(n,lo,hi)
  return type(n)=="number" and n>=lo and n<=hi and n==floor(n)
end
function M.low(word) return word%16,floor(word/16)%16 end
function M.word(data,i)
  local a,b,c,d=byte(data,i,i+3)
  return a+256*b+65536*c+16777216*d
end
function M.river(random)
  assert(int(random,0,255),"stock river random must be an unsigned byte")
  return RIVER+TAG+STRIDE*random
end
function M.river_bits(word)
  -- Reserved top-byte tag is independent of the value in byte three.
  -- In particular a known random byte of 0 is different from absent.
  if int(word,TAG,2*TAG-1) and word%STRIDE==RIVER then return floor(word/STRIDE)%256 end
end
function M.valid(word)
  if not int(word,0,2*TAG-1) then return false end
  local class,ground=M.low(word)
  if not M.valid_descriptor(class,ground) then return false end
  if class==6 and ground==3 then return M.river_bits(word)~=nil end
  return word<STRIDE
end
function M.valid_descriptor(class,ground)
  return int(class,0,10) and (ground==nil or int(ground,0,5))
end
function M.is_promoted(base_id)
  return type(base_id)=="string" and base_id:sub(-5)=="/r3p1"
end
function M.describe(word) return M.low(word) end
function M.storage_options(raster)
  -- Explicit promotion is a storage adapter only. The source generator
  -- and live campaign still consume separate .tile and .river_bits.
  assert(type(raster.storage_options)=="function" and type(raster.river_bits)=="function",
    "Expected a source raster with independent river randomness")
  local original=raster.storage_options()
  assert(not M.is_promoted(original.base_id),"Terrain base is already promoted")
  local id=original.base_id.."/r3p1"
  assert(#id<=127,"Promoted terrain identity is too long")
  return {seed=original.seed,base_id=id,corner=original.corner,validate_tile_word=M.valid,
    tile=function(seed,x,z)
      local w=original.tile(seed,x,z)
      if w==RIVER then return M.river(raster.river_bits(x,z)) end
      return w
    end}
end
local C=M.cover
function M.skin(class,ground,mask)
  if class==7 then return C.VOID end
  if ground==2 and class==6 then return C.COAST end
  if ground==3 and class==4 then return C.COAST_TREES end
  if class==6 then
    if ground==4 then return C.LOCK end
    if ground==5 then return C.DEPOT end
    if ground==1 then return mask==0 and C.WATER_FLAT or C.WATER_GRADED end
    if ground==3 then return mask==0 and C.RIVER_FLAT or C.RIVER_GRADED end
    return C.WATER_UNRESOLVED
  end
  return mask==0 and C.LAND_FLAT or C.LAND_GRADED
end
function M.profile_bytes(mask,base,high,class,ground)
  local skin=M.skin(class,ground,mask)
  local coast=skin==C.COAST or skin==C.COAST_TREES
  return char(mask,base,high,class,skin,coast and mask%16 or 0,ground or 255)
end
function M.entry(data,i,word,x,z,version)
  local mask,base,high,class,skin,land,ground=byte(data,i,i+(version==2 and 6 or 5))
  if version==2 then
    if ground==255 then ground=nil end
    if not M.valid_descriptor(class,ground) or M.skin(class,ground,mask)~=skin then return end
  else
    if not M.valid_descriptor(class) or skin>C.WATER_UNRESOLVED then return end
  end
  local coast=skin==C.COAST or skin==C.COAST_TREES
  if version==2 and land~=(coast and mask%16 or 0) then return end
  local river=skin==C.RIVER_FLAT or skin==C.RIVER_GRADED
  local p={x=x,z=z,mask=mask,base=base,high=high,class=class,cover=skin,word=word,ground=ground,
    shore_land_mask=coast and land or nil,shore_water_mask=coast and (15-land) or nil}
  if river then
    p.water_class="river"
    p.river_flat=mask==0
    p.river_bits=M.river_bits(word)
  end
  return p
end
return M
