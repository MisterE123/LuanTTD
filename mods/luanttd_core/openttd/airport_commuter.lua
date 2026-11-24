-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Exact Commuter 16.0-RC1 board.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local path=mod.."/openttd/"
local data=dofile(path.."airport_expansion_data.lua").commuter
return dofile(path.."airport_fixed_wing_profile.lua")(data,path)
