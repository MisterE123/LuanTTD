-- SPDX-License-Identifier: GPL-2.0-only
-- Dry hull's default cargo uses the same translated loading pass and
-- industry station receipts as tankers. It cannot use a neutral Oil Rig.
local root=(core and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local build=dofile(root.."/ship_oil_service.lua")
return function(Sim,Roster,Packets,Rating,LoadingFactory,Timing)
  return build(Sim,Roster,Packets,Rating,LoadingFactory,Timing,{
    cargo=assert(Roster.cargo_key(Roster.default_cargo)),
    station_base=0x14000,tag="GOODS_SHIP",
    running_fixed=function(id,ticks,price) return Roster.running_fixed(ticks,price,id) end,
  })
end
