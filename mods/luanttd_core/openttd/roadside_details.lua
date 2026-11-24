-- SPDX-License-Identifier: GPL-2.0-only
-- 16.0-RC1 OpenTTD contributors, table/road_land.h.
-- Subcoordinates are the stock (0..15) tile positions; inverse lamps
-- face the road from the other side. No source sprites are included.
local D={}
D.street_lights={
  [3]={{1,8,0}},
  [5]={{1,8,0},{14,8,1}},
  [6]={{8,1,1}},
  [7]={{1,8,0}},
  [9]={{8,14,0}},
  [10]={{8,14,0},{8,1,1}},
  [11]={{8,14,0}},
  [12]={{8,1,1}},
  [13]={{14,8,1}},
  [14]={{8,1,1}},
}
D.trees={
  [3]={{0,2,0},{3,9,0},{10,12,0}},
  [5]={{0,2,0},{0,10,0},{12,2,0},{12,10,0}},
  [6]={{10,0,0},{3,3,0},{0,10,0}},
  [7]={{0,2,0},{0,10,0}},
  [9]={{12,2,0},{9,9,0},{2,12,0}},
  [10]={{2,0,0},{10,0,0},{2,12,0},{10,12,0}},
  [11]={{2,12,0},{10,12,0}},
  [12]={{2,0,0},{9,3,0},{12,10,0}},
  [13]={{12,2,0},{12,10,0}},
  [14]={{2,0,0},{10,0,0}},
}
function D.points(state,road_bits,all_bits,work,base_max,bridge_deck)
  local p=D[state] and D[state][all_bits]
  if work or not p or road_bits==0 or road_bits==1 or road_bits==2 or road_bits==4 or road_bits==8 then return end
  if bridge_deck and bridge_deck<base_max+(state=="trees" and 3 or 2) then return end
  return p
end
return D
