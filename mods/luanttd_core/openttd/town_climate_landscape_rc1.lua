-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 src/landscape.cpp:
-- CalculateCoverageLine, CalculateSnowLine, CalculateDesertLine and
-- CreateDesertOrRainForest; src/table/genland.h for the neighbourhood.
-- src/clear_cmd.cpp: NeighbourIsNormal, TileLoopClearDesert,
-- and TileLoopClearAlps; water_cmd.cpp MakeRiverAndModifyDesertZoneAround.
local source=debug and debug.getinfo(1,"S").source
local path=(source and source:match("^@(.*/)")) or
  (core and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Spiral=dofile(path.."spiral_tile_rc1.lua")
local C={MAX_HEIGHT=255,NORMAL=0,DESERT=1,RAINFOREST=2,
  DEFAULT_SNOW_COVERAGE=40,DEFAULT_DESERT_COVERAGE=50}
local abs,floor,max=math.abs,math.floor,math.max
local cardinal={{-1,0},{0,1},{1,0},{0,-1}}

-- Board coordinates here are zero-based stock tile coordinates.
-- height returns TileHeight, not GetTileZ (minimum corner elevation).
-- The histogram includes the edge row/column even if its tiles are void;
-- only lower-neighbour scoring excludes invalid tiles.
function C.coverage_line(board,coverage,edge_multiplier)
  local hcount,edges={},{}
  local w,d,height,valid=board.width,board.depth,board.height,board.valid
  for z=0,d-1 do for x=0,w-1 do
    local h=height(x,z)
    hcount[h]=(hcount[h] or 0)+1
    if edge_multiplier~=0 then
      for _,v in ipairs(cardinal) do
        local nx,nz=x+v[1],z+v[2]
        if nx>=0 and nx<w and nz>=0 and nz<d and valid(nx,nz) and height(nx,nz)<h then
          edges[h]=(edges[h] or 0)+1
        end
      end
    end
  end end
  local land=w*d-(hcount[0] or 0)
  local best_score,best_h=land,C.MAX_HEIGHT
  local goal=floor(land*coverage/100)
  local current=0
  for h=C.MAX_HEIGHT,1,-1 do
    current=current+(hcount[h] or 0)
    local score=goal-current
    if edge_multiplier~=0 and h>1 then
      score=score-((edges[1] or 0)+(edges[h] or 0))*edge_multiplier
    end
    if abs(score)<abs(best_score) then best_score,best_h=score,h end
  end
  return best_h
end

function C.snow_line(board,snow_coverage)
  return max(C.coverage_line(board,snow_coverage or C.DEFAULT_SNOW_COVERAGE,0),2)
end
function C.desert_line(board,desert_coverage)
  return C.coverage_line(board,100-(desert_coverage or C.DEFAULT_DESERT_COVERAGE),4)
end

-- The exact source neighbourhood is the union of these rectangles:
-- ±5x±5, ±6x±3 and ±3x±6. A rolling sum makes the all-of test
-- linear in map size. Intersections may be counted more than once
-- because only zero vs nonzero is used. Writes still use tile order.
-- Reject predicate inputs (height, water, clear ground) do not change
-- when a zone label is written during either pass.
local radius={5,3,6}
local halfwidth={5,6,3}
local byte=string.byte
local function pass(board,reject,target)
  local w,d,valid=board.width,board.depth,board.valid
  local rows,buffer,columns={},{},{{},{},{}}
  local function input_row(z)
    if z<0 or z>=d then return end
    if not rows[z] then
      -- Keep in-bounds void coordinates in the rejection test, but
      -- do not count positions outside the raw map raster.
      for x=0,w-1 do buffer[x+1]=reject(x,z) and "\1" or "\0" end
      rows[z]=table.concat(buffer)
    end
    return rows[z]
  end
  local function apply(col,data,sign)
    if data then for x=1,w do col[x]=(col[x] or 0)+sign*byte(data,x) end end
  end
  for k,r in ipairs(radius) do
    for z=0,r do apply(columns[k],input_row(z),1) end
  end
  for z=0,d-1 do
    local totals={}
    for k,half in ipairs(halfwidth) do
      local sum,col=0,columns[k]
      for x=1,half+1 do sum=sum+(col[x] or 0) end
      totals[k]=sum
    end
    for x=1,w do
      if totals[1]+totals[2]+totals[3]==0 and valid(x-1,z) then
        board.set_zone(x-1,z,target)
      end
      for k,half in ipairs(halfwidth) do
        local col=columns[k]
        totals[k]=totals[k]+(col[x+half+1] or 0)-(col[x-half] or 0)
      end
    end
    for k,r in ipairs(radius) do
      local col=columns[k]
      apply(col,input_row(z-r),-1)
      apply(col,input_row(z+r+1),1)
    end
    rows[z-6]=nil
  end
end

-- Ground and density are the native clear-tile fields, not the zone.
-- Supply normal_neighbor lazily: stock checks it only in the desert zone.
function C.clear_desert(ground,density,zone,normal_neighbor)
  local current=(ground=="desert" or ground=="rocks") and density or 0
  local expected=zone==C.DESERT and (normal_neighbor() and 1 or 3) or 0
  if current==expected then return end
  if ground=="rocks" then return "rocks",expected end
  if expected==0 then return "grass",3 end
  return "desert",expected
end

-- Stock NeighbourIsNormal reads linear diagonal offsets, not the
-- bounded x/z offsets of the classification passes above.
function C.normal_neighbor(width,tile,valid,is_desert,is_sea)
  for i=1,4 do
    local n=tile+(i==1 and -1 or i==2 and width or i==3 and 1 or -width)
    if valid(n) and (not is_desert(n) or is_sea(n)) then return true end
  end
  return false
end

-- Operation chosen by TileLoopClearAlps. Snow density is a separate
-- storage field from the underlying ground; let the adapter preserve it.
-- This uses GetTileZ (minimum corner height), unlike the town growth gate.
function C.clear_snow(min_z,snowline,is_snow,current_density)
  local k=min_z-snowline+1
  if not is_snow then
    if k>=0 then return "make",0 end
    return
  end
  local required=k<0 and 0 or math.min(k,3)
  if current_density==required then
    if k<0 then return "clear" end
  else
    return "density",current_density+(current_density<required and 1 or -1)
  end
end

-- Stock runs its real clear-land tile loop between these two passes.
-- The host must supply that phase, rather than infer desert ground from
-- the desert zone label. Physical water and clear ground are separate.
function C.classify_tropic(board,desert_tropic_line,advance_landscape)
  pass(board,function(x,z)
    return board.height(x,z)>=desert_tropic_line or board.is_water(x,z)
  end,C.DESERT)
  for _=1,256 do advance_landscape() end
  pass(board,board.is_clear_desert,C.RAINFOREST)
end

-- Called once for a new river tile, in the source command's order.
-- Do not remove rainforest or roll a random number per affected tile.
function C.clear_river_zone(board,tile)
  local w,d=board.width,board.depth
  for n in Spiral.centered(w,d,tile,5) do
    local x,z=n%w,floor(n/w)
    if board.zone(x,z)==C.DESERT then board.set_zone(x,z,C.NORMAL) end
  end
end
function C.river_tile(board,tile,random,make_river,dirty)
  make_river(tile,random())
  dirty(tile)
  C.clear_river_zone(board,tile)
end

-- This callback is evaluated on demand by the growth scheduler. A
-- terrain adapter can translate host coordinates before delegating here.
function C.town_lookup(board,snowline)
  return function(x,z)
    return {tile_height=board.height(x,z),snowline=snowline(),
      is_desert=board.zone(x,z)==C.DESERT}
  end
end

return C
