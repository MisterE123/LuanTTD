-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, pinned 14.1 src/tree_cmd.cpp GenerateTrees,
-- PlaceTreeGroups, PlaceTreesRandomly, PlaceTreeAtSameHeight, PlaceTree,
-- PlantTreesOnTile and CanPlantTreesOnTile; src/tree_map.h, src/map.cpp and
-- src/map_func.h. Temperate normal-game world generation only.
-- See COPYING.OpenTTD.md; no original tree graphics are included.
local T={}
local floor,ceil,min,abs=math.floor,math.ceil,math.min,math.abs
local MP_CLEAR,MP_WATER=0,6
local GRASS,ROUGH,ROCKS,FIELDS,SNOW,DESERT=0,1,2,3,4,5
local TREE_GRASS,TREE_ROUGH,TREE_SNOW_DESERT,TREE_SHORE,TREE_ROUGH_SNOW=0,1,2,3,4
local NONE,ORIGINAL,IMPROVED=0,1,2
local DEFAULT_TREE_STEPS=1000
local one_raised={[1]=true,[2]=true,[4]=true,[8]=true}
T.placer={none=NONE,original=ORIGINAL,improved=IMPROVED}
T.ground={grass=TREE_GRASS,rough=TREE_ROUGH,snow_desert=TREE_SNOW_DESERT,
  shore=TREE_SHORE,rough_snow=TREE_ROUGH_SNOW}
T.tile_class=4
local sizes={}
for i=6,12 do sizes[2^i]=true end
local function int(v,a,b)
  return type(v)=="number" and v>=a and v<=b and v==floor(v)
end
local function bits(r,start,n) return floor(r/2^start)%2^n end

-- Source CanPlantTreesOnTile; world generation passes allow_desert=true.
function T.can_plant(t,allow_desert)
  if not t or t.bridge_above then return false end
  if t.class==MP_WATER then return t.coast==true and int(t.slope,0,30) and not one_raised[t.slope] end
  if t.class~=MP_CLEAR then return false end
  local g=t.ground or GRASS
  return g~=FIELDS and (t.raw_ground or g)~=ROCKS and (allow_desert or g~=DESERT)
end

-- An adapter-friendly, lossless packed representation of source tree fields:
-- bits 0..3 type, 4..5 count-minus-one, 6..8 growth, 9..11 ground,
-- 12..13 density. type 0 and code 0 are valid tree values.
local function encode(r,t)
  local kind=floor(bits(r,24,8)*12/256) -- TREE_COUNT_TEMPERATE
  local number=bits(r,22,2)
  local growth=min(bits(r,16,3),6)
  local ground,density
  if t.class==MP_WATER then
    ground,density=TREE_SHORE,3
  else
    local g=t.ground or GRASS
    density=g==ROUGH and 3 or (t.density or 3)
    if g==GRASS then ground=TREE_GRASS
    elseif g==ROUGH then ground=TREE_ROUGH
    elseif g==SNOW and t.raw_ground==ROUGH then ground=TREE_ROUGH_SNOW
    else ground=TREE_SNOW_DESERT end
    if ground==TREE_GRASS or ground==TREE_ROUGH then
      -- PlaceTree rerandomizes ordinary grass/rough even if source ground
      -- was known; PlantTreesOnTile keeps shore/snow density and substrate.
      ground,density=bits(r,28,1),3
    end
  end
  return kind+16*number+64*growth+512*ground+4096*density,number+1
end
function T.decode(packed)
  if packed==nil then return nil end
  local ground=bits(packed,9,3)
  return {class=T.tile_class,type=bits(packed,0,4),count=bits(packed,4,2)+1,
    growth=bits(packed,6,3),ground=ground,density=bits(packed,12,2),
    water_class=ground==TREE_SHORE and "sea" or nil}
end

function T.generate(board,start,next_random,opts)
  assert(type(board)=="table" and sizes[board.width] and sizes[board.depth]
    and type(board.tile)=="function","Expected a typed stock map (power-of-two axes 64–4096)")
  assert(type(start)=="table" and int(start[1],0,4294967295)
    and int(start[2],0,4294967295) and type(next_random)=="function","Expected explicit stock RNG state and advance")
  opts=opts or {}
  local mode=opts.tree_placer==nil and IMPROVED or opts.tree_placer
  assert(int(mode,0,2),"Invalid OpenTTD tree placer")
  assert(opts.landscape==nil or opts.landscape=="temperate","Only temperate forest generation is supported")
  assert(not opts.editor,"Editor-only forest placement is not supported")
  assert(board.freeform==nil or type(board.freeform)=="boolean","Invalid freeform edge flag")
  local w,h=board.width,board.depth
  local free=board.freeform~=false
  local area=w*h
  local state={start[1],start[2]}
  local S={groups=0,group_attempts=0,base_attempts=0,same_height_attempts=0,
    random_draws=0,tiles=0,total_trees=0,shore_tiles=0,tree_placer=mode}
  local function random()
    S.random_draws=S.random_draws+1
    return next_random(state)
  end
  local function xy(i) return i%w+1,floor(i/w)+1 end
  local packed,order={},{}
  local function available(i)
    if packed[i]~=nil then return nil end -- Actual MP_TREES written by an earlier stock attempt.
    local x,z=xy(i)
    local t=board.tile(x,z)
    return T.can_plant(t,true) and t or nil
  end
  local function place(i,r,t)
    local word,count=encode(r,t)
    packed[i]=word
    order[#order+1]=i
    S.tiles=S.tiles+1
    S.total_trees=S.total_trees+count
    if t.class==MP_WATER then S.shore_tiles=S.shore_tiles+1 end
  end
  local function offset(x,z,dx,dz)
    x,z=x+dx,z+dz
    -- TileAddWrap excludes far border and, if freeform, also the near border.
    local lo=free and 2 or 1
    if x>=lo and z>=lo and x<w and z<h then return (z-1)*w+x-1 end
  end
  local function random_offset(r) return r%32-16,bits(r,8,5)-16 end
  local function scale(n) return ceil(n*area/65536) end
  local function height(t)
    assert(int(t.height,0,255),"Improved tree placer requires the minimum of all four tile corners (GetTileZ)")
    return t.height
  end
  local function near_height(x,z,v)
    for _=1,DEFAULT_TREE_STEPS do
      S.same_height_attempts=S.same_height_attempts+1
      local r=random()
      local dx,dz=random_offset(r)
      local i=offset(x,z,dx,dz)
      if i and abs(dx)+abs(dz)<=16 then
        local t=available(i)
        if t and abs(height(t)-v)<=2 then
          place(i,r,t)
          return
        end
      end
    end
  end

  if mode~=NONE then
    S.groups=scale(random()%32+25)
    for _=1,S.groups do
      local x,z=xy(random()%area)
      for _=1,DEFAULT_TREE_STEPS do
        S.group_attempts=S.group_attempts+1
        local r=random()
        local dx,dz=random_offset(r)
        local i=offset(x,z,dx,dz)
        if i and abs(dx)+abs(dz)<=13 then
          local t=available(i)
          if t then place(i,r,t) end
        end
      end
    end
    local passes=mode==ORIGINAL and 6 or 2
    for _=1,passes do
      for _=1,scale(DEFAULT_TREE_STEPS) do
        S.base_attempts=S.base_attempts+1
        local r=random()
        local i=r%area
        local t=available(i)
        if t then
          place(i,r,t)
          if mode==IMPROVED then
            local x,z=xy(i)
            local v=height(t)
            for _=1,v*2 do near_height(x,z,v) end
          end
        end
      end
    end
  end
  local V={width=w,depth=h,rng_after=state,stats=S}
  function V.encoded(x,z)
    if int(x,1,w) and int(z,1,h) then return packed[(z-1)*w+x-1] end
  end
  function V.tree(x,z) return T.decode(V.encoded(x,z)) end
  function V.each(visitor)
    for _,i in ipairs(order) do
      local x,z=xy(i)
      visitor(x,z,T.decode(packed[i]))
    end
  end
  return V
end
return T
