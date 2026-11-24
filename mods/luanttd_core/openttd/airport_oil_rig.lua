-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 (movement points in oil_rig.lua).
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local Rig=dofile(mod.."/openttd/oil_rig.lua")
local flag={exact_position=16,heli_raise=64,unclamped_slow_turn=5,heli_lower=128,ground=0}
local points={}
for i=0,8 do
  local p=Rig.airport.moving[i]
  points[i]={p[1],p[2],flag[p[3]],p[4]=="NE" and 1 or 0}
end
return dofile(mod.."/openttd/airport_heliport_fta.lua")(mod,{
  airport_type="oilrig",delta_z=Rig.airport.delta_z,
  catchment_radius=Rig.airport.catchment,points=points,
})
