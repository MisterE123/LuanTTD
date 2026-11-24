-- Pure presentation randomness; don't consume the simulation's RNG.
-- Numerical range fits exactly in Lua doubles on all supported maps.
return function(x,z)
  local h=(117*x*x+193*z*z+97*x*z+19801*x+38153*z)%104729
  h=(h*h+53471*h+7919)%104729
  return h%4,math.floor(h/4)%4,math.floor(h/16)%2
end
