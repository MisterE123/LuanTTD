-- SPDX-License-Identifier: GPL-2.0-only
-- Source-facing board adapter for rail spans. Pure, no clearing is applied.
local S={TRACKBIT_FACTOR=4}
function S.railtype(opts)
  local rt=opts.railtype or 0
  if type(rt)~="number" or rt%1~=0 or rt<0 or rt>3 then return end
  if opts.can_build_railtype then
    if not opts.can_build_railtype(rt) then return end
  elseif rt~=0 then return end
  if opts.deity then return end -- only roads have the deity exception
  return rt
end
function S.price(opts,key,base)
  return opts.prices and opts.prices[key] or base
end
function S.id(board,x,z)
  return (board.id or board.tile_at)(x,z)
end
local keys={grass={"clear_grass",20},rough={"clear_rough",40},rocks={"clear_rocks",200},
  fields={"clear_fields",500},desert={"clear_rough",40},snow={"clear_rough",40}}
local one={[1]=true,[2]=true,[4]=true,[8]=true}
function S.clear(board,id,tile,role,opts)
  if board.clear_quote then return board.clear_quote(id,tile,role,opts.owner) end
  if tile.clear_cost~=nil then return tile.clear_cost end -- explicit landscape quote
  local kind=tile.kind
  if kind=="clear" or kind=="ground" then
    local g=tile.ground or "grass"
    if g=="grass" and tile.density==0 then return 0 end
    local p=keys[g]
    if p then return S.price(opts,p[1],p[2]) end
  elseif kind=="coast" or kind=="water" and tile.coast then
    if tile.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    if one[tile.slope] then return S.price(opts,"clear_water",10000) end
    return S.price(opts,"clear_rough",40)
  elseif kind=="water" or kind=="sea" or kind=="river" or kind=="canal" then
    return nil,"CANT_BUILD_ON_WATER"
  elseif kind=="rail" or kind=="signals" or kind=="plain_rail" or kind=="shore_rail" or kind=="depot" and tile.transport~="road" then
    if tile.owner~=opts.owner then return nil,"AREA_IS_OWNED_BY_ANOTHER" end
    return nil,kind=="depot" and "BUILDING_MUST_BE_DEMOLISHED" or "MUST_REMOVE_RAILROAD_TRACK"
  elseif kind=="bridge" or kind=="aqueduct" then return nil,"MUST_DEMOLISH_BRIDGE_FIRST"
  elseif kind=="tunnel" then return nil,"MUST_DEMOLISH_TUNNEL_FIRST"
  elseif kind=="station" or kind=="waypoint" or kind=="depot" then return nil,"BUILDING_MUST_BE_DEMOLISHED" end
  return nil,"LANDSCAPE_CLEAR_REQUIRED"
end

function S.portal(portal,plan,other,kind,direction)
  portal.kind=kind;portal.transport="rail";portal.railtype=plan.railtype;portal.owner=plan.owner
  portal.other=other;portal.skip=plan.middle_length;portal.dir=direction
  portal.axis=direction%2;portal.trackbits=2^portal.axis
  return portal
end
return S
