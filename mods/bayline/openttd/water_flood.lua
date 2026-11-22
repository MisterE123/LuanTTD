-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors: 14.1 src/water_cmd.cpp GetFloodingBehaviour,
-- _flood_from_dirs, TileLoop_Water, and ordinary clear ground branches of
-- DoFloodTile/FLOOD_DRYUP. Terrain structure replacement is host policy.
local F={}
local floor=math.floor
local flood={[0]=170,10,130,2,160,0,128,131,40,8,0,14,32,56,224}
local dx,dz={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
local raised={[1]=true,[2]=true,[4]=true,[8]=true}
local sea_facilities={station=true,industry=true,object=true}
local function has(n,d) return floor(n/2^d)%2==1 end
local function opposite(d) return (d+4)%8 end
local function directions(t)
  return flood[(t.foundation_slope or t.slope)%16] or 0
end
function F.one_raised(slope) return raised[slope]==true end
function F.offset(d) return dx[d],dz[d] end
function F.behaviour(t)
  if not t then return "none" end
  local k=t.kind
  if k=="coast" or k=="rail" and t.water_ground then return raised[t.slope] and "active" or "dryup" end
  if k=="trees" and t.water_ground then return "dryup" end
  if k=="sea" or k=="void" or sea_facilities[k] and t.water_class=="sea" then return "active" end
  return "none"
end

-- One physical landscape visit, NOT a flood fill or a worldgen conversion.
-- Board coordinates are absolute, and off-grid read is nil. A world can
-- mark stock valid/void edge cells explicitly. Stock void visits can
-- flood adjacent playable edges (see void_cmd.cpp::TileLoop_Void).
-- A stock TileIndex board can supply offset(x,z,dir) for edge addressing.
-- Board.can_clear(x,z,t) is the non-mutating ordinary-clear quote. Hosts
-- may leave protected structures intact while still recognizing them as
-- active water sources. The only committed classes here are ordinary
-- clear land, plain sea and shore. Return changes in source direction order.
function F.visit(board,x,z)
  local source=board.tile(x,z)
  local behaviour=F.behaviour(source)
  local changes={}
  local function neighbor(dir)
    if board.offset then return board.offset(x,z,dir) end
    return x+dx[dir],z+dz[dir]
  end
  if behaviour=="active" then
    for dir=0,7 do
      local u,v=neighbor(dir)
      local t=u and board.tile(u,v)
      if t and t.kind=="clear" and (t.foundation_base or t.base)==0 and has(directions(t),opposite(dir)) and
         (not board.can_clear or board.can_clear(u,v,t)) then
        changes[#changes+1]={x=u,z=v,from="clear",kind=t.slope==0 and "sea" or "coast"}
      end
    end
  elseif behaviour=="dryup" and source.kind=="coast" then
    local allowed=directions(source)
    for dir=0,7 do
      if has(allowed,dir) then
        local u,v=neighbor(dir)
        local k=F.behaviour(u and board.tile(u,v))
        if k=="active" then return changes end
      end
    end
    if not board.can_clear or board.can_clear(x,z,source) then
      changes[1]={x=x,z=z,from="coast",kind="clear"}
    end
  end
  return changes
end

-- water_cmd.cpp::ClearTile_Water, ordinary WATER_TILE_CLEAR and
-- WATER_TILE_COAST only. Explicit canal demolition differs from raising
-- land: the latter calls TerraformTile_Water before this branch.
function F.clear_water(t,opts)
  opts=opts or {}
  if not t or t.kind=="void" then return nil,"OUTSIDE_MAP" end
  if t.kind=="coast" then
    if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    return raised[t.slope] and (opts.clear_water or 10000) or (opts.clear_rough or 40)
  end
  if t.kind~="sea" and t.kind~="river" and t.kind~="canal" then return nil,"PROTECTED_TILE" end
  if opts.no_water then return nil,"CAN_T_BUILD_ON_WATER" end
  if opts.clear_allowed==false then return nil,"TOO_CLOSE_TO_EDGE_OF_MAP" end
  if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
  if t.owner and t.owner~="water" and t.owner~="none" and t.owner~=opts.owner then
    return nil,"OWNED_BY_ANOTHER"
  end
  return t.kind=="canal" and (opts.clear_canal or 5000) or (opts.clear_water or 10000)
end

function F.terraform_water(t,opts)
  if t and t.kind=="canal" then return nil,"MUST_DEMOLISH_CANAL_FIRST" end
  return F.clear_water(t,opts)
end
return F
