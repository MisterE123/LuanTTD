-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, table/airport_movement.h _airport_fta_heliport,
-- _airport_moving_data_oilrig, airport.cpp and aircraft_cmd.cpp.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local Rig=dofile(mod.."/openttd/oil_rig.lua")
local H=dofile(mod.."/openttd/airport_small.lua")
local S={ALL=0,HELIPAD1=8,HELITAKEOFF=13,FLYING=14,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
local B={PAD=2^6,BUSY=2^8,NOTHING=2^30}
local A={W=1,H=1,TILE=16,state=S,block=B,flag=H.flag,entries={[0]=7,7,7,7},
  airport_type="oilrig",num_helipads=1,helicopters=true,airplanes=false,delta_z=Rig.airport.delta_z,
  catchment_radius=Rig.airport.catchment,points={},block_bits={B.PAD,B.BUSY,B.NOTHING},
  terminal_bits={B.PAD},terminal_states={S.HELIPAD1}}
local flag={exact_position=16,heli_raise=64,unclamped_slow_turn=5,heli_lower=128,ground=0}
for i=0,8 do
  local p=Rig.airport.moving[i]
  A.points[i]={p[1],p[2],flag[p[3]],p[4]=="NE" and 1 or 0}
end
A.layout={
  [0]={{S.HELIPAD1,B.PAD,1}},
  {{S.HELITAKEOFF,B.NOTHING,0}},
  {{S.TERMGROUP,B.BUSY,0},{S.HELILANDING,0,3},{S.HELITAKEOFF,0,1}},
  {{S.HELILANDING,B.BUSY,4}},
  {{S.HELIENDLANDING,B.BUSY,4},{S.HELIPAD1,B.PAD,0},{S.HELITAKEOFF,0,2}},
  {{S.ALL,B.NOTHING,6}},
  {{S.ALL,B.NOTHING,7}},
  {{S.ALL,B.NOTHING,8}},
  {{S.FLYING,B.NOTHING,5},{S.HELILANDING,B.PAD,2}},
}
return dofile(mod.."/openttd/airport_fta.lua")(A)
