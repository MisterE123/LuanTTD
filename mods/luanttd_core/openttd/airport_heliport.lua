-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1:
-- table/airport_movement.h _airport_moving_data_heliport[9],
-- table/airport_defaults.h AS_ND(heliport), airport.cpp HELIPORT(heliport).
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local f=dofile(mod.."/openttd/airport_small.lua").flag
return dofile(mod.."/openttd/airport_heliport_fta.lua")(mod,{
  airport_type="heliport",intro_year=1963,delta_z=60,catchment_radius=4,
  points={
    [0]={5,9,f.EXACTPOS,1},
    {2,9,f.HELI_RAISE,0},
    {-3,9,f.NOSPDCLAMP+f.SLOWTURN,0},
    {-3,9,f.HELI_LOWER,0},
    {2,9,0,0},
    {-31,59,f.NOSPDCLAMP+f.SLOWTURN,0},
    {-31,-49,f.NOSPDCLAMP+f.SLOWTURN,0},
    {49,-49,f.NOSPDCLAMP+f.SLOWTURN,0},
    {70,9,f.NOSPDCLAMP+f.SLOWTURN,0},
  },
})
