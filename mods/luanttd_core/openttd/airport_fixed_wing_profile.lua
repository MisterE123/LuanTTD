-- SPDX-License-Identifier: GPL-2.0-only
-- Stock fixed-wing FTA profile assembly.
local state={ALL=0,HANGAR=1,TERM1=2,TERM2=3,TERM3=4,TERM4=5,TERM5=6,TERM6=7,HELIPAD1=8,HELIPAD2=9,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERM7=19,TERM8=20,HELIPAD3=21,TERMGROUP=255}
local block={TERM1=1,TERM2=2,TERM3=4,RUNWAY_IN=256,RUNWAY_OUT=512,TAXIWAY=1024,OUT=2048,IN=4096,NOTHING=2^30}
local flag={NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}

return function(data,path)
  local hangar=data.hangars[1]
  assert(#data.hangars==1,"multiple source hangars require a departure selection adapter")
  data.TILE,data.hangar=16,{x=hangar[1],z=hangar[2],dir=hangar[3],id=hangar[4]}
  data.catchment_radius=data.catchment
  data.state,data.block,data.flag=state,block,flag
  data.terminal_bits,data.terminal_states={},{}
  local terminal={1,2,3,4,5,6,7,8}
  for i=1,data.num_helipads do terminal[#terminal+1]=8+i end
  for _,i in ipairs(terminal) do
    local pair=data.terminal_mapping[i]
    data.terminal_states[#data.terminal_states+1]=pair[1]
    data.terminal_bits[#data.terminal_bits+1]=pair[2]
  end
  data.block_bits={}
  local seen={}
  for _,row in pairs(data.layout) do
    for _,transition in ipairs(row) do
      for b=0,31 do
        local mask=2^b
        if not seen[mask] and math.floor(transition[2]/mask)%2==1 then
          seen[mask]=true;data.block_bits[#data.block_bits+1]=mask
        end
      end
    end
  end
  table.sort(data.block_bits)
  local policy=dofile(path.."airport_terminal_policy.lua")(data)
  data.reserve_terminal,data.reserve_helipad=policy.terminal,policy.helipad
  return dofile(path.."airport_fta.lua")(data)
end
