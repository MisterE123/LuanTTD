-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1.
-- table/airport_movement.h: _airport_fta_heliport is shared by the
-- ordinary Heliport and the oil rig, with distinct movement coordinates.
return function(mod,options)
  local S={ALL=0,HELIPAD1=8,HELITAKEOFF=13,FLYING=14,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
  local B={PAD=2^6,BUSY=2^8,NOTHING=2^30}
  local H=dofile(mod.."/openttd/airport_small.lua")
  local A={W=1,H=1,TILE=16,state=S,block=B,flag=H.flag,entries={[0]=7,7,7,7},
    airport_type=options.airport_type,intro_year=options.intro_year,
    num_helipads=1,helicopters=true,airplanes=false,delta_z=options.delta_z,
    catchment_radius=options.catchment_radius,points=options.points,
    block_bits={B.PAD,B.BUSY,B.NOTHING},terminal_bits={B.PAD},terminal_states={S.HELIPAD1}}
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
end
