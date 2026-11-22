-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 table/town_land.h HouseSpec and town_cmd.cpp
-- AddAcceptedCargo_Town. Original house IDs, including subtile rows.
local A={}
local eighths={
  [0]=4,4,1,0,6,6,0,2,2,0,0,0,0,4,3,3,
  3,6,8,6,0,0,0,0,0,0,0,2,3,3,3,2,
  0,0,0,0,2,0,0,2,3,3,3,3,0,0,0,0,
  0,0,4,4,4,4,5,5,0,0,0,0,0,0,0,0,
  3,3,0,2,0,2,3,3,4,4,2,2,2,2,0,0,
  0,0,1,0,0,1,1,4,4,1,4,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,
}
function A.house_acceptance(id) return eighths[id] end
return A
