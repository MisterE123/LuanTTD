-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 rail_gui.cpp GenericPlaceSignals.
-- Select a physical track from 0..15 tile fractions. The stock command
-- rejects a selected half that is not actually present.
return function(Track)
  return function(bits,x,y)
    local track
    if x~=nil and y~=nil then
      if Track.intersect(bits,48)~=0 then track=x<=y and Track.RIGHT or Track.LEFT end
      if Track.intersect(bits,12)~=0 then track=x+y<=15 and Track.UPPER or Track.LOWER end
    end
    if track~=nil then return track end
    for i=0,5 do if Track.has(bits,i) then return i end end
  end
end
