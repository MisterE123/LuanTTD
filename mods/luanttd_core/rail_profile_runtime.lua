-- SPDX-License-Identifier: GPL-2.0-only
-- Additional stock wagons use the same station machinery as Oil and Goods.
-- All production, packets, acceptance and receipts are shared with road.
local mod=(core and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(mod.."/rail_freight_kinds.lua")
local Service=dofile(mod.."/rail_industry_service.lua")
local Runtime=dofile(mod.."/rail_industry_runtime.lua")
return function(cargo,Sim,Rules,Catchment,Roster,FreightStation,Packets,Rating,Station,Loader,Timing,debit,credit,ready)
  local p=assert(Freight.profiles[cargo])
  local service=Service({tag=cargo:upper(),single_error="SINGLE_STOCK_"..cargo:upper().."_WAGON_REQUIRED",
    wagon=assert(Roster.entry(p.wagon))},Sim,Rules,Catchment,Roster,FreightStation,Packets,Rating,Station,Loader,Timing)
  return Runtime({cargo=cargo,name="Rail "..p.name,block="block_"..cargo,
    enabled=function(s) return ready(s,cargo) and Sim["road_"..p.system.."_active"](s) end,
    distinct_industries=p.distinct_industries,
    choose_source="Choose a platform in a working "..p.source.."'s catchment.",
    choose_sink="Choose a platform accepting "..p.name.." at a "..p.sink..".",
    source_lost="The ordered "..p.source.." has closed or moved out of catchment.",
    sink_lost="The ordered "..p.sink.." no longer accepts "..p.name.." in catchment."},
    Sim,service,FreightStation,Roster,debit,credit)
end
