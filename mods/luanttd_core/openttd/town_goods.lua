-- SPDX-License-Identifier: GPL-2.0-only
-- Stock Temperate goods acceptance. The shared RC1 table also covers
-- the other climate cargo labels and multi-tile child HouseIDs.
local here=debug and debug.getinfo(1,"S").source:match("^@(.*/)")
local path=here or (core and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
return {house_acceptance=dofile(path.."town_house_acceptance_rc1.lua").goods}
