-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 vehicle.cpp ShowVisualEffect (stock diesel engine),
-- core/random_func.hpp Chance16I, and effectvehicle.cpp DieselSmokeTick.
local D={}
local floor=math.floor
D.DEFAULT_AMOUNT,D.LIFETIME=2,41

function D.sample(speed,limit,power,weight,amount,random)
  if amount==0 or speed<2 or speed>=floor(limit/2^(2-amount)) then return false end
  local contribution=floor(32/2^floor(power/1024))-floor(32/2^floor(weight/512))
  local a=64-floor(speed*32/limit)+contribution
  local b=floor(512/2^amount)
  return floor(((random()%65536)*b+floor(b/2))/65536)<a
end
return D
