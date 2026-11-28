-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 aircraft_cmd.cpp Aircraft::Crash,
-- HandleCrashedAircraft and HandleAircraftSmoke. Stock pixels are not
-- presentation coordinates. The authority provides the shared RNG/pool.
local A={}
local floor=math.floor
local direction_delta={[0]=-1,0,0,1}
local smoke_offsets={[0]={5,5},{6,0},{5,-5},{0,-6},{-5,-5},{-6,0},{-5,5},{0,6}}

function A.begin(v,flooded)
  assert(not v.crashed)
  v.crashed,v.stopped,v.crashed_counter=true,true,flooded and 9000 or 0
end

-- Aircraft calls this once per controller pass, not once per tick.
-- Airport and ground are testable callbacks, not world edits.
function A.pass(v,airport,ground,random,effect)
  local n=v.crashed_counter+3
  if n<500 and not airport and n%3==0 then
    local z=ground(v.x,v.z)
    v.y=v.y-1
    if v.y<=z then n,v.y=500,z+1 else n=0 end
  end
  v.crashed_counter=n
  if n<650 then
    local word=random()
    -- Chance16R(1,32), using only the low word and rounding.
    if floor((32*(word%65536)+16)/65536)<1 then
      v.direction=(v.direction+direction_delta[floor(word/65536)%4])%8
      local gust=random()
      effect("explosion_small",v.x+gust%16-4,v.y+floor(gust/256)%16,v.z+floor(gust/16)%16-4)
    end
  elseif n>=10000 then
    if airport then
      -- AirportBlock::{RunwayIn,RunwayInOut} share bit eight.
      for _,bit in ipairs({2^8,2^29}) do
        if floor(airport.flags/bit)%2==1 then airport.flags=airport.flags-bit end
      end
    end
    return false
  end
  return true
end

function A.smoke(v,effect)
  local d=assert(smoke_offsets[v.direction])
  effect("aircraft_smoke",v.x+d[1],v.y+2,v.z+d[2])
end

return A
