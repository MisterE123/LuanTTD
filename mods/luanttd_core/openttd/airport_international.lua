-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Exact International 16.0-RC1 board.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local next_=mod.."/openttd/"
local data=dofile(next_.."airport_expansion_data.lua").international
return dofile(next_.."airport_fixed_wing_profile.lua")(data,next_)
