-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 newgrf_engine.cpp DoTriggerVehicleRandomisation,
-- vehicle_type.h VehicleRandomTrigger. Vanilla engines have no
-- rerandomisation resolver: they still draw once per triggered body
-- and preserve waiting bits, but no sprite bits are reseeded.
local V={}
local mask={new_cargo=1,depot=2,empty=4,any_new_cargo=8,callback32=16}
local floor=math.floor

local function body(part,trigger,random)
  local bit=assert(mask[trigger])
  local pending=part.stock_waiting_random_triggers or 0
  if floor(pending/bit)%2==0 then pending=pending+bit end
  part.stock_waiting_random_triggers=pending
  random()
end

function V.single(part,trigger,random)
  body(part,trigger,random)
  if trigger=="new_cargo" then body(part,"any_new_cargo",random) end
end

-- Train chain follows Vehicle::First()/Next(), not the direction in
-- which the consist happens to be moving. This includes no-capacity engines.
function V.chain(parts,at,trigger,random)
  if trigger=="new_cargo" then
    body(assert(parts[at]),trigger,random)
    for _,part in ipairs(parts) do body(part,"any_new_cargo",random) end
  elseif trigger=="depot" or trigger=="empty" then
    for _,part in ipairs(parts) do body(part,trigger,random) end
  else
    body(assert(parts[at]),trigger,random)
  end
end

function V.built(part,random)
  part.stock_vehicle_random_bits=random()%65536
end

return V
