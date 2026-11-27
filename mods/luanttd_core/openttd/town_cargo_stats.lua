-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 town_cmd.cpp TownGenerateCargo,
-- town.h SuppliedHistory and station_cmd.cpp MoveGoodsToStation.
local M={}
local UINT32=4294967296

function M.supply(s,source,cargo,production,transported)
  if source.source_type and source.source_type~="town" then return end
  local by_town=s.stock_town_growth and s.stock_town_growth.towns
  local town=by_town and by_town[source.source or source.town]
  if not town or production==0 and transported==0 then return end
  local r=town.supplied[cargo]
  if not r then r={};town.supplied[cargo]=r end
  if production~=0 then r.new_max=((r.new_max or 0)+production)%UINT32 end
  if transported~=0 then r.new_act=((r.new_act or 0)+transported)%UINT32 end
end

function M.last_month(town,cargo)
  local r=town.supplied[cargo]
  return r and r.old_max or 0,r and r.old_act or 0
end

function M.last_month_percent(town,cargo)
  local generated,moved=M.last_month(town,cargo)
  return generated==0 and 0 or math.min(255,math.floor(moved*256/generated))
end

return M
