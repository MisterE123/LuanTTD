-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. OpenTTD 14.1 table/airport_movement.h,
-- airport.h/airport.cpp and aircraft_cmd.cpp fixed-wing handlers.
-- Country Airfield AT_SMALL; movement and permission callbacks are external.
local A={W=4,H=3,TILE=16,short_strip=true,hangar={x=3,z=0,dir=3,id=0},entries={[0]=16,15,18,17}}
local S={ALL=0,HANGAR=1,TERM1=2,TERM2=3,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
local B={TERM1=1,TERM2=2,BUSY=256,NOTHING=2^30}
local F={NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}
A.state,A.block,A.flag=S,B,F
A.points={
  [0]={53,3,16,3},{53,27,0,0},{32,23,16,7},{10,23,16,7},{43,37,0,0},{24,37,0,0},
  {53,37,0,0},{61,40,16,1},{3,40,1,0},{-79,40,3,0},{177,40,5,0},{56,40,9,0},
  {3,40,33,0},{7,40,0,0},{53,40,0,0},{1,193,5,0},{1,1,5,0},{257,1,5,0},
  {273,47,5,0},{44,37,64,0},{44,40,5,0},{44,40,128,0},
}
A.layout={
  [0]={{S.HANGAR,B.NOTHING,1}},
  {{S.TERMGROUP,B.BUSY,0},{S.HANGAR,0,0},{S.TERM1,B.TERM1,2},{S.TERM2,0,4},{S.HELITAKEOFF,0,19},{S.ALL,0,6}},
  {{S.TERM1,B.TERM1,1}},
  {{S.TERM2,B.TERM2,5}},
  {{S.TERMGROUP,B.BUSY,0},{S.TERM2,0,5},{S.HANGAR,0,1},{S.TAKEOFF,0,6},{S.HELITAKEOFF,0,1}},
  {{S.TERMGROUP,B.BUSY,0},{S.TERM2,B.TERM2,3},{S.ALL,0,4}},
  {{S.ALL,B.BUSY,7}},
  {{S.TAKEOFF,B.BUSY,8}},
  {{S.STARTTAKEOFF,B.NOTHING,9}},
  {{S.ENDTAKEOFF,B.NOTHING,0}},
  {{S.FLYING,B.NOTHING,15},{S.LANDING,0,11},{S.HELILANDING,0,20}},
  {{S.LANDING,B.BUSY,12}},
  {{S.ALL,B.BUSY,13}},
  {{S.ENDLANDING,B.BUSY,14},{S.TERM2,0,5},{S.ALL,0,14}},
  {{S.ALL,B.BUSY,1}},
  {{S.ALL,B.NOTHING,16}},
  {{S.ALL,B.NOTHING,17}},
  {{S.ALL,B.NOTHING,18}},
  {{S.ALL,B.NOTHING,10}},
  {{S.HELITAKEOFF,B.NOTHING,0}},
  {{S.HELILANDING,B.BUSY,21}},
  {{S.HELIENDLANDING,B.BUSY,1}},
}

A.terminal_bits,A.terminal_states={B.TERM1,B.TERM2},{S.TERM1,S.TERM2}
A.block_bits={B.TERM1,B.TERM2,B.BUSY,B.NOTHING}
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
return dofile(mod.."/openttd/airport_fta.lua")(A)
