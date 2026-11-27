-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 town_cmd.cpp TownGenerateCargo,
-- town.h SuppliedHistory, station_cmd.cpp MoveGoodsToStation, and
-- economy.cpp DeliverGoods with the effects in table/cargo_const.h.
local M={}
local UINT16,UINT32=65536,4294967296
local effect_by_stock_cargo={passenger=1,mail=2,goods=3,water=4,food=5}

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
  -- Town's Uint32 supplied history multiplies in Uint32; the industry
  -- variant has Uint16 inputs and promotes them before multiplication.
  return generated==0 and 0 or math.min(255,math.floor(((moved*256)%UINT32)/generated))
end

-- Total accepted cargo contributes to the station's associated town
-- effect, including any units consumed by industries. Only the portion
-- remaining with the town is part of its per-cargo accepted history.
function M.accept(s,town_id,cargo,total,town_units)
  local by_town=s.stock_town_growth and s.stock_town_growth.towns
  local town=by_town and by_town[town_id]
  if not town or total==0 then return end
  assert(total>0 and town_units>=0 and town_units<=total)
  local effect=effect_by_stock_cargo[cargo] or 0
  local r=town.received[effect]
  if not r then r={};town.received[effect]=r end
  r.new_act=((r.new_act or 0)+total)%UINT16
  if town_units>0 then
    town.accepted=town.accepted or {}
    local a=town.accepted[cargo]
    if not a then a={};town.accepted[cargo]=a end
    a.new_act=((a.new_act or 0)+town_units)%UINT32
  end
end

return M
