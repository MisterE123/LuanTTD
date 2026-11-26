-- Decorative weather: shared prevailing cloud drift, slowly varying local
-- wind for scenery. Coordinates are Luanti +X/+Z; the vector points downwind.
local W={prevailing={x=1.1,z=.4}}
function W.sample(x,z,seconds)
  local t=seconds or 0
  local a=(x+z)*.003+t*.047
  local b=(x-z)*.002+t*.026
  local u=W.prevailing.x+.32*math.sin(b)
  local v=W.prevailing.z+.58*math.sin(a)
  return u,v,math.sqrt(u*u+v*v)
end
return W
