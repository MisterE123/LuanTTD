-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 elrail.cpp::MaskWireBits. Missing neighbours mark
-- individual directions, not whole pieces, before the ordered fallbacks.
return function(Track)
  local M={}
  local function disable_both(dir)
    return Track.intersect(dir%64,math.floor(dir/256)%64)
  end
  function M.select(tracks,missing,plain)
    if not plain or tracks==0 or not Track.tracks_overlap(tracks) and tracks~=12 and tracks~=48 then return tracks end
    local mask
    local one=Track.trackbits(missing)
    if tracks==3 or not Track.tracks_overlap(tracks) then
      mask=63-disable_both(missing)
      if tracks~=3 and mask==63 then mask=63-one end
    else
      mask=63-one
      if Track.intersect(tracks,mask)==0 then
        if not Track.has(missing,0) or not Track.has(missing,8) then mask=Track.union(mask,1) end
        if not Track.has(missing,1) or not Track.has(missing,9) then mask=Track.union(mask,2) end
        if Track.intersect(tracks,mask)==0 then mask=63-disable_both(missing) end
      end
    end
    local kept=Track.intersect(tracks,mask)
    return kept~=0 and kept or tracks
  end
  function M.at(board,id,tracks,plain)
    if not plain then return tracks end
    local missing=0
    for d=0,3 do
      local t=board.rail(board.adjacent(id,d))
      local reaches=Track.trackbits(Track.reachable(d))
      if not t or not t.catenary or
          (Track.intersect(t.trackbits or 0,reaches)==0 and not (t.station_wires and t.axis==d%2)) then
        missing=Track.union(missing,Track.reachable(Track.reverse_side(d)))
      end
    end
    return M.select(tracks,missing,true)
  end
  return M
end
