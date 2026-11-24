-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Exact 16.0-RC1 Metropolitan moving, block and source
-- tile tables. Not exposed to the game until facility and art are integrated.
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local path=mod.."/openttd/"
local data=dofile(path.."airport_expansion_data.lua").metropolitan
local state={ALL=0,HANGAR=1,TERM1=2,TERM2=3,TERM3=4,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
local block={TERM1=1,TERM2=2,TERM3=4,RUNWAY_IN=256,RUNWAY_OUT=512,TAXIWAY=1024,OUT=2048,IN=4096,NOTHING=2^30}
local flag={NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}
local hangar=data.hangars[1]
data.TILE,data.hangar=16,{x=hangar[1],z=hangar[2],dir=hangar[3],id=hangar[4]}
data.catchment_radius=data.catchment
data.state,data.block,data.flag=state,block,flag
data.terminal_bits,data.terminal_states={block.TERM1,block.TERM2,block.TERM3},{state.TERM1,state.TERM2,state.TERM3}
data.block_bits={1,2,4,256,512,1024,2048,4096,2^30}
local policy=dofile(path.."airport_terminal_policy.lua")(data)
data.reserve_terminal,data.reserve_helipad=policy.terminal,policy.helipad
return dofile(path.."airport_fta.lua")(data)
