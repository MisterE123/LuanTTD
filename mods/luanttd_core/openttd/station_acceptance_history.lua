-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, RC1 economy.cpp DeliverGoods and station_cmd.cpp
-- StationHandleBigTick / the monthly Station economy timer.
local M={}
function M.record(goods)
  goods.ever_accepted,goods.current_month,goods.accepted_bigtick=true,true,true
end
function M.big_tick(goods) goods.accepted_bigtick=nil end
function M.month(goods)
  goods.last_month=goods.current_month or nil
  goods.current_month=nil
end

-- Adapters have separate transport catalogs and sometimes share a
-- GoodsEntry table. Month rotation is for the underlying entry once,
-- not the number of station windows or modes referencing its receipt.
function M.rotate_host(s,freight_kinds)
  local seen={}
  local function rotate(goods)
    if goods and not seen[goods] then seen[goods]=true;M.month(goods) end
  end
  local function station(st)
    rotate(st.passenger_rating_state)
    rotate(st.mail_rating_state)
    for _,goods in pairs(st.goods or {}) do
      if type(goods)=="table" then rotate(goods) end
    end
  end
  local function stations(list)
    for _,st in pairs(list or {}) do station(st) end
  end
  stations(s.stations)
  for _,entry in pairs(s.retired_road_stations or {}) do station(entry.row) end
  for _,entry in pairs(s.retired_ship_stations or {}) do station(entry.row) end
  local commercial=s.stock_ship_commercial and s.stock_ship_commercial.service
  if commercial then stations(commercial.stations) end
  for _,name in ipairs({"stock_ship_coal","stock_oil_ship_service","stock_goods_ship_service"}) do
    local state=s[name]
    if state then stations(state.stations) end
  end
  for _,kind in ipairs(freight_kinds) do
    local ledger=s["stock_rail_"..kind]
    if ledger then stations(ledger.stations) end
  end
end
return M
