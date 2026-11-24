-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 rail_cmd.cpp TileLoop_Rail and
-- rail_map.h RailGroundType. Flooded rail uses a separate water tile loop.
return function(Track)
  local G={BARREN=0,GRASS=1,HALF_TILE_WATER=13}
  local masks={[0]=37,42,25,22} -- TRACK_BIT_3WAY_NE/SE/SW/NW.
  local ground={[0]=1,[1]=5,[2]=3,[4]=6,[8]=2,[5]=7,[10]=4,[3]=8,[9]=11,[6]=10,[12]=9}
  local fenced={house=true,industry=true,road=true,tunnelbridge=true}
  function G.visit(tile,neighbor)
    if tile.ground==G.HALF_TILE_WATER then return tile.ground,"water" end
    if not tile.plain or tile.ground==G.BARREN then return G.GRASS end
    local directions=0
    for d=Track.NE,Track.NW do
      if Track.intersect(tile.tracks,masks[d])==0 then
        local t=neighbor(d)
        if not t or fenced[t.kind] or (t.kind=="object" and not t.owned_land) or t.owner~=tile.owner then
          directions=directions+2^d
        end
      end
    end
    return assert(ground[directions],"Rail ground requires at least one track"),nil,directions
  end
  return G
end
