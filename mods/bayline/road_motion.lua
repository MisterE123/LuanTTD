-- Render-only smoothing. It cannot change the road path, simulated travel
-- time, cargo or occupancy. Stations and the end of the route stay exact.
local M={}
local radius=.18 -- path units, or .36 native nodes at this scale
function M.corner(route,at,xy,allow)
  local k=math.floor(at+.5)
  if k<=1 or k>=#route or math.abs(at-k)>=radius then return end
  if allow and not allow(route[k]) then return end
  local ax,az=xy(route[k-1])
  local bx,bz=xy(route[k])
  local cx,cz=xy(route[k+1])
  local ux,uz=bx-ax,bz-az
  local vx,vz=cx-bx,cz-bz
  -- Only orthogonal half-road joins; portals and reversals are not arcs.
  if math.abs(ux)+math.abs(uz)~=1 or math.abs(vx)+math.abs(vz)~=1
      or ux*vx+uz*vz~=0 then return end
  local f=(at-(k-radius))/(2*radius)
  local q=1-f
  local x=bx+radius*(-q*q*ux+f*f*vx)
  local z=bz+radius*(-q*q*uz+f*f*vz)
  return x*2+.5,z*2+.5,q*ux+f*vx,q*uz+f*vz,route[k]
end
-- Resolve the shortest signed world turn before submitting it to the
-- visual engine. Bound each update even if a daily route step changes
-- heading abruptly; never ask the renderer to guess a spin direction.
-- Blender road models export noses along local -Z. With Luanti's
-- client mapping, (sin(model), -cos(model)) is their in-world nose.
-- Keep logical route yaw separate from the model's Euler angle.
function M.nose_yaw(route_yaw) return math.pi-route_yaw end
function M.turn(previous,target,step)
  if previous==nil then return target end
  local pi=math.pi
  local delta=(target-previous+pi)%(2*pi)-pi
  if math.abs(delta+pi)<1e-8 then delta=pi end
  return previous+math.max(-step,math.min(step,delta))
end
return M
