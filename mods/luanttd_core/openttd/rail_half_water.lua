-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 rail_cmd.cpp FloodHalftile and
-- GetTileTrackStatus_Rail, plus water_cmd.cpp DoDryUp.
-- Terrain tests the upstream flood directions before calling this module.
-- The owner must perform an actual permitted removal (cannot cut a reserved
-- piece from under a train) and own all topology/vehicle/ledger effects.
return function(Track,Slope)
  local W={HALF_TILE_WATER=13}
  -- CornerToTrackBits(OppositeCorner(GetHighestSlopeCorner(tileh))).
  local lower={[1]=32,[2]=4,[4]=16,[8]=8}
  local upper={[1]=16,[2]=8,[4]=32,[8]=4}
  local dry_fence={[4]=10,[8]=11,[16]=8,[32]=9}
  local three={[7]=true,[11]=true,[13]=true,[14]=true}
  function W.flood(shape,bits,ground,remove)
    if ground==W.HALF_TILE_WATER then return end
    local flooded,removed=false,nil
    if lower[shape] then
      local bit=Track.intersect(bits,lower[shape])
      if bit~=0 then
        if not remove(bit) then return end
        flooded,removed=true,bit
        bits=Track.remove(bits,bit)
        if bits==0 then return {kind="coast",removed=removed} end
      end
      local f=Track.foundation(shape,bits)
      if f=="half" or f=="steep_both" then
        return {kind="rail",tracks=bits,ground=W.HALF_TILE_WATER,removed=removed}
      end
    else
      local f,corner=Track.foundation(shape,bits)
      -- The source mutates tileh by reference before testing steeper corners.
      local adjusted,rise=Slope.foundation(shape,f,corner)
      if rise==0 and (adjusted%32>=16 or three[adjusted]) then return {kind="rail",tracks=bits,ground=W.HALF_TILE_WATER} end
    end
    if flooded then return {kind="rail",tracks=bits,ground=ground,removed=removed} end
  end
  -- Only a wet lower single-corner half carries ships. Steep and
  -- three-corner foundations remain shore/dry-out state, not ship lanes.
  function W.water_tracks(shape,bits,ground)
    if ground==W.HALF_TILE_WATER and upper[shape] and bits==upper[shape] then return lower[shape] end
    return 0
  end
  function W.dry_ground(bits)
    return assert(dry_fence[bits],"Flooded shore rail must have exactly one curved piece")
  end
  return W
end
